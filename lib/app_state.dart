import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'auth_state.dart';
import 'package:provider/provider.dart';

// =====================================================
// Models / Utilities
// =====================================================

class HoldPoint {
  final String label;
  final double x;
  final double y;
  const HoldPoint({required this.label, required this.x, required this.y});
}

class WallData {
  final int rows;
  final int cols;
  final List<HoldPoint> holds;
  final double baseWidth;
  final double baseHeight;
  const WallData({
    required this.rows,
    required this.cols,
    required this.holds,
    required this.baseWidth,
    required this.baseHeight,
  });
}

class FootOption {
  final String holdToken; // e.g., "hold3"
  final String label; // e.g., "Domes"
  const FootOption(this.holdToken, this.label);
}

enum ConfirmStage { none, start1, start2, finish, feet, review }

// serpentine LED index from "A1" etc, 1-based
int wsIndexFromLabel(String label, int rows) {
  final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(label.trim().toUpperCase());
  if (m == null) throw ArgumentError('Bad hold label: $label');
  final letters = m.group(1)!;
  final rowNum = int.parse(m.group(2)!);

  int col = 0;
  for (int i = 0; i < letters.length; i++) {
    col = col * 26 + (letters.codeUnitAt(i) - 65 + 1);
  }
  col -= 1; // 0-based column
  final rowIdx = rowNum - 1; // 0-based row

  final idxInCol = (col % 2 == 0) ? rowIdx : (rows - 1 - rowIdx);
  return col * rows + idxInCol + 1;
}

int? tryWsIndexFromLabel(String label, int rows) {
  try {
    return wsIndexFromLabel(label, rows);
  } catch (_) {
    return null;
  }
}

String? labelForWs(int ws, WallData wd) {
  final zero = ws - 1;
  final col = zero ~/ wd.rows;
  final posInCol = zero % wd.rows;
  final row = (col % 2 == 0) ? (posInCol + 1) : (wd.rows - posInCol);
  return "${String.fromCharCode(65 + col)}$row";
}

// =====================================================
// App State
// =====================================================

class AppState extends ChangeNotifier {
  WallData? wallData;

  // selection during building
  final Set<int> selected = {};
  final List<int> selectionOrder = [];

  // confirmation flow
  ConfirmStage confirmStage = ConfirmStage.none;
  int? cStart1;
  int? cStart2;
  int? cFinish;
  String confirmLabel = "";

  // feet mode/state
  int footMode = 0; // 0 none, 1 options, 2 choose feet holds
  List<FootOption> footOptions = [];
  final Set<int> feetSelected = {}; // for footMode=2
  List<String> footMode1TokensSelected = []; // for footMode=1

  // settings
  int minGradeNum = 4; // 4/5/6 → min grade

  AppState() {
    _init();
  }

  Future<void> _init() async {
    try {
      wallData = await _loadDefaultWall();
      notifyListeners();
    } catch (e) {
      debugPrint("Init failed: $e");
    }
  }

  Future<WallData> _loadDefaultWall() async {
    // --- Settings
    final settingsRaw = await rootBundle.loadString(
      'assets/walls/default/Settings',
    );
    final lines = settingsRaw
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .toList();

    // Line 7 (1-indexed) → footMode
    if (lines.length >= 7) {
      final v = int.tryParse(lines[6]);
      if (v != null && v >= 0 && v <= 2) footMode = v;
    }

    // Line 8 → foot options as pairs: holdToken,label,holdToken,label,...
    footOptions = [];
    if (lines.length >= 8 && lines[7].isNotEmpty) {
      final parts = lines[7].split(',').map((e) => e.trim()).toList();
      for (int i = 0; i + 1 < parts.length; i += 2) {
        final token = parts[i];
        final name = parts[i + 1];
        if (token.isNotEmpty && name.isNotEmpty) {
          footOptions.add(FootOption(token, name));
        }
      }
    }

    // Line 13 → min grade number 4/5/6
    if (lines.length >= 13) {
      final g = int.tryParse(lines[12]);
      if (g != null && (g == 4 || g == 5 || g == 6)) {
        minGradeNum = g;
      }
    }

    // --- Rows/cols (fallbacks if not in file; can also parse by key if present)
    final rows =
        _extractInt(settingsRaw, ['rows', 'Rows', 'ROW', 'HEIGHT']) ?? 24;
    final cols =
        _extractInt(settingsRaw, ['cols', 'Columns', 'COLS', 'WIDTH']) ?? 14;

    // --- Base image logical size
    final baseWidth = (cols >= 20) ? 1150.0 : 800.0;
    const baseHeight = 750.0;

    // --- Hold coordinates
    final coordsRaw = await rootBundle.loadString(
      'assets/walls/default/dicholdlist.txt',
    );
    final Map<String, dynamic> rawMap = jsonDecode(coordsRaw);
    final holds = <HoldPoint>[];
    rawMap.forEach((label, val) {
      if (val is List && val.length >= 2) {
        final x = (val[0] as num).toDouble();
        final y = (val[1] as num).toDouble();
        if (x < 0 || y < 0) return; // ignore negative coords
        if (!RegExp(r'^[A-Z]+\d+$').hasMatch(label)) return;
        holds.add(HoldPoint(label: label, x: x, y: y));
      }
    });

    return WallData(
      rows: rows,
      cols: cols,
      holds: holds,
      baseWidth: baseWidth,
      baseHeight: baseHeight,
    );
  }

