import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'mirror_utils.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'services/ble_cast_service.dart';

class MirrorSetupPage extends StatefulWidget {
  final String wallId;

  const MirrorSetupPage({super.key, required this.wallId});

  @override
  State<MirrorSetupPage> createState() => _MirrorSetupPageState();
}

class _MirrorSetupPageState extends State<MirrorSetupPage> {
  bool _loading = true;
  bool _saving = false;

  String? _error;
  String? _statusMessage;

  int cols = 10;
  int rows = 10;

  double baseWidth = 800.0;
  double baseHeight = 750.0;

  File? wallImageFile;

  final Map<String, Offset> _mappedPositions = {};
  final Map<String, String> _mirrorDic = {};

  final List<String> _reviewHolds = [];
  final Set<String> _confirmedHolds = {};

  final List<String> _unusedHolds = [];

  int _currentIndex = 0;

  String? _selectedMirror;

  bool _allLedsOn = false;

  String get _currentHold {
    if (_reviewHolds.isEmpty) return "";
    return _reviewHolds[_currentIndex];
  }

  @override
  void initState() {
    super.initState();
    _loadMirrorSetup();
  }

  // ============================================================
  // LOCAL FILE
  // ============================================================

  Future<File> _getLocalWallFile(String wallId, String filename) async {
    final dir = await getApplicationDocumentsDirectory();

    return File('${dir.path}/walls/$wallId/$filename');
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> _loadMirrorSetup() async {
    try {
      await _loadSettings();
      await _loadWallImage();
      await _loadDicholdList();
      await _loadExistingMirrorDic();

      _buildUnusedList();
      _buildReviewList();
      _buildInitialSuggestions();

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      if (_reviewHolds.isNotEmpty) {
        _selectedMirror = _mirrorDic[_currentHold];

        await _lightCurrentPair();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ============================================================
  // SETTINGS
  // ============================================================

  Future<void> _loadSettings() async {
    final file = await _getLocalWallFile(widget.wallId, "Settings");

    if (!await file.exists()) {
      throw Exception("Settings file was not found.");
    }

    final lines = await file.readAsLines();

    if (lines.length < 3) {
      throw Exception("Settings file is incomplete.");
    }

    cols = int.tryParse(lines[0].trim()) ?? 10;

    rows = int.tryParse(lines[1].trim()) ?? 10;

    final symmetrical = lines[2].trim() == "1";

    if (!symmetrical) {
      throw Exception("This wall is not marked as symmetrical.");
    }

    baseWidth = cols >= 20 ? 1150.0 : 800.0;

    baseHeight = 750.0;
  }

  // ============================================================
  // WALL IMAGE
  // ============================================================

  Future<void> _loadWallImage() async {
    final file = await _getLocalWallFile(widget.wallId, "wall.png");

    if (!await file.exists()) {
      throw Exception("wall.png was not found.");
    }

    wallImageFile = file;
  }

  // ============================================================
  // DICHOLDLIST
  // ============================================================

  Future<void> _loadDicholdList() async {
    final file = await _getLocalWallFile(widget.wallId, "dicholdlist.txt");

    if (!await file.exists()) {
      throw Exception("dicholdlist.txt was not found.");
    }

    final raw = await file.readAsString();

    final decoded = jsonDecode(raw);

    if (decoded is! Map) {
      throw Exception("dicholdlist.txt is invalid.");
    }

    _mappedPositions.clear();

    decoded.forEach((key, value) {
      if (value is List && value.length >= 2) {
        _mappedPositions[key.toString()] = Offset(
          (value[0] as num).toDouble(),
          (value[1] as num).toDouble(),
        );
      }
    });
  }

  // ============================================================
  // EXISTING MIRRORDIC
  // ============================================================

  Future<void> _loadExistingMirrorDic() async {
    final file = await _getLocalWallFile(widget.wallId, "MirrorDic.txt");

    if (!await file.exists()) {
      return;
    }

    final raw = await file.readAsString();

    if (raw.trim().isEmpty) {
      return;
    }

    final decoded = jsonDecode(raw);

    if (decoded is! Map) {
      return;
    }

    decoded.forEach((key, value) {
      _mirrorDic[key.toString()] = value.toString();
    });
  }

  // ============================================================
  // UNUSED LEDS
  // ============================================================

  void _buildUnusedList() {
    _unusedHolds
      ..clear()
      ..addAll(
        _mappedPositions.entries
            .where((entry) => entry.value.dx < 0 || entry.value.dy < 0)
            .map((entry) => entry.key),
      );
  }

  // ============================================================
  // REVIEW LEFT SIDE + CENTRE ONLY
  // ============================================================

  void _buildReviewList() {
    _reviewHolds.clear();

    final centreX = baseWidth / 2.0;

    final mappedHolds = _mappedPositions.entries
        .where((entry) => entry.value.dx >= 0 && entry.value.dy >= 0)
        .toList();

    mappedHolds.sort((a, b) {
      if (a.value.dy != b.value.dy) {
        return b.value.dy.compareTo(a.value.dy);
      }

      return a.value.dx.compareTo(b.value.dx);
    });

    for (final entry in mappedHolds) {
      if (entry.value.dx <= centreX) {
        _reviewHolds.add(entry.key);
      }
    }
  }

  // ============================================================
  // AUTOMATIC FIRST GUESS
  // ============================================================

  void _buildInitialSuggestions() {
    final realHolds = _mappedPositions.entries
        .where((entry) => entry.value.dx >= 0 && entry.value.dy >= 0)
        .toList();

    for (final hold in _reviewHolds) {
      final current = _mappedPositions[hold];

      if (current == null) continue;

      final ideal = Offset(baseWidth - current.dx, current.dy);

      String? nearestHold;
      double nearestDistance = double.infinity;

      for (final candidate in realHolds) {
        final dx = candidate.value.dx - ideal.dx;

        final dy = candidate.value.dy - ideal.dy;

        final distance = sqrt((dx * dx) + (dy * dy));

        if (distance < nearestDistance) {
          nearestDistance = distance;

          nearestHold = candidate.key;
        }
      }

      if (nearestHold != null) {
        _mirrorDic[hold] = nearestHold;

        _mirrorDic[nearestHold] = hold;
      }
    }
  }

  // ============================================================
  // LIGHT CURRENT PAIR
  // ============================================================

  Future<void> _lightCurrentPair() async {
    if (_currentHold.isEmpty ||
        _selectedMirror == null ||
        _selectedMirror!.isEmpty) {
      return;
    }

    try {
      final holds = <String>[_currentHold];

      if (_selectedMirror != _currentHold) {
        holds.add(_selectedMirror!);
      }

      await BleCastService().sendMessage({
        "type": "preview_problem",
        "wallId": widget.wallId,
        "problem": "Mirror check",
        "holds": holds,
        "mirrored": false,
      }, boardName: "DTB Board ${widget.wallId}");

      if (!mounted) return;

      setState(() {
        _statusMessage =
            "$_currentHold ↔ $_selectedMirror\n"
            "Check the illuminated LEDs, then Confirm.";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _statusMessage = "Could not illuminate mirror pair.";
      });
    }
  }

  // ============================================================
  // ALL LEDS
  // ============================================================

  Future<void> _lightAllLeds() async {
    try {
      await BleCastService().sendMessage({
        "type": "all_leds",
        "wallId": widget.wallId,
      }, boardName: "DTB Board ${widget.wallId}");

      if (!mounted) return;

      setState(() {
        _allLedsOn = true;

        _statusMessage =
            "All LEDs are illuminated.\n"
            "Check that every hold has an LED.";
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not switch all LEDs on:\n$e")),
      );
    }
  }

  Future<void> _returnToCurrentPair() async {
    setState(() {
      _allLedsOn = false;
    });

    await _lightCurrentPair();
  }

  // ============================================================
  // TAP A HOLD ON THE IMAGE
  // ============================================================

  Future<void> _handleWallTap(
    TapUpDetails details,
    BoxConstraints constraints,
  ) async {
    final wallX = (details.localPosition.dx / constraints.maxWidth) * baseWidth;

    final wallY =
        (details.localPosition.dy / constraints.maxHeight) * baseHeight;

    final tapPoint = Offset(wallX, wallY);

    String? nearestHold;
    double nearestDistance = double.infinity;

    for (final entry in _mappedPositions.entries) {
      final p = entry.value;

      if (p.dx < 0 || p.dy < 0) {
        continue;
      }

      final dx = p.dx - tapPoint.dx;

      final dy = p.dy - tapPoint.dy;

      final distance = sqrt((dx * dx) + (dy * dy));

      if (distance < nearestDistance) {
        nearestDistance = distance;

        nearestHold = entry.key;
      }
    }

    // Do not select a mapped hold that is nowhere near the tap.
    // This normally means the installer has tapped a hold that
    // has not been mapped yet.
    final maxTapDistance = baseWidth * 0.035;

    if (nearestHold == null || nearestDistance > maxTapDistance) {
      if (!mounted) return;

      final returnToMap = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 10),
                Expanded(child: Text("Hold Not Mapped")),
              ],
            ),
            content: const Text(
              "No mapped hold was found where you tapped.\n\n"
              "If there is a physical hold at this position, it may not "
              "have been mapped during Map Setup.\n\n"
              "Return to Map Setup and map the hold before completing "
              "the mirror check.",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text("Continue Mirror Check"),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.place_outlined),
                label: const Text("Return to Map Setup"),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      if (returnToMap == true) {
        Navigator.pop(context, false);
      }

      return;
    }

    setState(() {
      _selectedMirror = nearestHold;
    });

    if (!_allLedsOn) {
      await _lightCurrentPair();
    }
  }

  // ============================================================
  // CONFIRM = SAVE + NEXT
  // ============================================================

  Future<void> _confirmPair() async {
    if (_selectedMirror == null) {
      return;
    }

    final current = _currentHold;

    final selected = _selectedMirror!;

    _mirrorDic[current] = selected;

    _mirrorDic[selected] = current;

    _confirmedHolds.add(current);

    _confirmedHolds.add(selected);

    await _saveMirrorDic();

    if (_currentIndex >= _reviewHolds.length - 1) {
      await _finishMirrorSetup();
      return;
    }

    setState(() {
      _currentIndex++;

      _selectedMirror = _mirrorDic[_currentHold];
    });

    if (!_allLedsOn) {
      await _lightCurrentPair();
    }
  }

  // ============================================================
  // BACK
  // ============================================================

  Future<void> _previousPair() async {
    if (_currentIndex <= 0) {
      return;
    }

    setState(() {
      _currentIndex--;

      _selectedMirror = _mirrorDic[_currentHold];
    });

    if (!_allLedsOn) {
      await _lightCurrentPair();
    }
  }

  // ============================================================
  // SAVE MIRRORDIC
  // ============================================================

  Future<void> _saveMirrorDic() async {
    final file = await _getLocalWallFile(widget.wallId, "MirrorDic.txt");

    await file.writeAsString(jsonEncode(_mirrorDic), flush: true);

    // Update the mirror map used by the rest of the app immediately.
    MirrorUtils.setMirrorMap(Map<String, String>.from(_mirrorDic));

    await MirrorUtils.saveToPrefs(widget.wallId);
  }

  // ============================================================
  // FIND MIRROR PAIRS THAT NEED CHECKING AGAIN
  // ============================================================

  List<String> _findMirrorProblems() {
    final problemHolds = <String>{};

    final mappedHolds = _mappedPositions.entries
        .where((entry) => entry.value.dx >= 0 && entry.value.dy >= 0)
        .map((entry) => entry.key)
        .toSet();

    final centreX = baseWidth / 2.0;

    bool isReviewSide(String hold) {
      final position = _mappedPositions[hold];

      if (position == null) {
        return false;
      }

      return position.dx >= 0 && position.dy >= 0 && position.dx <= centreX;
    }

    // ----------------------------------------------------------
    // CHECK EACH HOLD HAS A VALID RECIPROCAL MIRROR
    // ----------------------------------------------------------

    final incoming = <String, List<String>>{};

    for (final hold in mappedHolds) {
      final mirror = _mirrorDic[hold];

      // No mirror at all.
      if (mirror == null || mirror.isEmpty) {
        if (isReviewSide(hold)) {
          problemHolds.add(hold);
        }

        continue;
      }

      // Mirror points to an LED/hold that is not mapped.
      if (!mappedHolds.contains(mirror)) {
        if (isReviewSide(hold)) {
          problemHolds.add(hold);
        }

        continue;
      }

      incoming.putIfAbsent(mirror, () => []).add(hold);

      // The opposite side does not point back.
      if (_mirrorDic[mirror] != hold) {
        if (isReviewSide(hold)) {
          problemHolds.add(hold);
        } else if (isReviewSide(mirror)) {
          problemHolds.add(mirror);
        }
      }
    }

    // ----------------------------------------------------------
    // CHECK FOR DUPLICATE MIRRORS
    // ----------------------------------------------------------

    for (final entry in incoming.entries) {
      if (entry.value.length <= 1) {
        continue;
      }

      for (final source in entry.value) {
        if (isReviewSide(source)) {
          problemHolds.add(source);
        }
      }

      if (isReviewSide(entry.key)) {
        problemHolds.add(entry.key);
      }
    }

    // Put them back into the normal Mirror Check order.
    final result = problemHolds.toList();

    result.sort((a, b) {
      final pa = _mappedPositions[a]!;
      final pb = _mappedPositions[b]!;

      if (pa.dy != pb.dy) {
        return pb.dy.compareTo(pa.dy);
      }

      return pa.dx.compareTo(pb.dx);
    });

    return result;
  }

  String? _getRepairSuggestion(String hold) {
    final existing = _mirrorDic[hold];

    // If the existing mirror is a genuinely mapped hold,
    // keep showing it. The installer can decide whether it is right.
    if (existing != null) {
      final existingPosition = _mappedPositions[existing];

      if (existingPosition != null &&
          existingPosition.dx >= 0 &&
          existingPosition.dy >= 0) {
        return existing;
      }
    }

    // Otherwise make a fresh geometric suggestion.
    final current = _mappedPositions[hold];

    if (current == null) {
      return null;
    }

    final ideal = Offset(baseWidth - current.dx, current.dy);

    String? nearestHold;
    double nearestDistance = double.infinity;

    for (final entry in _mappedPositions.entries) {
      final p = entry.value;

      if (p.dx < 0 || p.dy < 0) {
        continue;
      }

      final dx = p.dx - ideal.dx;
      final dy = p.dy - ideal.dy;

      final distance = sqrt((dx * dx) + (dy * dy));

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestHold = entry.key;
      }
    }

    return nearestHold;
  }

  // ============================================================
  // FINISH
  // ============================================================

  Future<void> _finishMirrorSetup() async {
    setState(() {
      _saving = true;
    });

    // ----------------------------------------------------------
    // Check whether any mirror pairs need another look.
    // ----------------------------------------------------------

    final problemHolds = _findMirrorProblems();

    if (problemHolds.isNotEmpty) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      final checkAgain = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 10),
                Expanded(child: Text("Some Pairs Need Checking")),
              ],
            ),
            content: Text(
              "${problemHolds.length} mirror "
              "${problemHolds.length == 1 ? 'pair needs' : 'pairs need'} "
              "another look.\n\n"
              "We'll now take you through just "
              "${problemHolds.length == 1 ? 'this hold' : 'these holds'} "
              "again.",
            ),
            actions: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.refresh),
                label: const Text("Check Again"),
              ),
            ],
          );
        },
      );

      if (!mounted || checkAgain != true) {
        return;
      }

      setState(() {
        // Replace the review list with only the holds
        // that need checking again.
        _reviewHolds
          ..clear()
          ..addAll(problemHolds);

        _currentIndex = 0;

        _selectedMirror = _getRepairSuggestion(_currentHold);

        _allLedsOn = false;

        _statusMessage = "This mirror pair needs checking again.";
      });

      await _lightCurrentPair();

      return;
    }

    // ----------------------------------------------------------
    // Everything passed validation.
    // ----------------------------------------------------------

    await _saveMirrorDic();

    if (!mounted) return;

    setState(() {
      _saving = false;
    });

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 10),
              Expanded(child: Text("Mirror Setup Complete")),
            ],
          ),
          content: Text(
            "All mapped holds have a valid mirror pair.\n\n"
            "${_unusedHolds.length} unused LEDs remain.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text("Back"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text("Complete"),
            ),
          ],
        );
      },
    );

    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Mirror Setup")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Mirror Setup")),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$_currentHold ↔ "
                    "${_selectedMirror ?? '?'}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    "Pair ${_currentIndex + 1} "
                    "of ${_reviewHolds.length}",
                  ),

                  const SizedBox(height: 6),

                  Text(_statusMessage ?? "Check the suggested mirror pair."),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _allLedsOn ? _returnToCurrentPair : null,
                          icon: const Icon(Icons.radio_button_checked),
                          label: const Text("Current Pair"),
                        ),
                      ),

                      const SizedBox(width: 8),

                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _allLedsOn ? null : _lightAllLeds,
                          icon: const Icon(Icons.lightbulb),
                          label: const Text("All LEDs"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: InteractiveViewer(
                minScale: 0.6,
                maxScale: 6.0,

                child: AspectRatio(
                  aspectRatio: baseWidth / baseHeight,

                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,

                        onTapUp: (details) {
                          _handleWallTap(details, constraints);
                        },

                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Image.file(
                                wallImageFile!,
                                fit: BoxFit.fill,
                              ),
                            ),

                            ..._mappedPositions.entries
                                .where(
                                  (entry) =>
                                      entry.value.dx >= 0 &&
                                      entry.value.dy >= 0 &&
                                      (entry.key == _currentHold ||
                                          entry.key == _selectedMirror),
                                )
                                .map((entry) {
                                  final p = entry.value;

                                  final sx =
                                      (p.dx / baseWidth) * constraints.maxWidth;

                                  final sy =
                                      (p.dy / baseHeight) *
                                      constraints.maxHeight;

                                  final isSource = entry.key == _currentHold;

                                  final size = 16.0;

                                  return Positioned(
                                    left: sx - size / 2,
                                    top: sy - size / 2,
                                    child: IgnorePointer(
                                      child: Container(
                                        width: size,
                                        height: size,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSource
                                              ? Colors.blue
                                              : Colors.orange,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _currentIndex == 0 ? null : _previousPair,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text("Back"),
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _selectedMirror == null ? null : _confirmPair,
                      icon: const Icon(Icons.check),
                      label: Text(
                        _currentIndex >= _reviewHolds.length - 1
                            ? "Confirm & Finish"
                            : "Confirm",
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
