import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../hold_utils.dart';

enum ProblemFilterType { none, liked, attempted, ticked, notTicked, benchmarks }

class ProblemsProvider extends ChangeNotifier {
  List<Map<String, dynamic>> allProblems = [];
  List<Map<String, dynamic>> filteredProblems = [];

  Set<String> attemptedProblems = {}; // 🔴 Attempts (today + past)
  Set<String> tickedProblemsPast = {}; // 🟣 Past ticks
  Set<String> tickedProblemsToday = {}; // 🟢 Today’s ticks

  String gradeMode = "french";
  String? selectedGrade;

  int numCols = 0;
  int numRows = 0;

  bool isLoading = false;
  bool hasLoaded = false;

  Future<void> load(String wallId, ApiService api) async {
    isLoading = true;
    notifyListeners();

    // ✅ Reset all state before loading new wall
    allProblems = [];
    filteredProblems = [];
    attemptedProblems = {};
    tickedProblemsPast = {};
    tickedProblemsToday = {};
    selectedGrade = null;

    try {
      await _loadSettingsPrefs();
      await _loadProblems(wallId, api);
      await _loadTicks(wallId);
      await _loadLikes(wallId);
      await _loadSessions(wallId);
      await _loadSettings();

      filterProblems("", selectedGrade, extraFilter: ProblemFilterType.none);
    } finally {
      isLoading = false;
      hasLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _loadSettingsPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    gradeMode = prefs.getString('gradeMode') ?? "french";
  }

  Future<File> _getCsvFile(String wallId) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/$wallId.csv");
    if (!await file.exists()) {
      try {
        final data = await rootBundle.loadString(
          'assets/walls/default/$wallId.csv',
        );
        await file.writeAsString(data);
      } catch (_) {
        final fallback = await rootBundle.loadString(
          'assets/walls/default/test.csv',
        );
        await file.writeAsString(fallback);
      }
    }
    return file;
  }

  Future<void> _loadProblems(String wallId, ApiService api) async {
    final rawProblems = await api.getWallProblems(wallId);
    debugPrint(
      "📥 ProblemsProvider: got ${rawProblems.length} problems for wall $wallId",
    );

    allProblems = rawProblems.map<Map<String, dynamic>>((item) {
      final holds = <Map<String, String>>[
        ...(item['StartHolds'] ?? []).map(
          (h) => {'type': 'start', 'label': h.toString()},
        ),
        ...(item['IntermediateHolds'] ?? []).map(
          (h) => {'type': 'intermediate', 'label': h.toString()},
        ),
        if (item['FinishHold'] != null)
          {'type': 'finish', 'label': item['FinishHold'].toString()},
      ];

      return {
        'name': item['Problem'] ?? '',
        'grade': item['Grade'] ?? '',
        'comment': item['Comment'] ?? '',
        'setter': item['Setter'] ?? '',
        'stars': item['Stars'] ?? 0,
        'holds': _normalizeHolds(holds),
        'ticks': 0,
        'likesCount': 0,
        'likedByUser': false,
      };
    }).toList();

    filterProblems("", selectedGrade, extraFilter: ProblemFilterType.none);
  }

  /// ✅ Ensure holds are always a List<Map<String,String>>
  List<Map<String, String>> _normalizeHolds(dynamic raw) {
    if (raw == null || raw is! List || raw.isEmpty) return [];

    if (raw.first is Map) {
      return raw.map<Map<String, String>>((e) {
        return {
          "type": (e["type"] ?? "").toString(),
          "label": (e["label"] ?? "").toString(),
        };
      }).toList();
    }

    if (raw.first is String) {
      return raw.map<Map<String, String>>((h) {
        return {"type": "intermediate", "label": h.toString()};
      }).toList();
    }

    return [];
  }

  Future<void> _loadTicks(String wallId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString("ticks_$wallId");
    if (jsonString == null) return;

    final List<dynamic> ticks = jsonDecode(jsonString);
    final tickMap = {
      for (var t in ticks) (t['Problem'] as String).trim(): t['Count'],
    };
    for (var problem in allProblems) {
      final rawName = (problem['name'] as String? ?? '').trim();
      problem['ticks'] = tickMap[rawName] ?? 0;
    }
  }

  Future<void> _loadLikes(String wallId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString("likes_$wallId");
    if (jsonString == null) return;

    final Map<String, dynamic> decoded = jsonDecode(jsonString);
    final List<dynamic> aggregated = decoded['aggregated'] ?? [];
    final Map<String, dynamic> user = decoded['user'] ?? {};

    final likeMap = {
      for (var l in aggregated)
        (l['Problem'] as String).trim().toLowerCase(): l['Count'] as int,
    };
    final likedByUserSet = user.keys.map((p) => p.trim().toLowerCase()).toSet();

    for (var problem in allProblems) {
      final rawName = (problem['name'] as String? ?? '').trim().toLowerCase();
      problem['likesCount'] = likeMap[rawName] ?? 0;
      problem['likedByUser'] = likedByUserSet.contains(rawName);
    }
  }

