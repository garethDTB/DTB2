import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_service.dart';
import 'services/draft_service.dart'; // 👈 new import
import 'auth_state.dart';
import 'hold_utils.dart';
import 'services/websocket_service.dart';
import 'package:collection/collection.dart';
import 'package:dtb2/services/hold_loader.dart';
import 'services/problem_services.dart';
import 'dart:math';

// ---------------- ENUMS ----------------

enum ConfirmStage { none, start1, start2, finish, feet, review }

enum FootMode { mark, auto }

// ---------------- MODELS ----------------

class HoldPoint {
  final String label;
  final double x;
  final double y;
  const HoldPoint({required this.label, required this.x, required this.y});
}

class FootOption {
  final String holdToken;
  final String label;
  const FootOption(this.holdToken, this.label);
}

// ---------------- PAGE ----------------

class CreateProblemPage extends StatefulWidget {
  final String wallId;
  final bool isDraftMode;
  final List<String>? draftRow;

  // 👇 new: for editing published problems
  final bool isEditing;

  final List<String> superusers;

  final List<String>? problemRow;

  const CreateProblemPage({
    super.key,
    required this.wallId,
    this.isDraftMode = false,
    this.draftRow,

    this.isEditing = false,
    this.problemRow,
    this.superusers = const [],
  });

  @override
  State<CreateProblemPage> createState() => _CreateProblemPageState();
}

class _CreateProblemPageState extends State<CreateProblemPage> {
  bool get editingDraft => widget.isDraftMode && widget.draftRow != null;
  bool get editingProblem => widget.isEditing && widget.problemRow != null;
  int rows = 18;
  int cols = 14;
  double baseWidth = 1150.0;
  double baseHeight = 750.0;
  bool autoSend = false;
  Timer? _sendConfirmTimer;
  bool _awaitingSendConfirm = false;
  final Set<int> selected = {};
  final List<int> selectionOrder = [];
  StreamSubscription? _wsSub;
  ConfirmStage confirmStage = ConfirmStage.none;
  int? cStart1;
  int? cStart2;
  int? cFinish;
  String confirmLabel = "Please select holds";
  String? originalFullName;
  int footMode = 0;
  List<FootOption> footOptions = [];
  final Set<int> feetSelected = {};
  List<String> footMode1TokensSelected = [];

  List<HoldPoint> holds = [];

  int minGradeNum = 4;
  File? wallImageFile;

  late DraftService draftService; // 👈 new service

  static const bool kHoldDebug = true;

  void _debugHoldTap(String label) {
    if (!kHoldDebug) return;
    final wsIndex = tryWsIndexFromLabel(label, cols, rows);
    final holdId = (wsIndex == null) ? "<invalid>" : "hold$wsIndex";
    debugPrint("🔎 TAP  label=$label -> $holdId (ws=$wsIndex)");
  }

  void _debugWsSelection(int wsIndex) {
    if (!kHoldDebug) return;
    final holdId = "hold$wsIndex";
    final label = labelForWs(wsIndex, cols, rows);
    debugPrint("🧩 SAVE-SEL  ws=$wsIndex -> $holdId (label=$label)");
  }

  Future<void> _sendToBoardWithFeedback() async {
    if (!mounted) return;
    _sendConfirmTimer?.cancel();
    _sendConfirmTimer = null;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("📡 Sending to board…"),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );

    _awaitingSendConfirm = true;
    _sendPreviewToWall();

    _sendConfirmTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (_awaitingSendConfirm) {
        _awaitingSendConfirm = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Send failed (timeout)"),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();

    // --- editing problem case ---
    final editing = widget.isEditing;
    final row = widget.problemRow;
    if (editing && row != null) {
      final oldId = row[0]; // this is now the Cosmos id
      final oldName = row[1]; // name
      final oldGrade = row[2]; // grade
      originalFullName = "$oldName $oldGrade";
      debugPrint("✏️ Editing problem id=$oldId name=$originalFullName");
    }

    // --- common init setup ---
    draftService = DraftService(widget.wallId, cols: cols, rows: rows);
    Future.wait([
      _loadSettings(),
      _loadHoldPositions(),
      _loadWallImage(),
      _loadUserPrefs(),
    ]).then((_) {
      _restoreSelection();
    });
    // --- WebSocket listener ---
    _wsSub = ProblemUpdaterService.instance.messages.listen((msg) {
      if (!mounted) return;
      if (msg is Map && msg["type"] == 3) {
        if (_awaitingSendConfirm) {
          _sendConfirmTimer?.cancel();
          _sendConfirmTimer = null;
          _awaitingSendConfirm = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Sent to board successfully"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _sendConfirmTimer?.cancel();
    super.dispose();
  }

  // ---------------- LOADERS ----------------

  Future<void> _loadUserPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      autoSend = prefs.getBool('autoSend') ?? false;
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
        cols = int.tryParse(lines[0]) ?? cols;
        rows = int.tryParse(lines[1]) ?? rows;
        baseWidth = (cols >= 20) ? 1150.0 : 800.0;
        baseHeight = 750.0;
      }

      if (lines.length >= 7) {
        final v = int.tryParse(lines[6]);
        if (v != null && v >= 0 && v <= 2) footMode = v;
      }

      if (lines.length >= 8 && lines[7].isNotEmpty) {
        final parts = lines[7].split(',').map((e) => e.trim()).toList();
        footOptions.clear();
        for (int i = 0; i + 1 < parts.length; i += 2) {
          final token = parts[i];
          final name = parts[i + 1];
          if (token.isNotEmpty && name.isNotEmpty) {
            footOptions.add(FootOption(token, name));
          }
        }
      }

      if (lines.length >= 13) {
        final g = int.tryParse(lines[12]);
        if (g != null && (g == 4 || g == 5 || g == 6)) minGradeNum = g;
      }

      setState(() {});
    } catch (e) {
      debugPrint("❌ Settings load failed: $e");
    }
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
      holds.clear();
      decoded.forEach((label, val) {
        if (val is List && val.length >= 2) {
          final x = (val[0] as num).toDouble();
          final y = (val[1] as num).toDouble();
          if (x < 0 || y < 0) return;
          holds.add(HoldPoint(label: label, x: x, y: y));
        }
      });

      setState(() {});
    } catch (e) {
      debugPrint("❌ Hold positions load failed: $e");
    }
  }

