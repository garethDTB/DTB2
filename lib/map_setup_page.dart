import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'services/ble_cast_service.dart';

class MapSetupPage extends StatefulWidget {
  final String wallId;

  const MapSetupPage({super.key, required this.wallId});

  @override
  State<MapSetupPage> createState() => _MapSetupPageState();
}

class _MapSetupPageState extends State<MapSetupPage> {
  bool _loading = true;
  bool _saving = false;

  String? _error;
  String? _statusMessage;

  int cols = 10;
  int rows = 10;

  double baseWidth = 800.0;
  double baseHeight = 750.0;

  File? wallImageFile;

  final List<String> _allHoldLabels = [];
  final List<String> _mappingHolds = [];

  final Map<String, Offset> _mappedPositions = {};

  final Set<String> _confirmedHolds = {};

  bool _allLedsOn = false;

  int _currentIndex = 0;

  String get _currentHold {
    if (_mappingHolds.isEmpty) return "";
    return _mappingHolds[_currentIndex];
  }

  int get _checkedCount => _confirmedHolds.length;

  int get _mappedHoldCount {
    return _confirmedHolds.where((hold) {
      final p = _mappedPositions[hold];

      return p != null && p.dx >= 0 && p.dy >= 0;
    }).length;
  }

  int get _unusedLedCount {
    return _confirmedHolds.where((hold) {
      final p = _mappedPositions[hold];

      return p != null && p.dx < 0 && p.dy < 0;
    }).length;
  }

  bool get _allMapped =>
      _mappingHolds.isNotEmpty &&
      _confirmedHolds.length == _mappingHolds.length;

  @override
  void initState() {
    super.initState();

    _loadMapper();
  }

  // ============================================================
  // LOCAL FILE
  // ============================================================

  Future<File> _getLocalWallFile(String wallId, String filename) async {
    final dir = await getApplicationDocumentsDirectory();

    return File('${dir.path}/walls/$wallId/$filename');
  }

  // ============================================================
  // LOAD EVERYTHING
  // ============================================================

  Future<void> _loadMapper() async {
    try {
      await _loadSettings();
      await _loadWallImage();
      await _loadHoldList();
      await _loadExistingPositions();

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      // Light the first real hold.
      if (_mappingHolds.isNotEmpty) {
        await _lightCurrentHold();
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

    if (lines.length < 2) {
      throw Exception("Settings file is incomplete.");
    }

    cols = int.tryParse(lines[0].trim()) ?? cols;

    rows = int.tryParse(lines[1].trim()) ?? rows;

    // Same logic already used in CreateProblemPage.
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
  // HOLDLIST.CSV
  // ============================================================

  Future<void> _loadHoldList() async {
    final file = await _getLocalWallFile(widget.wallId, "holdlist.csv");

    if (!await file.exists()) {
      throw Exception("holdlist.csv was not found.");
    }

    final rawLines = await file.readAsLines();

    final labels = rawLines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (labels.isEmpty) {
      throw Exception("holdlist.csv is empty.");
    }

    // IMPORTANT:
    // A0 is the reserved first LED.
    //
    // Stop rather than risk mapping every LED one position out.
    if (labels.first != "A0") {
      throw Exception(
        "holdlist.csv does not begin with A0.\n\n"
        "Mapping has been stopped to prevent an LED numbering error.",
      );
    }

    _allHoldLabels
      ..clear()
      ..addAll(labels);

    _mappingHolds
      ..clear()
      ..addAll(labels.skip(1));

    if (_mappingHolds.isEmpty) {
      throw Exception("No mappable holds were found after A0.");
    }
  }

  // ============================================================
  // EXISTING DICHOLDLIST
  // ============================================================

  Future<void> _loadExistingPositions() async {
    final file = await _getLocalWallFile(widget.wallId, "dicholdlist.txt");

    if (!await file.exists()) {
      // This is allowed.
      // We can start with an empty mapping.
      return;
    }

    final raw = await file.readAsString();

    if (raw.trim().isEmpty) {
      return;
    }

    final decoded = jsonDecode(raw);

    if (decoded is! Map) {
      throw Exception("dicholdlist.txt is not valid.");
    }

    _mappedPositions.clear();

    decoded.forEach((key, value) {
      if (value is List && value.length >= 2) {
        final x = (value[0] as num).toDouble();

        final y = (value[1] as num).toDouble();

        _mappedPositions[key.toString()] = Offset(x, y);
      }
    });
  }

  // ============================================================
  // LIGHT CURRENT HOLD
  //
  // Uses EXACTLY the same BLE message type as Create Problem.
  // ============================================================

  Future<void> _lightCurrentHold() async {
    if (_currentHold.isEmpty) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _statusMessage = "Lighting $_currentHold...";
    });

    try {
      await BleCastService().sendMessage({
        "type": "preview_problem",
        "wallId": widget.wallId,
        "problem": "Mapping $_currentHold",
        "holds": [_currentHold],
        "mirrored": false,
      }, boardName: "DTB Board ${widget.wallId}");

      if (!mounted) return;

      setState(() {
        _statusMessage =
            "$_currentHold should now be illuminated.\n"
            "Tap the centre of that hold.";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _statusMessage =
            "Could not illuminate $_currentHold.\n\n"
            "You can still map it manually.";
      });
    }
  }

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

  Future<void> _returnToCurrentLed() async {
    setState(() {
      _allLedsOn = false;
    });

    await _lightCurrentHold();
  }
  // ============================================================
  // MAP A TAP
  // ============================================================

  Future<void> _mapTap(TapUpDetails details, BoxConstraints constraints) async {
    if (_currentHold.isEmpty) {
      return;
    }

    // This is the inverse of the tested Create Problem display:
    //
    // sx = (hold.x / baseWidth) * screenWidth
    // sy = (hold.y / baseHeight) * screenHeight
    //
    // So mapping converts screen -> wall coordinates.

    final wallX = (details.localPosition.dx / constraints.maxWidth) * baseWidth;

    final wallY =
        (details.localPosition.dy / constraints.maxHeight) * baseHeight;

    setState(() {
      _mappedPositions[_currentHold] = Offset(wallX, wallY);

      _confirmedHolds.add(_currentHold);

      _statusMessage =
          "$_currentHold position selected.\n"
          "Tap again to adjust it, or press Next when happy.";
    });
    await _saveProgress();
  }

  // ============================================================
  // PREVIOUS
  // ============================================================

  Future<void> _previousHold() async {
    if (_currentIndex <= 0) return;

    setState(() {
      _currentIndex--;
    });

    if (!_allLedsOn) {
      await _lightCurrentHold();
    }
  }

  // ============================================================
  // NEXT
  // ============================================================

  Future<void> _nextHold() async {
    if (!_confirmedHolds.contains(_currentHold)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Tap the hold position first, or choose No Hold."),
        ),
      );
      return;
    }