  int? _extractInt(String raw, List<String> keys) {
    for (final k in keys) {
      final m = RegExp(
        '(?:^|[\\r\\n])\\s*${RegExp.escape(k)}\\s*[:=]\\s*(\\d+)',
        caseSensitive: false,
      ).firstMatch(raw);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }

  // ========= Build-mode selection =========
  void toggleByLabel(String label) {
    final wd = wallData;
    if (wd == null) return;
    final ws = tryWsIndexFromLabel(label, wd.rows);
    if (ws == null) return;

    // Feet stage: only toggle feet among remaining blues
    if (confirmStage == ConfirmStage.feet) {
      if (!_remainingForFeet().contains(ws)) return;
      if (feetSelected.contains(ws)) {
        feetSelected.remove(ws);
      } else {
        feetSelected.add(ws);
      }
      notifyListeners();
      return;
    }

    // During confirmation (start/finish), taps handled by handleConfirmTap
    if (confirmStage != ConfirmStage.none) return;

    if (selected.contains(ws)) {
      selected.remove(ws);
      selectionOrder.remove(ws);
    } else {
      selected.add(ws);
      selectionOrder.add(ws);
    }
    notifyListeners();
  }

  void clearSelection() {
    selected.clear();
    selectionOrder.clear();
    cStart1 = cStart2 = cFinish = null;
    feetSelected.clear();
    confirmStage = ConfirmStage.none;
    confirmLabel = "";
    footMode1TokensSelected = [];
    notifyListeners();
  }

  // ========= Confirmation flow =========
  void beginConfirmation() {
    if (selectionOrder.isEmpty) {
      confirmLabel = "Select holds first.";
      notifyListeners();
      return;
    }
    cStart1 = cStart2 = cFinish = null;
    feetSelected.clear();
    footMode1TokensSelected = [];
    confirmStage = ConfirmStage.start1;
    confirmLabel = "Confirm Start hold (tap one of your selected holds)";
    notifyListeners();
  }

  void handleConfirmTap(int ws) {
    if (!selectionOrder.contains(ws)) return;

    if (confirmStage == ConfirmStage.start1) {
      cStart1 = ws;
      confirmStage = ConfirmStage.start2;
      confirmLabel =
          "Confirm second Start: tap the same again for one-handed, or another for two-handed";
    } else if (confirmStage == ConfirmStage.start2) {
      cStart2 = ws; // same as cStart1 → one-handed
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
          confirmLabel = "Review selection";
        }
      }
    }
    notifyListeners();
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
    notifyListeners();
  }

  List<int> finalConfirmedOrder() {
    final starts = <int>[];
    if (cStart1 != null) starts.add(cStart1!);
    if (cStart2 != null) starts.add(cStart2!);
    if (starts.length == 1) {
      starts.add(starts.first); // duplicate for one-handed
    }

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
          showDialog(context: context, builder: (_) => SaveProblemDialog());
        },
      ),
    );
  }

  // ========= Saving =========
  // app_state.dart
  void saveProblem(
    BuildContext context,
    String name,
    String comment,
    String grade,
    int stars,
  ) {
    final wd = wallData;
    if (wd == null) return;

    // 🔑 get the logged-in user from AuthState
    final auth = context.read<AuthState>();
    final currentUser = auth.username ?? "unknown";

    final order = finalConfirmedOrder();
    final labels = order.map((ws) => labelForWs(ws, wd) ?? "??").toList();

    if (footMode == 1 && footMode1TokensSelected.isNotEmpty) {
      final insertAt = labels.length >= 2 ? 2 : labels.length;
      labels.insertAll(insertAt, footMode1TokensSelected);
    }

    if (footMode == 2 && feetSelected.isNotEmpty) {
      final feetLabels = feetSelected
          .map((ws) => labelForWs(ws, wd) ?? "??")
          .toList();
      labels.add("feet");
      labels.addAll(feetLabels);
    }

    final savedLine =
        "$name, $grade, $comment, $currentUser, $stars★, ${labels.join(",")}";
    debugPrint("Saved: $savedLine");
  }
}