  Future<void> _loadWallImage() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/walls/${widget.wallId}/wall.png');
      if (await file.exists()) {
        wallImageFile = file;
      }
      setState(() {});
    } catch (e) {
      debugPrint("❌ Wall image load failed: $e");
    }
  }

  // ---------------- DRAFT RESTORE ----------------

  void _restoreSelection() {
    selected.clear();
    selectionOrder.clear();

    List<dynamic>? holdsPart;

    if (editingDraft && widget.draftRow != null) {
      debugPrint("📥 Restoring from draft → ${widget.draftRow}");
      holdsPart = widget.draftRow!.sublist(5);
    } else if (editingProblem && widget.problemRow != null) {
      debugPrint("📥 Restoring from problem → ${widget.problemRow}");
      holdsPart = widget.problemRow!.sublist(
        6,
      ); // skip id, name, grade, comment, setter, stars
      if (originalFullName == null && widget.problemRow!.length > 2) {
        originalFullName = "${widget.problemRow![1]} ${widget.problemRow![2]}";
      }
    }

    if (holdsPart != null) {
      for (final raw in holdsPart) {
        String? label;

        // Case 1: already a Map
        if (raw is Map && raw.containsKey("label")) {
          label = raw["label"] as String?;
          debugPrint("   ↳ Map detected → $raw → label=$label");
        }
        // Case 2: String that looks like a Map "{type:..., label:...}"
        else if (raw is String &&
            raw.startsWith("{") &&
            raw.contains("label:")) {
          final fixed = raw
              .replaceAll(RegExp(r'type:\s*'), '"type": "')
              .replaceAll(RegExp(r', label:\s*'), '", "label": "')
              .replaceAll("}", '"}');
          try {
            final parsed = Map<String, dynamic>.from(jsonDecode(fixed));
            label = parsed["label"] as String?;
            debugPrint("   ↳ Parsed string-map → $parsed → label=$label");
          } catch (e) {
            debugPrint("⚠️ Failed to parse string-map $raw → $e");
          }
        }
        // Case 3: plain string like "A4" or "hold23"
        else if (raw is String) {
          label = raw;
          debugPrint("   ↳ Plain string detected → $label");
        }

        if (label == null) {
          debugPrint("⚠️ Could not extract label from $raw");
          continue;
        }

        // Convert "hold23" → "A4/B8/..."
        if (label.startsWith("hold")) {
          final ws = int.tryParse(label.substring(4));
          if (ws != null) {
            label = labelForWs(ws, cols, rows);
            debugPrint("   ↳ Converted hold → $label");
          }
        }

        // Map to ws index
        final ws = tryWsIndexFromLabel(label, cols, rows);
        debugPrint("   ↳ Final $label => wsIndex=$ws");

        if (ws != null) {
          selected.add(ws);
          selectionOrder.add(ws);
        } else {
          debugPrint("⚠️ Could not map label '$label' to a hold index!");
        }
      }
    }

    setState(() {});

    // ✅ Special case: auto-send active
    if (autoSend && selectionOrder.isNotEmpty) {
      _sendToBoardWithFeedback();
    }
  }

  // ---------------- SELECTION ----------------

  void toggleByLabel(String label) {
    _debugHoldTap(label);

    final ws = tryWsIndexFromLabel(label, cols, rows);
    if (ws == null) return;

    if (confirmStage == ConfirmStage.feet) {
      if (!_remainingForFeet().contains(ws)) return;
      if (feetSelected.contains(ws)) {
        feetSelected.remove(ws);
      } else {
        feetSelected.add(ws);
      }
      setState(() {});
      if (autoSend) {
        _sendToBoardWithFeedback();
      }
      return;
    }

    if (confirmStage != ConfirmStage.none) return;

    if (selected.contains(ws)) {
      selected.remove(ws);
      selectionOrder.remove(ws);
    } else {
      selected.add(ws);
      selectionOrder.add(ws);
    }
    setState(() {});
    if (autoSend) {
      _sendToBoardWithFeedback();
    }
  }

  void clearSelection() {
    selected.clear();
    selectionOrder.clear();
    cStart1 = cStart2 = cFinish = null;
    feetSelected.clear();
    confirmStage = ConfirmStage.none;
    confirmLabel = "Please select holds";
    footMode1TokensSelected = [];
    setState(() {});
  }

  void beginConfirmation() {
    if (selectionOrder.isEmpty) {
      confirmLabel = "Select holds first.";
      setState(() {});
      return;
    }
    cStart1 = cStart2 = cFinish = null;
    feetSelected.clear();
    footMode1TokensSelected = [];
    confirmStage = ConfirmStage.start1;
    confirmLabel = "Confirm Start hold (tap one of your selected holds)";
    setState(() {});
  }

  void handleConfirmTap(int ws) {
    if (!selectionOrder.contains(ws)) return;

    if (confirmStage == ConfirmStage.start1) {
      cStart1 = ws;
      confirmStage = ConfirmStage.start2;
      confirmLabel =
          "Confirm second Start: tap same again for one-handed, or another for two-handed";
    } else if (confirmStage == ConfirmStage.start2) {
      cStart2 = ws;
      confirmStage = ConfirmStage.finish;
      confirmLabel = "Confirm Finish hold";
    } else if (confirmStage == ConfirmStage.finish) {
      if (ws == cStart1 || ws == cStart2) {
        confirmLabel = "! Finish cannot be the same as a Start hold";
      } else {
        cFinish = ws;
        if (footMode == 2) {
          confirmStage = ConfirmStage.feet;
          confirmLabel =
              "Select FEET holds (yellow). Tap blue holds to toggle, then press ✓";
        } else {
          confirmStage = ConfirmStage.review;
          confirmLabel = "Review selection and press Save";
        }
      }
    }
    setState(() {});
  }

  List<int> _remainingForFeet() {
    final starts = <int>[];
    if (cStart1 != null) starts.add(cStart1!);
    if (cStart2 != null) starts.add(cStart2!);
    final fin = cFinish;
    return selectionOrder
        .where((ws) => !starts.contains(ws) && ws != fin)
        .toList();
  }

  void proceedFromFeetToReview() {
    if (confirmStage != ConfirmStage.feet) return;
    confirmStage = ConfirmStage.review;
    confirmLabel = "Review selection";
    setState(() {});
  }

  List<int> finalConfirmedOrder() {
    final starts = <int>[];
    if (cStart1 != null) starts.add(cStart1!);
    if (cStart2 != null) starts.add(cStart2!);
    if (starts.length == 1) starts.add(starts.first);

    final fin = cFinish;
    final middle = selectionOrder
        .where((ws) => !starts.contains(ws) && ws != fin)
        .toList();

    final all = <int>[];
    all.addAll(starts);
    all.addAll(middle);
    if (fin != null) all.add(fin);
    return all;
  }

  // ---------------- FILE I/O ----------------

  Future<File> _getCsvFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File("${dir.path}/${widget.wallId}.csv");
  }

  Future<void> _appendToCsv(List<String> row) async {
    final file = await _getCsvFile();
    final sink = file.openWrite(mode: FileMode.append);
    sink.writeln(row.join("\t"));
    await sink.flush();
    await sink.close();
  }

  Future<File> _getDraftsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File("${dir.path}/${widget.wallId}_drafts.csv");
  }

  Future<void> _appendToDrafts(List<String> row) async {
    final file = await _getDraftsFile();

    final holds = row.length > 5 ? row.sublist(5) : const <String>[];

    if (await file.exists()) {
      final lines = await file.readAsLines();
      if (lines.length >= 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ You can only keep 10 drafts. Delete one first."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // 📝 Consistent debug output
    debugPrint("💾 DRAFT SAVE → '${row[0]}' with ${holds.length} holds");
    for (final h in holds) {
      final ws = tryWsIndexFromLabel(h, cols, rows);
      debugPrint("   ↳ $h => wsIndex=$ws");
    }

    final sink = file.openWrite(mode: FileMode.append);
    sink.writeln(row.join("\t")); // <-- save raw labels
    await sink.flush();
    await sink.close();
  }

  // ---------------- DUPLICATE CHECKS ----------------

  Future<bool> _isDuplicate(String nameWithGrade) async {
    final file = await _getCsvFile();
    if (!await file.exists()) return false;

    final target = nameWithGrade.trim().toLowerCase();
    final lines = await file.readAsLines();

    for (final line in lines) {
      final parts = line.split("\t");
      if (parts.length > 1 && parts[1].trim().toLowerCase() == target) {
        return true;
      }
    }
    return false;
  }

  Future<String?> _isDuplicateHoldSet(List<String> newLabels) async {
    final file = await _getCsvFile();
    if (!await file.exists()) return null;

    final newSet = [...newLabels]..sort();
    final lines = await file.readAsLines();

    for (final line in lines) {
      final parts = line.split("\t");
      if (parts.length < 7)
        continue; // id + name + grade + comment + setter + stars + holds
      final existingName = parts[1]; // name is at index 1 now
      final existingHolds = parts.sublist(6); // holds start at index 6
      final existingSet = [...existingHolds]..sort();

      if (newSet.length == existingSet.length &&
          ListEquality().equals(newSet, existingSet)) {
        return existingName;
      }
    }
    return null;
  }

  // ---------------- PREVIEW TO WALL ----------------

  void _sendPreviewToWall() {
    final labels = selectionOrder
        .map((ws) => labelForWs(ws, cols, rows))
        .toList();
    if (labels.isEmpty) return;

    if (kHoldDebug) {
      final pairs = <String>[];
      for (final ws in selectionOrder) {
        pairs.add("${labelForWs(ws, cols, rows)}→hold$ws");
      }
      debugPrint("💡 PREVIEW  ${pairs.join(', ')}");
    }

    final message = "New problem being created by ${labels.join(" ")}";

    ProblemUpdaterService.instance.sendProblem(
      "",
      message,
      false,
      widget.wallId,
    );
  }
  // ---------------- REVIEW & SAVE ----------------

  void openReviewDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ConfirmReviewDialog(
        onBack: () {
          Navigator.pop(context);
          beginConfirmation();
        },
        onContinue: () {
          Navigator.pop(context);
          showDialog(
            context: context,
            builder: (_) => SaveProblemDialog(
              minGradeNum: minGradeNum,
              footMode: footMode,
              footOptions: footOptions,
              editingDraft: editingDraft,
              editingProblem: editingProblem,
              problemRow: widget.problemRow,
              superusers: widget.superusers,
              onSave:
                  (
                    String name,
                    String comment,
                    String grade,
                    int stars,
                    List<String> feetTokens, {
                    bool draft = false,
                    bool delete = false,
                  }) async {
                    final api = context.read<ApiService>();
                    final confirmed = finalConfirmedOrder();
                    final labels = confirmed
                        .map((ws) => labelForWs(ws, cols, rows))
                        .toList();

                    final auth = context.read<AuthState>();
                    final setter = auth.username ?? "me";
                    final fullName = "$name $grade";

                    // ---------------- DELETE BRANCH ----------------
                    if (delete) {
                      if (editingProblem && widget.problemRow != null) {
                        String? oldId = widget.problemRow?[0]?.toString();

                        if (oldId == null || oldId.isEmpty) {
                          final problemName = widget.problemRow![1];
                          oldId = await api.getProblemIdByName(
                            widget.wallId,
                            problemName,
                          );
                        }

                        if (oldId != null && oldId.isNotEmpty) {
                          try {
                            await api.deleteProblem(widget.wallId, oldId);
                            debugPrint("🗑️ Deleted from API: $oldId");
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("🗑️ Problem Deleted"),
                                  backgroundColor: Colors.red,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          } catch (e) {
                            debugPrint("⚠️ Failed to delete: $e");
                          }
                        }
                      }
                      return; // stop here
                    }

                    // ---------------- VALIDATION ----------------
                    if (name.trim().isEmpty) return;
                    if (confirmed.isEmpty) return;
                    if (cStart1 == null && cStart2 == null) return;
                    if (cFinish == null) return;

                    // ✅ Skip duplicate checks if editing
                    if (!draft && !editingProblem) {
                      if (await _isDuplicate(fullName)) return;
                      final dupProblem = await _isDuplicateHoldSet(labels);
                      if (dupProblem != null) return;
                    }

                    // ---------------- STARTS / FINISH / INTERMEDIATES ----------------
                    final starts = <String>[];
                    if (cStart1 != null)
                      starts.add(labelForWs(cStart1!, cols, rows));
                    if (cStart2 != null)
                      starts.add(labelForWs(cStart2!, cols, rows));

                    final finish = cFinish != null
                        ? labelForWs(cFinish!, cols, rows)
                        : "";

                    final intermediates = labels
                        .where((l) => !starts.contains(l) && l != finish)
                        .toList();

                    // feetMode=2 → add "feet" marker + selected foot holds
                    if (footMode == 2 && feetSelected.isNotEmpty) {
                      intermediates.add("feet");
                      intermediates.addAll(feetSelected.map((ws) => "hold$ws"));
                    }

                    // feetMode=1 → add tokens from dialog
                    if (footMode == 1 && feetTokens.isNotEmpty) {
                      intermediates.addAll(feetTokens);
                    }

                    // ---------------- DRAFT BRANCH ----------------
                    if (draft) {
                      final success = await draftService.appendDraft(
                        finalConfirmedOrder(),
                        fullName: fullName,
                        grade: grade,
                        comment: comment,
                        setter: setter,
                        stars: stars,
                        feetTokens: intermediates.contains("feet")
                            ? intermediates.sublist(
                                intermediates.indexOf("feet") + 1,
                              )
                            : feetTokens,
                        footMode: footMode,
                      );
                      if (!success && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "⚠️ You can only keep 10 drafts. Delete one first.",
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                      return; // stop draft save
                    }

                    // ---------------- EDITING BRANCH ----------------
                    if (editingProblem && widget.problemRow != null) {
                      var oldId = widget.problemRow?[0]?.toString();
                      if (oldId == null || oldId.isEmpty) {
                        final problemName = widget.problemRow![1];
                        try {
                          oldId = await api.getProblemIdByName(
                            widget.wallId,
                            problemName,
                          );
                        } catch (_) {}
                      }

                      if (oldId != null && oldId.isNotEmpty) {
                        try {
                          await api.deleteProblem(widget.wallId, oldId);
                        } catch (_) {}
                      }

                      await api.saveProblem(
                        widget.wallId,
                        fullName,
                        grade,
                        comment,
                        setter,
                        stars,
                        starts.map((l) {
                          final ws = tryWsIndexFromLabel(l, cols, rows);
                          return ws == null ? l : "hold$ws";
                        }).toList(),
                        intermediates.map((l) {
                          final ws = tryWsIndexFromLabel(l, cols, rows);
                          return ws == null ? l : "hold$ws";
                        }).toList(),
                        finish.isEmpty
                            ? ""
                            : (() {
                                final ws = tryWsIndexFromLabel(
                                  finish,
                                  cols,
                                  rows,
                                );
                                return ws == null ? finish : "hold$ws";
                              })(),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "📝 Draft saved! Drafts can be viewed from the Wall loading screen.",
                            ),
                            backgroundColor: Colors.blueAccent,
                          ),
                        );
                      }

                      // ✅ Return to the Wall Log Page after a tiny delay
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (!mounted) return;
                        Navigator.of(context).pop(); // ← Pop CreateProblemPage
                      });

                      return;
                    }

                    // ---------------- CREATE BRANCH (NEW PROBLEM) ----------------
                    await api.saveProblem(
                      widget.wallId,
                      fullName,
                      grade,
                      comment,
                      setter,
                      stars,
                      starts.map((l) {
                        final ws = tryWsIndexFromLabel(l, cols, rows);
                        return ws == null ? l : "hold$ws";
                      }).toList(),
                      intermediates.map((l) {
                        final ws = tryWsIndexFromLabel(l, cols, rows);
                        return ws == null ? l : "hold$ws";
                      }).toList(),
                      finish.isEmpty
                          ? ""
                          : (() {
                              final ws = tryWsIndexFromLabel(
                                finish,
                                cols,
                                rows,
                              );
                              return ws == null ? finish : "hold$ws";
                            })(),
                    );

                    // ✅ also write to local CSV
                    await _appendToCsv([
                      DateTime.now().millisecondsSinceEpoch.toString(),
                      fullName,
                      grade,
                      comment,
                      setter,
                      stars.toString(),
                      ...starts.map((l) {
                        final ws = tryWsIndexFromLabel(l, cols, rows);
                        return ws == null ? l : "hold$ws";
                      }),
                      ...intermediates.map((l) {
                        final ws = tryWsIndexFromLabel(l, cols, rows);
                        return ws == null ? l : "hold$ws";
                      }),
                      finish.isEmpty
                          ? ""
                          : (() {
                              final ws = tryWsIndexFromLabel(
                                finish,
                                cols,
                                rows,
                              );
                              return ws == null ? finish : "hold$ws";
                            })(),
                    ]);

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            "✅ Problem Saved. Press clear to start again",
                          ),
                          backgroundColor: Colors.green.shade600,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
            ),
          );
        },
      ),
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Problem' : 'Create Problem'),
        actions: [
          IconButton(
            tooltip: "Clear",
            icon: const Icon(Icons.clear_all),
            onPressed: clearSelection,
          ),
          IconButton(
            tooltip: "Send to Wall",
            icon: const Icon(Icons.lightbulb_outline, color: Colors.blue),
            onPressed: () => _sendToBoardWithFeedback(),
          ),
          IconButton(
            tooltip: confirmStage == ConfirmStage.feet ? "Done Feet" : "Save",
            icon: Icon(
              confirmStage == ConfirmStage.feet ? Icons.check : Icons.save,
            ),
            onPressed: () {
              if (confirmStage == ConfirmStage.feet) {
                proceedFromFeetToReview();
                openReviewDialog(context);
              } else if (confirmStage == ConfirmStage.review) {
                openReviewDialog(context);
              } else {
                beginConfirmation();
              }
            },
          ),

          // 👇 Delete button (only when editing)
          if (widget.isEditing)
            IconButton(
              tooltip: "Delete Problem",
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Delete Problem"),
                    content: const Text(
                      "Are you sure you want to delete this problem? This cannot be undone.",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("Delete"),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  final api = context.read<ApiService>();
                  final row = widget.problemRow;
                  if (row != null) {
                    String? oldId = row[0].toString();

                    if (oldId.isEmpty) {
                      final problemName = row[1];
                      try {
                        oldId = await api.getProblemIdByName(
                          widget.wallId,
                          problemName,
                        );
                      } catch (e) {
                        debugPrint("⚠️ Failed lookup: $e");
                      }
                    }

                    if (oldId != null && oldId.isNotEmpty) {
                      try {
                        await api.deleteProblem(widget.wallId, oldId);
                        debugPrint("🗑️ Deleted problem $oldId");

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("🗑️ Problem Deleted"),
                              backgroundColor: Colors.red,
                            ),
                          );
                          Navigator.pop(context); // close after delete
                        }
                      } catch (e) {
                        debugPrint("⚠️ Delete failed: $e");
                      }
                    }
                  }
                }
              },
            ),
        ],
      ),

      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            // ✅ Instruction bar
            Container(
              height: 40,
              width: double.infinity,
              color: confirmStage == ConfirmStage.none
                  ? Colors.grey.shade100
                  : Colors.yellow.shade100,
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  (confirmStage == ConfirmStage.none)
                      ? (selectionOrder.isEmpty
                            ? "Please select holds"
                            : "Selected ${selectionOrder.length} — tap Save to confirm start/finish")
                      : confirmLabel,
                  style: TextStyle(
                    color: confirmLabel.startsWith('!')
                        ? Colors.red
                        : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),

            Expanded(
              child: holds.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : WallPhoto(
                      holds: holds,
                      rows: rows,
                      cols: cols,
                      baseWidth: baseWidth,
                      baseHeight: baseHeight,
                      selectionOrder: selectionOrder,
                      confirmStage: confirmStage,
                      cStart1: cStart1,
                      cStart2: cStart2,
                      cFinish: cFinish,
                      feetSelected: feetSelected,
                      onTapHold: toggleByLabel,
                      onConfirmTap: handleConfirmTap,
                      wallImageFile: wallImageFile,
                    ),
            ),
            LegendBar(footMode: footMode),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

// ---------------- WALL PHOTO ----------------

class WallPhoto extends StatelessWidget {
  final List<HoldPoint> holds;
  final int rows;
  final int cols;
  final double baseWidth;
  final double baseHeight;
  final List<int> selectionOrder;
  final ConfirmStage confirmStage;
  final int? cStart1;
  final int? cStart2;
  final int? cFinish;
  final Set<int> feetSelected;
  final Function(String) onTapHold;
  final Function(int) onConfirmTap;
  final File? wallImageFile;

  const WallPhoto({
    super.key,
    required this.holds,
    required this.rows,
    required this.cols,
    required this.baseWidth,
    required this.baseHeight,
    required this.selectionOrder,
    required this.confirmStage,
    required this.cStart1,
    required this.cStart2,
    required this.cFinish,
    required this.feetSelected,
    required this.onTapHold,
    required this.onConfirmTap,
    required this.wallImageFile,
  });

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.6,
      maxScale: 6.0,
      child: AspectRatio(
        aspectRatio: baseWidth / baseHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(
                  child: wallImageFile != null
                      ? Image.file(wallImageFile!, fit: BoxFit.fill)
                      : Image.asset(
                          'assets/walls/default/wall.png',
                          fit: BoxFit.fill,
                        ),
                ),
                ...holds.map((h) {
                  final sx = (h.x / baseWidth) * constraints.maxWidth;
                  final sy = (h.y / baseHeight) * constraints.maxHeight;
                  // scale radius smoothly between 15 (few cols) and 8 (many cols)
                  double _scaledRadius(int cols) {
                    const minCols = 10; // smallest wall you expect
                    const maxCols = 35; // largest wall you expect
                    const minR = 4.0;
                    const maxR = 20.0;

                    // clamp cols into [minCols, maxCols]
                    final c = cols.clamp(minCols, maxCols);

                    // map cols to radius
                    final t =
                        (c - minCols) /
                        (maxCols - minCols); // 0 → minCols, 1 → maxCols
                    return maxR -
                        t * (maxR - minR); // decreases as cols increase
                  }

                  final double r = _scaledRadius(cols);
                  final double baseCircle = (160.0 / cols).clamp(40.0, 80.0);

                  return Positioned(
                    left: sx - (baseCircle / 2),
                    top: sy - (baseCircle / 2),
                    width: baseCircle,
                    height: baseCircle,
                    child: _HoldButton(
                      label: h.label,
                      radius: r, // still used for tap hitbox
                      rows: rows,
                      cols: cols,
                      selectionOrder: selectionOrder,
                      confirmStage: confirmStage,
                      cStart1: cStart1,
                      cStart2: cStart2,
                      cFinish: cFinish,
                      baseCircle: baseCircle,
                      feetSelected: feetSelected,
                      onTapHold: onTapHold,
                      onConfirmTap: onConfirmTap,
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}
// ---------------- HOLD BUTTON ----------------

class _HoldButton extends StatelessWidget {
  final String label;
  final double radius;
  final int rows;
  final int cols;
  final List<int> selectionOrder;
  final ConfirmStage confirmStage;
  final int? cStart1;
  final int? cStart2;
  final int? cFinish;
  final Set<int> feetSelected;
  final Function(String) onTapHold;
  final Function(int) onConfirmTap;
  final double baseCircle;

  const _HoldButton({
    required this.label,
    required this.radius,
    required this.rows,
    required this.cols,
    required this.selectionOrder,
    required this.confirmStage,
    required this.cStart1,
    required this.cStart2,
    required this.cFinish,
    required this.feetSelected,
    required this.onTapHold,
    required this.onConfirmTap,
    required this.baseCircle,
  });

  @override
  Widget build(BuildContext context) {
    final wsIndex = tryWsIndexFromLabel(label, cols, rows);
    if (wsIndex == null) return const SizedBox.shrink();

    Color? color;

    if (confirmStage == ConfirmStage.none) {
      final idx = selectionOrder.indexOf(wsIndex);
      final total = selectionOrder.length;
      if (idx == -1) {
        color = null;
      } else if (total <= 2) {
        color = Colors.green;
      } else if (idx == 0 || idx == 1) {
        color = Colors.green;
      } else if (idx == total - 1) {
        color = Colors.red;
      } else {
        color = Colors.blue;
      }
    } else if (confirmStage == ConfirmStage.start1 ||
        confirmStage == ConfirmStage.start2 ||
        confirmStage == ConfirmStage.finish ||
        confirmStage == ConfirmStage.review) {
      if (wsIndex == cStart1 || wsIndex == cStart2) {
        color = Colors.green;
      } else if (wsIndex == cFinish) {
        color = Colors.red;
      } else if (selectionOrder.contains(wsIndex)) {
        color = Colors.blue;
      }
    } else if (confirmStage == ConfirmStage.feet) {
      if (wsIndex == cStart1 || wsIndex == cStart2) {
        color = Colors.green;
      } else if (wsIndex == cFinish) {
        color = Colors.red;
      } else if (selectionOrder.contains(wsIndex)) {
        color = feetSelected.contains(wsIndex) ? Colors.yellow : Colors.blue;
      }
    }

    return GestureDetector(
      onTap: () {
        if (confirmStage == ConfirmStage.none ||
            confirmStage == ConfirmStage.feet) {
          onTapHold(label);
        } else {
          onConfirmTap(wsIndex);
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 👇 NEW: small dynamic hitbox based on rows/cols
          Builder(
            builder: (_) {
              final double hitSize = (240 / max(rows, cols)).clamp(6, 40);
              return SizedBox(
                width: hitSize,
                height: hitSize,
                child: const ColoredBox(color: Colors.transparent),
              );
            },
          ),

          if (color != null) ...[
            Container(
              width: baseCircle,
              height: baseCircle,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
            ),
            Container(
              width: baseCircle - 6,
              height: baseCircle - 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------- LEGEND BAR ----------------

class LegendBar extends StatelessWidget {
  final int footMode;
  const LegendBar({super.key, required this.footMode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _legendDot(Colors.green, "Start"),
          _legendDot(Colors.red, "Finish"),
          _legendDot(Colors.blue, "Intermediate"),
          if (footMode == 2) _legendDot(Colors.yellow, "Feet"),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String text) => Row(
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.black),
        ),
      ),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontSize: 13)),
    ],
  );
}

// ---------------- CONFIRM REVIEW ----------------

class ConfirmReviewDialog extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const ConfirmReviewDialog({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.help_outline, color: Colors.blue),
          SizedBox(width: 8),
          Text("Confirm Selection"),
        ],
      ),
      content: const Text(
        "Are you happy with your chosen holds?",
        style: TextStyle(fontSize: 15),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.arrow_back),
          label: const Text("Back"),
          onPressed: onBack,
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check),
          label: const Text("Continue"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: onContinue,
        ),
      ],
    );
  }
}

// ---------------- SAVE PROBLEM DIALOG ----------------
class SaveProblemDialog extends StatefulWidget {
  final List<String>? problemRow;
  final int minGradeNum;
  final int footMode;
  final List<FootOption> footOptions;
  final bool editingDraft;
  final bool editingProblem;

  final String? initialName;
  final String? initialComment;
  final String? initialGrade;
  final int? initialStars;
  final List<String>? initialFeetTokens;

  /// You MUST pass superusers from CreateProblemPage
  final List<String> superusers;

  final Function(
    String name,
    String comment,
    String grade,
    int stars,
    List<String> feetTokens, {
    bool draft,
    bool delete,
  })
  onSave;

  const SaveProblemDialog({
    super.key,
    this.problemRow,
    required this.minGradeNum,
    required this.footMode,
    required this.footOptions,
    required this.superusers,
    required this.onSave,
    this.editingDraft = false,
    this.editingProblem = false,
    this.initialName,
    this.initialComment,
    this.initialGrade,
    this.initialStars,
    this.initialFeetTokens,
  });

  @override
  State<SaveProblemDialog> createState() => _SaveProblemDialogState();
}

class _SaveProblemDialogState extends State<SaveProblemDialog> {
  final nameCtrl = TextEditingController();
  final commentCtrl = TextEditingController();
  String? grade;
  int stars = 1;
  final Map<String, bool> chosenFeetTokens = {};

  List<String> _allGradesFrom(int minNum) {
    final res = <String>[];
    for (int g = minNum; g <= 9; g++) {
      res.add("${g}a");
      if (g == 9) break;
      res.add("${g}a+");
      res.add("${g}b");
      res.add("${g}b+");
      res.add("${g}c");
      res.add("${g}c+");
    }
    return res;
  }

  @override
  void initState() {
    super.initState();

    if (widget.problemRow != null) {
      final rawName = widget.problemRow![1];
      final rawGrade = widget.problemRow![2];

      final cleanName = rawName.endsWith(rawGrade)
          ? rawName.substring(0, rawName.length - rawGrade.length).trim()
          : rawName;

      nameCtrl.text = cleanName;
      grade = rawGrade;
      commentCtrl.text = widget.problemRow![3];
      stars = int.tryParse(widget.problemRow![5]) ?? 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final grades = _allGradesFrom(widget.minGradeNum);
    grade ??= grades.first;

    /// ------------------------------
    /// SUPERUSER LOGIC (MATCH DETAILS PAGE)
    /// ------------------------------
    final auth = context.watch<AuthState>();
    final username = auth.username ?? "";

    // setter column is widget.problemRow?[4]
    final setter = widget.problemRow != null && widget.problemRow!.length > 4
        ? widget.problemRow![4]
        : "";

    final bool isCreator = (setter == username);
    final bool isSuper = widget.superusers.contains(username);

    final bool canBenchmark = isCreator || isSuper;

    // Debug
    print(
      "DEBUG SaveDialog -> username=$username, setter=$setter, "
      "isCreator=$isCreator, isSuper=$isSuper, canBenchmark=$canBenchmark",
    );

    /// Init foot tokens
    if (widget.footMode == 1 && chosenFeetTokens.isEmpty) {
      for (final opt in widget.footOptions) {
        chosenFeetTokens[opt.holdToken] = false;
      }
    }

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.save, color: Colors.blue),
          SizedBox(width: 8),
          Text("Save Problem"),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: "Problem Name",
                  prefixIcon: Icon(Icons.text_fields),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: commentCtrl,
                decoration: const InputDecoration(
                  labelText: "Comment",
                  prefixIcon: Icon(Icons.comment_outlined),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: grade,
                items: grades
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) => setState(() => grade = v),
                decoration: const InputDecoration(
                  labelText: "Grade",
                  prefixIcon: Icon(Icons.grade),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: stars,
                items: [1, 2, 3]
                    .map((s) => DropdownMenuItem(value: s, child: Text("$s ★")))
                    .toList(),
                onChanged: (v) => setState(() => stars = v ?? 1),
                decoration: const InputDecoration(
                  labelText: "Stars",
                  prefixIcon: Icon(Icons.star),
                ),
              ),

              if (widget.footMode == 1 && widget.footOptions.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Foot options",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 6),
                ...widget.footOptions.map(
                  (opt) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(opt.label),
                    value: chosenFeetTokens[opt.holdToken] ?? false,
                    onChanged: (v) {
                      setState(() {
                        chosenFeetTokens[opt.holdToken] = v ?? false;
                      });
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),

      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),

        OutlinedButton(
          onPressed: () {
            final feetTokens = chosenFeetTokens.entries
                .where((e) => e.value)
                .map((e) => e.key)
                .toList();
            widget.onSave(
              nameCtrl.text.trim(),
              commentCtrl.text.trim(),
              grade!,
              stars,
              feetTokens,
              draft: true,
            );
            Navigator.pop(context);
          },
          child: const Text("Save Draft"),
        ),

        /// ⭐ BENCHMARK BUTTON (Correct Rules)
        if (widget.editingProblem && canBenchmark)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            onPressed: () {
              String c = commentCtrl.text.trim();

              if (c.isEmpty || c == "No Comments") {
                commentCtrl.text = "Benchmark";
              } else if (!c.contains("Benchmark")) {
                commentCtrl.text = "$c\nBenchmark";
              }

              final feetTokens = chosenFeetTokens.entries
                  .where((e) => e.value)
                  .map((e) => e.key)
                  .toList();

              widget.onSave(
                nameCtrl.text.trim(),
                commentCtrl.text.trim(),
                grade!,
                stars,
                feetTokens,
                draft: false,
              );
              Navigator.pop(context);
            },
            child: const Text("Benchmark"),
          ),

        ElevatedButton(
          onPressed: () {
            final feetTokens = chosenFeetTokens.entries
                .where((e) => e.value)
                .map((e) => e.key)
                .toList();

            widget.onSave(
              nameCtrl.text.trim(),
              commentCtrl.text.trim(),
              grade!,
              stars,
              feetTokens,
              draft: false,
            );
            Navigator.pop(context);
          },
          child: Text(widget.editingProblem ? "Update" : "Save"),
        ),
      ],
    );
  }
}