    if (_currentIndex >= _mappingHolds.length - 1) {
      return;
    }

    setState(() {
      _currentIndex++;
    });

    if (!_allLedsOn) {
      await _lightCurrentHold();
    }
  }

  // ============================================================
  // NO HOLD / UNUSED LED
  // ============================================================

  Future<void> _noHold() async {
    if (_currentHold.isEmpty) return;

    setState(() {
      _mappedPositions[_currentHold] = const Offset(-30, -30);

      _confirmedHolds.add(_currentHold);
    });

    await _saveProgress();

    // If this is the final LED, go straight to review.
    if (_currentIndex >= _mappingHolds.length - 1) {
      await _showMappingReview();
      return;
    }

    // Otherwise automatically move to the next LED.
    setState(() {
      _currentIndex++;
    });

    if (!_allLedsOn) {
      await _lightCurrentHold();
    }
  }

  // ============================================================
  // SAVE DICHOLDLIST
  // ============================================================

  Future<void> _saveProgress() async {
    final file = await _getLocalWallFile(widget.wallId, "dicholdlist.txt");

    final output = <String, List<double>>{};

    // IMPORTANT:
    // Use holdlist.csv order when writing.
    //
    // Do NOT include A0.

    for (final hold in _mappingHolds) {
      final position = _mappedPositions[hold];

      if (position == null) {
        continue;
      }

      output[hold] = [position.dx, position.dy];
    }

    await file.writeAsString(jsonEncode(output), flush: true);
  }

  Future<void> _showMappingReview() async {
    if (_confirmedHolds.length != _mappingHolds.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "$_checkedCount of "
            "${_mappingHolds.length} LED positions checked.",
          ),
        ),
      );
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Mapping Review"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${_mappingHolds.length} LED positions checked",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text("$_mappedHoldCount holds mapped"),
                ],
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  const Icon(Icons.block),
                  const SizedBox(width: 8),
                  Text("$_unusedLedCount unused LEDs"),
                ],
              ),

              const SizedBox(height: 20),

              const Text("Check the wall and mapping before completing setup."),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text("Back to Mapping"),
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text("Complete Mapping"),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _finishMapping();
    }
  }

  // ============================================================
  // FINISH
  // ============================================================

  Future<void> _finishMapping() async {
    if (!_confirmedHolds.contains(_currentHold)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please map this hold or select No Hold first."),
        ),
      );
      return;
    }

    if (_confirmedHolds.length != _mappingHolds.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Mapping is not complete.\n"
            "${_confirmedHolds.length} of "
            "${_mappingHolds.length} positions have been confirmed.",
          ),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _statusMessage = "Saving completed wall mapping...";
    });

    try {
      await _saveProgress();

      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 10),
                Text("Mapping Complete"),
              ],
            ),
            content: Text(
              "All ${_mappingHolds.length} LED positions "
              "have been mapped.\n\n"
              "The wall mapping has been saved.",
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("Continue"),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _statusMessage = "Could not save the mapping.";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not save mapping:\n$e"),
          backgroundColor: Colors.red,
        ),
      );
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
        appBar: AppBar(title: const Text("Map Wall")),
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
      appBar: AppBar(title: const Text("Map Wall")),
      body: SafeArea(
        child: Column(
          children: [
            // ==================================================
            // STATUS
            // ==================================================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Mapping $_currentHold",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    "${_currentIndex + 1} "
                    "of ${_mappingHolds.length}",
                  ),

                  const SizedBox(height: 4),

                  Text(
                    _statusMessage ?? "Tap the centre of the illuminated hold.",
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _allLedsOn ? _returnToCurrentLed : null,
                          icon: const Icon(Icons.radio_button_checked),
                          label: const Text("Current LED"),
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

            // ==================================================
            // WALL
            // ==================================================
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
                          _mapTap(details, constraints);
                        },

                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Image.file(
                                wallImageFile!,
                                fit: BoxFit.fill,
                              ),
                            ),

                            // ==================================
                            // MAPPED / CURRENT HOLD POSITIONS
                            // ==================================
                            ..._mappedPositions.keys
                                .where((hold) {
                                  final p = _mappedPositions[hold];

                                  if (p == null || p.dx < 0 || p.dy < 0) {
                                    return false;
                                  }

                                  // Show:
                                  // 1. Holds confirmed during this session
                                  // 2. The current hold, even before it is confirmed
                                  return _confirmedHolds.contains(hold) ||
                                      hold == _currentHold;
                                })
                                .map((hold) {
                                  final p = _mappedPositions[hold]!;

                                  final sx =
                                      (p.dx / baseWidth) * constraints.maxWidth;

                                  final sy =
                                      (p.dy / baseHeight) *
                                      constraints.maxHeight;

                                  final isCurrent = hold == _currentHold;

                                  final isConfirmed = _confirmedHolds.contains(
                                    hold,
                                  );

                                  final dotSize = isCurrent ? 14.0 : 8.0;

                                  final dotColor = isCurrent && !isConfirmed
                                      ? Colors.green
                                      : Colors.blue;

                                  return Positioned(
                                    left: sx - (dotSize / 2),
                                    top: sy - (dotSize / 2),
                                    child: IgnorePointer(
                                      child: Container(
                                        width: dotSize,
                                        height: dotSize,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: dotColor,

                                          // Current hold becomes blue + white
                                          // once you have tapped a new position.
                                          border: isCurrent && isConfirmed
                                              ? Border.all(
                                                  color: Colors.white,
                                                  width: 2,
                                                )
                                              : null,
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

            // ==================================================
            // CONTROLS
            // ==================================================
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _currentIndex == 0 ? null : _previousHold,
                          icon: const Icon(Icons.chevron_left),
                          label: const Text("Back", maxLines: 1),
                        ),
                      ),

                      const SizedBox(width: 8),

                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _noHold,
                          icon: const Icon(Icons.block),
                          label: const Text("Unused", maxLines: 1),
                        ),
                      ),

                      const SizedBox(width: 8),

                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _confirmedHolds.contains(_currentHold)
                              ? (_currentIndex >= _mappingHolds.length - 1
                                    ? _showMappingReview
                                    : _nextHold)
                              : null,
                          icon: Icon(
                            _currentIndex >= _mappingHolds.length - 1
                                ? Icons.check
                                : Icons.chevron_right,
                          ),
                          label: Text(
                            _currentIndex >= _mappingHolds.length - 1
                                ? "Review"
                                : "Next",
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "$_mappedHoldCount holds mapped"
                    "   •   $_unusedLedCount unused LEDs",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