// =====================================================
// App
// =====================================================

class ClimbLightApp extends StatelessWidget {
  const ClimbLightApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClimbLight',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// =====================================================
// UI
// =====================================================

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('ClimbLight'),
        actions: [
          IconButton(
            tooltip: "Clear",
            icon: const Icon(Icons.clear_all),
            onPressed: () => app.clearSelection(),
          ),
          IconButton(
            tooltip: app.confirmStage == ConfirmStage.feet
                ? "Done Feet"
                : "Save",
            icon: Icon(
              app.confirmStage == ConfirmStage.feet ? Icons.check : Icons.save,
            ),
            onPressed: () {
              if (app.confirmStage == ConfirmStage.feet) {
                app.proceedFromFeetToReview();
                app.openReviewDialog(context);
              } else if (app.confirmStage == ConfirmStage.review) {
                app.openReviewDialog(context);
              } else {
                app.beginConfirmation();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            if (app.confirmStage != ConfirmStage.none)
              Container(
                padding: const EdgeInsets.all(8),
                width: double.infinity,
                color: Colors.yellow.shade100,
                child: Text(
                  app.confirmLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: app.confirmLabel.startsWith('!')
                        ? Colors.red
                        : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            // REMOVE the legend here 👇
            // const LegendBar(),
            Expanded(
              child: app.wallData == null
                  ? const Center(child: CircularProgressIndicator())
                  : const WallPhoto(),
            ),

            // MOVE the legend here 👇
            const LegendBar(),
            const SizedBox(height: 14), // spacer so it clears the OS bar
          ],
        ),
      ),
    );
  }
}

class LegendBar extends StatelessWidget {
  const LegendBar({super.key});

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
          _legendDot(Colors.yellow, "Feet"),
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

class WallPhoto extends StatelessWidget {
  const WallPhoto({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wd = app.wallData;
    if (wd == null) return const SizedBox();

    return InteractiveViewer(
      minScale: 0.6,
      maxScale: 3.0,
      child: AspectRatio(
        aspectRatio: wd.baseWidth / wd.baseHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/walls/default/wall.png',
                    fit: BoxFit.fill,
                  ),
                ),
                ...wd.holds.map((h) {
                  final sx = (h.x / wd.baseWidth) * constraints.maxWidth;
                  final sy = (h.y / wd.baseHeight) * constraints.maxHeight;
                  const double r = 13.0;
                  return Positioned(
                    left: sx - r,
                    top: sy - r,
                    width: r * 2,
                    height: r * 2,
                    child: _HoldButton(label: h.label, radius: r),
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

class _HoldButton extends StatelessWidget {
  final String label;
  final double radius;
  const _HoldButton({required this.label, required this.radius});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wd = app.wallData!;
    final ws = tryWsIndexFromLabel(label, wd.rows);
    if (ws == null) return const SizedBox.shrink();

    Color? color;

    if (app.confirmStage == ConfirmStage.none) {
      // Build mode: only show dots for selected holds
      final idx = app.selectionOrder.indexOf(ws);
      final total = app.selectionOrder.length;
      if (idx == -1) {
        color = null; // invisible until selected
      } else if (total <= 2) {
        color = Colors.green; // first 1-2 are green
      } else if (idx == 0 || idx == 1) {
        color = Colors.green;
      } else if (idx == total - 1) {
        color = Colors.red;
      } else {
        color = Colors.blue;
      }
    } else if (app.confirmStage == ConfirmStage.start1 ||
        app.confirmStage == ConfirmStage.start2 ||
        app.confirmStage == ConfirmStage.finish ||
        app.confirmStage == ConfirmStage.review) {
      if (ws == app.cStart1 || ws == app.cStart2) {
        color = Colors.green;
      } else if (ws == app.cFinish) {
        color = Colors.red;
      } else if (app.selectionOrder.contains(ws)) {
        color = Colors.blue;
      } else {
        color = null;
      }
    } else if (app.confirmStage == ConfirmStage.feet) {
      if (ws == app.cStart1 || ws == app.cStart2) {
        color = Colors.green;
      } else if (ws == app.cFinish) {
        color = Colors.red;
      } else if (app.selectionOrder.contains(ws)) {
        color = app.feetSelected.contains(ws) ? Colors.yellow : Colors.blue;
      } else {
        color = null;
      }
    }

    return GestureDetector(
      onTap: () {
        if (app.confirmStage == ConfirmStage.none ||
            app.confirmStage == ConfirmStage.feet) {
          app.toggleByLabel(label);
        } else {
          app.handleConfirmTap(ws);
          if (app.confirmStage == ConfirmStage.review &&
              app.cStart1 != null &&
              app.cStart2 != null &&
              app.cFinish != null &&
              app.footMode != 2) {
            app.openReviewDialog(context);
          }
        }
      },
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color?.withOpacity(0.9),
          border: color == null
              ? null
              : Border.all(color: Colors.black87, width: 1),
        ),
      ),
    );
  }
}

// =====================================================
// Dialogs
// =====================================================

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
      title: const Text("Confirm"),
      content: const Text("Is this selection correct?"),
      actions: [
        TextButton(onPressed: onBack, child: const Text("Back")),
        ElevatedButton(onPressed: onContinue, child: const Text("Continue")),
      ],
    );
  }
}

class SaveProblemDialog extends StatefulWidget {
  const SaveProblemDialog({super.key});
  @override
  State<SaveProblemDialog> createState() => _SaveProblemDialogState();
}

class _SaveProblemDialogState extends State<SaveProblemDialog> {
  final nameCtrl = TextEditingController();
  final commentCtrl = TextEditingController();
  String? grade;
  int stars = 1;

