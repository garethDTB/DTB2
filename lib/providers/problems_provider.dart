// lib/providers/problems_provider.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../hold_utils.dart';

enum ProblemFilterType { none, liked, attempted, ticked, notTicked, benchmarks }

enum ProblemSortType {
  grade,
  newest,
  oldest,
  mostAscents,
  leastAscents,
  mostLikes,
  leastLikes,
}

class ProblemsProvider extends ChangeNotifier {
  List<Map<String, dynamic>> allProblems = [];
  List<Map<String, dynamic>> filteredProblems = [];

  Set<String> attemptedProblems = {}; // 🔴 Attempts (today + past)
  Set<String> tickedProblemsPast = {}; // 🟣 Past ticks
  Set<String> tickedProblemsToday = {}; // 🟢 Today’s ticks
  String? selectedMinGrade;
  String? selectedMaxGrade;
  String gradeMode = "french";
  ProblemSortType selectedSort = ProblemSortType.grade;
  String? selectedGrade;
  Set<String> selectedHoldFilters = {};
  Set<String> selectedFootFilters = {};

  List<Map<String, String>> footFilterOptions = [];

  int numCols = 0;
  int numRows = 0;
  int footMode = 0;

  bool isLoading = false;
  bool hasLoaded = false;
  bool holdFilterMatchAll = true; // true = AND, false = OR

