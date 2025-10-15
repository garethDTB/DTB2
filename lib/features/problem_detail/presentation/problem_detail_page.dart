// lib/features/problem_detail/presentation/problem_detail_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../hold_utils.dart';
import '../../../auth_state.dart';
import '../../../services/api_service.dart';
import '../../../services/websocket_service.dart';
import '../../../mirror_utils.dart';
import '../../../providers/problems_provider.dart';
import 'package:dtb2/hold_point.dart';

import 'widgets/wall_view.dart';
import 'widgets/action_buttons_row.dart';
import 'widgets/swipe_hint_arrow.dart';
import 'widgets/legend_bar.dart';

class ProblemDetailPage extends StatefulWidget {
  final String wallId;
  final Map<String, dynamic> problem;
  final List<Map<String, dynamic>> problems;
  final int initialIndex;
  final int numRows;
  final int numCols;
  final String gradeMode;

  const ProblemDetailPage({
    super.key,
    required this.wallId,
    required this.problem,
    required this.problems,
    required this.initialIndex,
    required this.numRows,
    required this.numCols,
    this.gradeMode = "french",
  });

  @override
  State<ProblemDetailPage> createState() => _ProblemDetailPageState();
}

class _ProblemDetailPageState extends State<ProblemDetailPage> {
  late int currentIndex;
  List<HoldPoint> holds = [];
  int footMode = 0;
  Map<String, String> footOptions = {};
  late double baseWidth;
  late double baseHeight;

  int _cols = 20;
  int _rows = 20;

  String gradeMode = "french";

  Map<String, int> _attemptCounts = {};

  bool _likedByUser = false;
  int _likesCount = 0;

  bool isMirrored = false;
  bool autoSendToBoard = false;

  File? wallImageFile;

  String? _swipeMessage;
  Color _swipeMessageColor = Colors.black87;

  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _cols = widget.numCols;
    _rows = widget.numRows;
    baseWidth = (widget.numCols >= 20) ? 1150.0 : 800.0;
    baseHeight = 750.0;

    _loadMirrorDic();
    _loadSettings();
    _loadHoldPositions();
    _loadGradeMode();
    _loadLikes();
    _loadWallImage();