  // checkbox selections for footMode==1
  final Map<String, bool> chosenFeetTokens = {};

  List<String> _allGradesFrom(int minNum) {
    const suffixes = ["a", "a+", "b", "b+", "c", "c+"];
    final res = <String>[];
    for (int g = minNum; g <= 8; g++) {
      for (final s in suffixes) {
        res.add("$g$s");
      }
    }
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wd = app.wallData!;
    final grades = _allGradesFrom(app.minGradeNum);
    grade ??= grades.first;

    // init footMode1 checkbox state
    if (app.footMode == 1 && chosenFeetTokens.isEmpty) {
      for (final opt in app.footOptions) {
        chosenFeetTokens[opt.holdToken] = false;
      }
    }

    return AlertDialog(
      title: const Text("Save Problem"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: commentCtrl,
              decoration: const InputDecoration(labelText: "Comment"),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: grade,
              items: grades
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => grade = v),
              decoration: const InputDecoration(labelText: "Grade"),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: stars,
              items: [1, 2, 3]
                  .map((s) => DropdownMenuItem(value: s, child: Text("$s ★")))
                  .toList(),
              onChanged: (v) => setState(() => stars = v ?? 1),
              decoration: const InputDecoration(labelText: "Stars"),
            ),
            if (app.footMode == 1 && app.footOptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Foot options",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 6),
              ...app.footOptions.map(
                (opt) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(opt.label),
                  subtitle: Text(opt.holdToken),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () {
            if (app.footMode == 1) {
              app.footMode1TokensSelected = chosenFeetTokens.entries
                  .where((e) => e.value)
                  .map((e) => e.key)
                  .toList();
            }

            app.saveProblem(
              context, // 👈 pass BuildContext first
              nameCtrl.text.trim(),
              commentCtrl.text.trim(),
              grade ?? grades.first,
              stars,
            );
            Navigator.pop(context);
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}