  /// ✅ Restores attempts (all = red), ticks (today = green, past = purple)
  Future<void> _loadSessions(String wallId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString("sessions_$wallId");
    if (jsonString == null) return;

    final List<dynamic> raw = jsonDecode(jsonString);
    final now = DateTime.now();

    final tmpAttempts = <String>{};
    final tmpTicksPast = <String>{};
    final tmpTicksToday = <String>{};

    for (var s in raw) {
      final dateStr = s['Date'] ?? s['date'] ?? "";
      final sessionDate = DateTime.tryParse(dateStr);
      final isToday =
          sessionDate != null &&
          sessionDate.year == now.year &&
          sessionDate.month == now.month &&
          sessionDate.day == now.day;

      final attempts = (s['Attempts'] ?? s['attempts'] ?? []) as List;
      final sent = (s['Sent'] ?? s['ticks'] ?? []) as List;

      for (var a in attempts) {
        tmpAttempts.add((a['Problem'] as String).trim());
      }

      for (var t in sent) {
        final name = (t['Problem'] as String).trim();
        if (isToday) {
          tmpTicksToday.add(name);
        } else {
          tmpTicksPast.add(name);
        }
      }
    }

    attemptedProblems = tmpAttempts;
    tickedProblemsPast = tmpTicksPast;
    tickedProblemsToday = tmpTicksToday;
  }

  Future<void> _loadSettings() async {
    final data = await rootBundle.loadString('assets/walls/default/Settings');
    final lines = const LineSplitter().convert(data);
    numCols = int.tryParse(lines[0]) ?? 0;
    numRows = int.tryParse(lines[1]) ?? 0;
  }

  void filterProblems(
    String query,
    String? grade, {
    ProblemFilterType extraFilter = ProblemFilterType.none,
  }) {
    final q = query.toLowerCase();
    final queryFrench = vToFrench(query);

    filteredProblems = allProblems.where((problem) {
      final matchesQuery =
          query.isEmpty ||
          (problem['name']?.toLowerCase().contains(q) ?? false) ||
          (problem['setter']?.toLowerCase().contains(q) ?? false) ||
          (problem['grade']?.toLowerCase().contains(q) ?? false) ||
          (problem['grade']?.toLowerCase().contains(
                queryFrench.toLowerCase(),
              ) ??
              false) ||
          (problem['comment']?.toLowerCase().contains(q) ?? false);

      final matchesGrade =
          grade == null || grade.isEmpty || problem['grade'] == grade;

      final rawName = (problem['name'] as String? ?? '').trim();

      final matchesExtra = switch (extraFilter) {
        ProblemFilterType.none => true,
        ProblemFilterType.liked => problem['likedByUser'] == true,
        ProblemFilterType.ticked =>
          tickedProblemsToday.contains(rawName) ||
              tickedProblemsPast.contains(rawName),
        ProblemFilterType.attempted =>
          attemptedProblems.contains(rawName) &&
              !tickedProblemsToday.contains(rawName) &&
              !tickedProblemsPast.contains(rawName),
        ProblemFilterType.notTicked =>
          !tickedProblemsToday.contains(rawName) &&
              !tickedProblemsPast.contains(rawName),
        ProblemFilterType.benchmarks =>
          (problem['comment']?.toLowerCase().contains("benchmark") ?? false),
      };

      return matchesQuery && matchesGrade && matchesExtra;
    }).toList();

    filteredProblems.sort((a, b) {
      final gA = a['grade'] ?? '';
      final gB = b['grade'] ?? '';
      final cmp = gradeSort(gA, gB);
      if (cmp != 0) return cmp;

      final popA = (a['ticks'] ?? 0) + (a['likesCount'] ?? 0);
      final popB = (b['ticks'] ?? 0) + (b['likesCount'] ?? 0);
      return popB.compareTo(popA);
    });

    notifyListeners();
  }

  int gradeSort(String a, String b) {
    const order = ["a", "a+", "b", "b+", "c", "c+"];
    final re = RegExp(r'^(\d+)([abc]\+?)$');
    String normalize(String g) => g.trim().toLowerCase();
    final ma = re.firstMatch(normalize(a));
    final mb = re.firstMatch(normalize(b));
    if (ma == null || mb == null) return a.compareTo(b);
    final numA = int.tryParse(ma.group(1)!) ?? 0;
    final sufA = order.indexOf(ma.group(2)!);
    final numB = int.tryParse(mb.group(1)!) ?? 0;
    final sufB = order.indexOf(mb.group(2)!);
    if (numA != numB) return numA.compareTo(numB);
    return sufA.compareTo(sufB);
  }

  Future<void> toggleLike(
    ApiService api,
    String wallId,
    String user,
    Map<String, dynamic> problem,
  ) async {
    if (problem['likedByUser'] == true) {
      await api.removeLike(wallId, user, problem['name'] ?? '');
      problem['likedByUser'] = false;
      problem['likesCount'] = (problem['likesCount'] ?? 1) - 1;
      if (problem['likesCount'] < 0) problem['likesCount'] = 0;
    } else {
      await api.addLike(wallId, user, problem['name'] ?? '');
      problem['likedByUser'] = true;
      problem['likesCount'] = (problem['likesCount'] ?? 0) + 1;
    }
    notifyListeners();
  }

  Future<void> addTick(
    ApiService api,
    String wallId,
    String user,
    Map<String, dynamic> problem,
  ) async {
    await api.addTick(
      wallId,
      user,
      problem['name'] ?? '',
      problem['grade'] ?? '',
      getPointsForGrade(problem['grade'] ?? ''),
      flash: false,
    );
    await api.updateTick(wallId, problem['name'] ?? '', 1);
    problem['ticks'] = (problem['ticks'] ?? 0) + 1;
    tickedProblemsToday.add(problem['name'] ?? '');
    notifyListeners();
  }

  Future<void> addAttempt(
    ApiService api,
    String wallId,
    String user,
    Map<String, dynamic> problem,
  ) async {
    await api.addAttempt(
      wallId,
      user,
      problem['name'] ?? '',
      problem['grade'] ?? '',
    );

    attemptedProblems.add(problem['name'] ?? '');
    notifyListeners();
  }
}