    // 👇 listen to websocket messages
    _wsSub = ProblemUpdaterService.instance.messages.listen((msg) {
      if (!mounted) return;
      if (msg is Map && msg["type"] == 3) {
        _updateSwipeMessage("Displayed now", Colors.green, clearAfter: 2);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (autoSendToBoard) {
        _sendToBoard();
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMirrorDic() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/walls/${widget.wallId}/MirrorDic.txt');
      String raw;
      if (await file.exists()) {
        raw = await file.readAsString();
      } else {
        raw = await rootBundle.loadString('assets/walls/default/MirrorDic.txt');
      }
      MirrorUtils.setMirrorMap(Map<String, String>.from(jsonDecode(raw)));
    } catch (_) {}
  }

  Future<void> _loadWallImage() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/walls/${widget.wallId}/wall.png');
    if (await file.exists()) {
      setState(() => wallImageFile = file);
    }
  }

  Future<void> _loadGradeMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      gradeMode = prefs.getString('gradeMode') ?? widget.gradeMode;
      autoSendToBoard = prefs.getBool('autoSend') ?? false;

      if (autoSendToBoard) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _sendToBoard();
        });
      }
    });
  }

  Future<void> _loadSettings() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/walls/${widget.wallId}/Settings');
      String settingsRaw;
      if (await file.exists()) {
        settingsRaw = await file.readAsString();
      } else {
        settingsRaw = await rootBundle.loadString(
          'assets/walls/default/Settings',
        );
      }

      final lines = settingsRaw
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .toList();

      if (lines.length >= 2) {
        final cols = int.tryParse(lines[0]) ?? widget.numCols;
        final rows = int.tryParse(lines[1]) ?? widget.numRows;
        setState(() {
          _cols = cols;
          _rows = rows;
          baseWidth = (cols >= 20) ? 1150.0 : 800.0;
          baseHeight = 750.0;
        });
      }

      if (lines.length >= 7) {
        final v = int.tryParse(lines[6]);
        if (v != null && v >= 0 && v <= 2) {
          setState(() => footMode = v);
        }
      }

      if (lines.length >= 8 && lines[7].isNotEmpty) {
        final parts = lines[7].split(',').map((e) => e.trim()).toList();
        final opts = <String, String>{};
        for (int i = 0; i + 1 < parts.length; i += 2) {
          final token = parts[i];
          final name = parts[i + 1];
          if (token.isNotEmpty && name.isNotEmpty) {
            opts[token] = name;
          }
        }
        setState(() => footOptions = opts);
      }
    } catch (_) {}
  }

  Future<void> _loadHoldPositions() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/walls/${widget.wallId}/dicholdlist.txt');
      String data;
      if (await file.exists()) {
        data = await file.readAsString();
      } else {
        data = await rootBundle.loadString(
          'assets/walls/default/dicholdlist.txt',
        );
      }

      final Map<String, dynamic> decoded = jsonDecode(data);

      setState(() {
        holds = decoded.entries
            .where((e) => e.value is List && e.value.length >= 2)
            .map(
              (e) => HoldPoint(
                label: e.key,
                x: (e.value[0] as num).toDouble(),
                y: (e.value[1] as num).toDouble(),
              ),
            )
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _loadLikes() async {
    final api = context.read<ApiService>();
    final auth = context.read<AuthState>();
    final user = auth.username ?? "guest";
    final rawName = (widget.problems[currentIndex]['name'] as String? ?? '')
        .trim();

    try {
      final likes = await api.getWallLikes(widget.wallId, user);

      setState(() {
        _likesCount = (likes["aggregated"] as List)
            .where((e) => e["Problem"] == rawName)
            .map((e) => e["Count"] as int)
            .fold(0, (a, b) => a + b);
        _likedByUser = (likes["user"] as Map).containsKey(rawName);
      });
    } catch (_) {}
  }

  void nextProblem() {
    if (currentIndex < widget.problems.length - 1) {
      setState(() => currentIndex++);
      _loadLikes();
      if (autoSendToBoard) {
        _sendToBoard();
      }
    }
  }

  void prevProblem() {
    if (currentIndex > 0) {
      setState(() => currentIndex--);
      _loadLikes();
      if (autoSendToBoard) {
        _sendToBoard();
      }
    }
  }

  Color _colorForHoldType(String type) {
    switch (type) {
      case 'start':
        return Colors.green;
      case 'finish':
        return Colors.red;
      case 'feet':
        return Colors.yellow;
      default:
        return Colors.blue;
    }
  }

  void _updateSwipeMessage(String msg, Color bg, {int clearAfter = 0}) {
    setState(() {
      _swipeMessage = msg;
      _swipeMessageColor = bg;
    });
    if (clearAfter > 0) {
      Future.delayed(Duration(seconds: clearAfter), () {
        if (mounted && _swipeMessage == msg) {
          setState(() => _swipeMessage = null);
        }
      });
    }
  }

  List<Map<String, String>> _normalizeHolds(dynamic raw) {
    if (raw == null) return [];
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return raw.map<Map<String, String>>((e) {
        return {"type": e["type"].toString(), "label": e["label"].toString()};
      }).toList();
    }
    if (raw is List && raw.isNotEmpty && raw.first is String) {
      final strHolds = raw.cast<String>();
      final result = <Map<String, String>>[];
      int feetIndex = strHolds.indexWhere((h) => h.toLowerCase() == "feet");
      if (feetIndex != -1) {
        if (strHolds.length >= 2) {
          result.add({'type': 'start', 'label': strHolds[0]});
          result.add({'type': 'start', 'label': strHolds[1]});
        } else {
          result.add({'type': 'start', 'label': strHolds[0]});
        }
        if (feetIndex > 1) {
          result.add({'type': 'finish', 'label': strHolds[feetIndex - 1]});
        }
        for (int i = 2; i < feetIndex - 1; i++) {
          result.add({'type': 'intermediate', 'label': strHolds[i]});
        }
        for (int i = feetIndex + 1; i < strHolds.length; i++) {
          result.add({'type': 'feet', 'label': strHolds[i]});
        }
      } else {
        if (strHolds.length >= 2) {
          result.add({'type': 'start', 'label': strHolds[0]});
          result.add({'type': 'start', 'label': strHolds[1]});
        } else {
          result.add({'type': 'start', 'label': strHolds[0]});
        }
        if (strHolds.length > 3) {
          for (int i = 2; i < strHolds.length - 1; i++) {
            result.add({'type': 'intermediate', 'label': strHolds[i]});
          }
        }
        if (strHolds.length > 1) {
          result.add({'type': 'finish', 'label': strHolds.last});
        }
      }
      return result;
    }
    return [];
  }

  Future<void> _toggleLike(BuildContext context) async {
    final api = context.read<ApiService>();
    final auth = context.read<AuthState>();
    final wallId = widget.wallId;
    final user = auth.username ?? "guest";
    final rawName = (widget.problems[currentIndex]['name'] as String? ?? '')
        .trim();

    if (rawName.isEmpty) return;

    try {
      if (_likedByUser) {
        await api.removeLike(wallId, user, rawName);
        setState(() {
          _likedByUser = false;
          _likesCount = (_likesCount > 0) ? _likesCount - 1 : 0;
        });
      } else {
        await api.addLike(wallId, user, rawName);
        setState(() {
          _likedByUser = true;
          _likesCount += 1;
        });
      }
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  Future<void> _addAttempt(BuildContext context) async {
    final problem = widget.problems[currentIndex];
    final api = context.read<ApiService>();
    final auth = context.read<AuthState>();
    final provider = context.read<ProblemsProvider>();
    final wallId = widget.wallId;
    final user = auth.username ?? "guest";
    final rawName = (problem['name'] as String? ?? '').trim();

    if (rawName.isEmpty) return;
    if (provider.tickedProblemsToday.contains(rawName)) {
      _updateSwipeMessage(
        "Attempts not allowed after ticking today",
        Colors.orange,
        clearAfter: 2,
      );
      return;
    }
    try {
      await provider.addAttempt(api, wallId, user, problem);
      HapticFeedback.lightImpact();
      _updateSwipeMessage("Attempt logged", Colors.blue, clearAfter: 2);
    } catch (_) {
      _updateSwipeMessage("Failed to log attempt", Colors.red, clearAfter: 2);
    }
  }

  Future<void> _addTick(BuildContext context, {bool flash = false}) async {
    final problem = widget.problems[currentIndex];
    final api = context.read<ApiService>();
    final auth = context.read<AuthState>();
    final provider = context.read<ProblemsProvider>();
    final wallId = widget.wallId;
    final user = auth.username ?? "guest";

    try {
      await provider.addTick(api, wallId, user, problem);
      HapticFeedback.mediumImpact();
      _updateSwipeMessage(
        flash ? "Flash logged!" : "Tick logged",
        flash ? Colors.orange : Colors.green,
        clearAfter: 2,
      );
    } catch (_) {
      _updateSwipeMessage("Failed to log tick", Colors.red, clearAfter: 2);
    }
  }

  Future<void> _sendToBoard() async {
    final problem = widget.problems[currentIndex];
    final problemName = (problem['name'] ?? '').toString();
    final auth = context.read<AuthState>();
    final user = auth.username ?? "guest";
    _updateSwipeMessage("Sending… please wait", Colors.orange, clearAfter: 0);
    try {
      final prefs = await SharedPreferences.getInstance();
      final wallJson = prefs.getString('lastSelectedWall');
      if (wallJson == null) {
        _updateSwipeMessage("No wall info found", Colors.red, clearAfter: 2);
        return;
      }
      final wall = Map<String, dynamic>.from(jsonDecode(wallJson));
      final pos = await Geolocator.getCurrentPosition();
      final wallLat = double.tryParse(wall['lat'].toString()) ?? 0.0;
      final wallLon = double.tryParse(wall['lon'].toString()) ?? 0.0;
      final maxDistance = double.tryParse(wall['distance'].toString()) ?? 100.0;
      final distance = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        wallLat,
        wallLon,
      );
      if (distance > maxDistance) {
        _updateSwipeMessage(
          "Too far from wall (${distance.toStringAsFixed(1)} m)",
          Colors.red,
          clearAfter: 2,
        );
        return;
      }
      ProblemUpdaterService.instance.sendProblem(
        user,
        problemName,
        isMirrored,
        widget.wallId,
      );
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _swipeMessageColor == Colors.orange) {
          _updateSwipeMessage(
            "Send failed (timeout)",
            Colors.red,
            clearAfter: 2,
          );
        }
      });
    } catch (e) {
      _updateSwipeMessage("Send failed: $e", Colors.red, clearAfter: 2);
    }
  }

  // NEW: Load What's On from Azure
  Future<void> _loadWhatsOn() async {
    final api = context.read<ApiService>();
    try {
      final whatsOn = await api.getWhatsOn(widget.wallId);
      if (whatsOn == null) {
        _updateSwipeMessage(
          "No problem currently on",
          Colors.red,
          clearAfter: 2,
        );
        return;
      }

      final problemName = (whatsOn['Problem'] ?? '').trim();
      final idx = widget.problems.indexWhere(
        (p) => (p['name'] ?? '').trim() == problemName,
      );

      if (idx != -1) {
        setState(() {
          currentIndex = idx;
          isMirrored = whatsOn['IsMirrored'] ?? false;
        });
        _updateSwipeMessage(
          "Now showing: $problemName",
          Colors.green,
          clearAfter: 2,
        );
      } else {
        _updateSwipeMessage(
          "Problem not found locally",
          Colors.orange,
          clearAfter: 2,
        );
      }
    } catch (e) {
      _updateSwipeMessage(
        "Failed to load What's On",
        Colors.red,
        clearAfter: 2,
      );
    }
  }

  // ✅ Fixed: Only one _openComments now
  Future<void> _openComments() async {
    final problem = widget.problems[currentIndex];
    final auth = context.read<AuthState>();
    final user = auth.username ?? "guest";

    context.push(
      "/comments",
      extra: {
        "wallId": widget.wallId,
        "problemName": (problem['name'] ?? '').toString(),
        "user": user,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final problem = widget.problems[currentIndex];
    final holdsList = _normalizeHolds(problem['holds']);
    final grade = problem['grade'] ?? '';
    final rawName = problem['name'] ?? '';
    String titleText;
    if (gradeMode == "vgrade") {
      final cleanedName = rawName.replaceAll(grade, "").trim();
      titleText = "$cleanedName (${frenchToVGrade(grade)})";
    } else {
      titleText = rawName.contains(grade) ? rawName : "$rawName ($grade)";
    }
    final provider = context.watch<ProblemsProvider>();
    Color? headerColor;
    if (provider.tickedProblemsToday.contains(rawName)) {
      headerColor = Colors.green.shade100;
    } else if (provider.tickedProblemsPast.contains(rawName)) {
      headerColor = Colors.purple.shade100;
    } else if (provider.attemptedProblems.contains(rawName)) {
      headerColor = Colors.red.shade100;
    }
    final attemptCount = _attemptCounts[rawName] ?? 0;
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context);
        return true;
      },
      child: Scaffold(
        appBar: AppBar(backgroundColor: headerColor, title: Text(titleText)),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: WallView(
                  holds: holds,
                  holdsList: holdsList,
                  baseWidth: baseWidth,
                  baseHeight: baseHeight,
                  onSwipeLeft: nextProblem,
                  onSwipeRight: prevProblem,
                  colorForHoldType: _colorForHoldType,
                  isMirrored: isMirrored,
                  wallImageFile: wallImageFile,
                  cols: _cols,
                  rows: _rows,
                ),
              ),
              if (attemptCount > 0)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    "Attempts: $attemptCount",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              SizedBox(
                height: 40,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _swipeMessage != null
                      ? Container(
                          key: const ValueKey('banner'),
                          width: double.infinity,
                          color: _swipeMessageColor,
                          alignment: Alignment.center,
                          child: Text(
                            _swipeMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        )
                      : const SwipeHintArrow(key: ValueKey('hint')),
                ),
              ),
              ActionButtonsRow(
                likedByUser: _likedByUser,
                likesCount: _likesCount,
                onToggleLike: () => _toggleLike(context),
                onAttempt: () => _addAttempt(context),
                onTick: () => _addTick(context),
                onFlash: () => _addTick(context, flash: true),
                onSendToBoard: _sendToBoard,
                isMirrored: isMirrored,
                onMirrorToggle: () {
                  setState(() => isMirrored = !isMirrored);
                  HapticFeedback.selectionClick();
                  if (autoSendToBoard) {
                    _sendToBoard();
                  }
                },
                onWhatsOn: _loadWhatsOn,
                onComments: _openComments,
              ),
              const SizedBox(height: 8),
              LegendBar(footMode: footMode),
            ],
          ),
        ),
      ),
    );
  }
}