  Future<void> load(String wallId, ApiService api, String user) async {
    isLoading = true;
    hasLoaded = false; // <-- add this
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
      await _loadSessions(wallId, api, user); // ✅ hybrid
      await _loadSettings(wallId);

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

    int index = 0;

    allProblems = rawProblems.map<Map<String, dynamic>>((item) {
      final orderIndex = index++;
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
        'orderIndex': orderIndex,
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

  /// ✅ Hybrid session load: tries Azure first, falls back to local prefs
  Future<void> _loadSessions(String wallId, ApiService api, String user) async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> sessions = [];

    try {
      sessions = await api.getSessions(wallId, user);
      await prefs.setString("sessions_$wallId", jsonEncode(sessions));
      debugPrint("☁️ Loaded ${sessions.length} sessions from Azure");
    } catch (e) {
      final jsonString = prefs.getString("sessions_$wallId");
      if (jsonString != null) {
        sessions = (jsonDecode(jsonString) as List)
            .cast<Map<String, dynamic>>();
        debugPrint("📦 Loaded ${sessions.length} sessions from local cache");
      } else {
        debugPrint("⚠️ No local or remote sessions found for $wallId");
      }
    }

    final now = DateTime.now();
    final tmpAttempts = <String>{};
    final tmpTicksPast = <String>{};
    final tmpTicksToday = <String>{};

    for (var s in sessions) {
      final dateStr = s['Date'] ?? s['date'] ?? "";
      final sessionDate = DateTime.tryParse(dateStr);
      final isToday =
          sessionDate != null &&
          sessionDate.year == now.year &&
          sessionDate.month == now.month &&
          sessionDate.day == now.day;

      final attempts = (s['Attempts'] ?? []) as List;
      final sent = (s['Sent'] ?? []) as List;

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

  Future<void> _loadSettings(String wallId) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/walls/$wallId/Settings');

    final data = await file.exists()
        ? await file.readAsString()
        : await rootBundle.loadString('assets/walls/default/Settings');

    final lines = const LineSplitter().convert(data);

    numCols = int.tryParse(lines[0]) ?? 0;
    numRows = int.tryParse(lines[1]) ?? 0;

    footFilterOptions.clear();

    footMode = lines.length >= 7 ? int.tryParse(lines[6]) ?? 0 : 0;

    if (footMode == 1 && lines.length >= 8 && lines[7].trim().isNotEmpty) {
      final parts = lines[7].split(',').map((e) => e.trim()).toList();

      for (int i = 0; i + 1 < parts.length; i += 2) {
        final token = parts[i];
        final label = parts[i + 1];

        if (token.isNotEmpty && label.isNotEmpty) {
          footFilterOptions.add({"token": token, "label": label});
        }
      }
    }
  }

  void setHoldFilterMatchAll(bool value) {
    holdFilterMatchAll = value;
    filterProblems("", selectedGrade, extraFilter: ProblemFilterType.none);
  }

  void setFootFilters(Set<String> feet) {
    selectedFootFilters = Set<String>.from(feet);
    notifyListeners();
  }

  void clearFootFilters() {
    selectedFootFilters.clear();
    filterProblems("", selectedGrade, extraFilter: ProblemFilterType.none);
  }

  void toggleHoldFilter(String holdLabel) {
    if (selectedHoldFilters.contains(holdLabel)) {
      selectedHoldFilters.remove(holdLabel);
    } else {
      selectedHoldFilters.add(holdLabel);
    }

    filterProblems("", selectedGrade, extraFilter: ProblemFilterType.none);
  }

  void clearHoldFilters() {
    selectedHoldFilters.clear();
    filterProblems("", selectedGrade, extraFilter: ProblemFilterType.none);
  }

  void setHoldFilters(Set<String> holds) {
    selectedHoldFilters = Set<String>.from(holds);
    notifyListeners();
  }

  void _sortFilteredProblems() {
    filteredProblems.sort((a, b) {
      switch (selectedSort) {
        case ProblemSortType.newest:
          return (b['orderIndex'] ?? 0).compareTo(a['orderIndex'] ?? 0);

        case ProblemSortType.oldest:
          return (a['orderIndex'] ?? 0).compareTo(b['orderIndex'] ?? 0);

        case ProblemSortType.mostAscents:
          return (b['ticks'] ?? 0).compareTo(a['ticks'] ?? 0);

        case ProblemSortType.leastAscents:
          return (a['ticks'] ?? 0).compareTo(b['ticks'] ?? 0);

        case ProblemSortType.mostLikes:
          return (b['likesCount'] ?? 0).compareTo(a['likesCount'] ?? 0);

        case ProblemSortType.leastLikes:
          return (a['likesCount'] ?? 0).compareTo(b['likesCount'] ?? 0);

        case ProblemSortType.grade:
          final gA = a['grade'] ?? '';
          final gB = b['grade'] ?? '';
          final cmp = gradeSort(gA, gB);
          if (cmp != 0) return cmp;

          final popA = (a['ticks'] ?? 0) + (a['likesCount'] ?? 0);
          final popB = (b['ticks'] ?? 0) + (b['likesCount'] ?? 0);
          return popB.compareTo(popA);
      }
    });
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

      bool matchesGrade = true;

      if (selectedMinGrade != null && selectedMaxGrade != null) {
        final problemGrade = problem['grade'] ?? '';

        matchesGrade =
            gradeSort(problemGrade, selectedMinGrade!) >= 0 &&
            gradeSort(problemGrade, selectedMaxGrade!) <= 0;
      } else {
        matchesGrade =
            grade == null || grade.isEmpty || problem['grade'] == grade;
      }

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
      final problemHoldLabels = ((problem['holds'] ?? []) as List)
          .map((h) => (h['label'] ?? '').toString())
          .toSet();

      final matchesHoldFilter =
          selectedHoldFilters.isEmpty ||
          (holdFilterMatchAll
              ? selectedHoldFilters.every(
                  (hold) => problemHoldLabels.contains(hold),
                )
              : selectedHoldFilters.any(
                  (hold) => problemHoldLabels.contains(hold),
                ));

      final matchesFootFilter =
          selectedFootFilters.isEmpty ||
          selectedFootFilters.every((foot) => problemHoldLabels.contains(foot));

      return matchesQuery &&
          matchesGrade &&
          matchesExtra &&
          matchesHoldFilter &&
          matchesFootFilter;
    }).toList();

    _sortFilteredProblems();

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

  /// ✅ True if any filter, search, or grade restriction is currently applied
  bool get isFilterActive {
    return filteredProblems.length != allProblems.length ||
        (selectedGrade != null && selectedGrade!.isNotEmpty) ||
        selectedHoldFilters.isNotEmpty;
  }

  /// ✅ Clears all filters and restores the full problem list
  void clearFilters() {
    filteredProblems = List.from(allProblems);
    selectedGrade = null;
    selectedMinGrade = null;
    selectedMaxGrade = null;
    selectedHoldFilters.clear();
    selectedFootFilters.clear();
    notifyListeners();
  }
}
