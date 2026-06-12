import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'hold_utils.dart';

class HoldFilterPage extends StatefulWidget {
  final String wallId;
  final Set<String> initiallySelected;
  final bool matchAll;

  const HoldFilterPage({
    super.key,
    required this.wallId,
    required this.initiallySelected,
    required this.matchAll,
  });

  @override
  State<HoldFilterPage> createState() => _HoldFilterPageState();
}

class _HoldFilterPageState extends State<HoldFilterPage> {
  int rows = 18;
  int cols = 14;
  double baseWidth = 1150.0;
  double baseHeight = 750.0;

  File? wallImageFile;
  List<HoldPoint> holds = [];
  final Set<int> selectedWs = {};
  late bool matchAll;

  @override
  void initState() {
    super.initState();
    matchAll = widget.matchAll;
    _loadEverything();
  }

  Future<void> _loadEverything() async {
    await _loadSettings();
    await _loadHoldPositions();
    await _loadWallImage();

    for (final holdId in widget.initiallySelected) {
      if (holdId.startsWith("hold")) {
        final ws = int.tryParse(holdId.substring(4));
        if (ws != null) selectedWs.add(ws);
      }
    }

    setState(() {});
  }

  Future<void> _loadSettings() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/walls/${widget.wallId}/Settings');

    final raw = await file.exists()
        ? await file.readAsString()
        : await rootBundle.loadString('assets/walls/default/Settings');

    final lines = raw.split(RegExp(r'\r?\n')).map((e) => e.trim()).toList();

    if (lines.length >= 2) {
      cols = int.tryParse(lines[0]) ?? cols;
      rows = int.tryParse(lines[1]) ?? rows;
      baseWidth = cols >= 20 ? 1150.0 : 800.0;
      baseHeight = 750.0;
    }
  }

  Future<void> _loadHoldPositions() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/walls/${widget.wallId}/dicholdlist.txt');

    final data = await file.exists()
        ? await file.readAsString()
        : await rootBundle.loadString('assets/walls/default/dicholdlist.txt');

    final decoded = jsonDecode(data) as Map<String, dynamic>;

    holds = decoded.entries
        .map((entry) {
          final val = entry.value;
          if (val is List && val.length >= 2) {
            final x = (val[0] as num).toDouble();
            final y = (val[1] as num).toDouble();
            if (x >= 0 && y >= 0) {
              return HoldPoint(label: entry.key, x: x, y: y);
            }
          }
          return null;
        })
        .whereType<HoldPoint>()
        .toList();
  }

  Future<void> _loadWallImage() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/walls/${widget.wallId}/wall.png');

    if (await file.exists()) {
      wallImageFile = file;
    }
  }

  void _toggleHold(String label) {
    final ws = tryWsIndexFromLabel(label, cols, rows);
    if (ws == null) return;

    setState(() {
      if (selectedWs.contains(ws)) {
        selectedWs.remove(ws);
      } else {
        selectedWs.add(ws);
      }
    });
  }

  void _apply() {
    final selectedHoldIds = selectedWs.map((ws) => "hold$ws").toSet();

    Navigator.pop(context, {"holds": selectedHoldIds, "matchAll": matchAll});
  }

  void _clear() {
    setState(() {
      selectedWs.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedLabels =
        selectedWs.map((ws) => labelForWs(ws, cols, rows)).toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Filter by holds"),
        actions: [
          IconButton(
            tooltip: "Clear",
            icon: const Icon(Icons.clear_all),
            onPressed: _clear,
          ),
          IconButton(
            tooltip: "Apply",
            icon: const Icon(Icons.check),
            onPressed: _apply,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: Colors.grey.shade100,
              child: Text(
                selectedWs.isEmpty
                    ? "Tap holds to filter problems"
                    : "Selected ${selectedWs.length}: ${selectedLabels.join(', ')}",
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SwitchListTile(
              title: Text(
                matchAll
                    ? "Match all selected holds"
                    : "Match any selected hold",
              ),
              subtitle: Text(matchAll ? "AND filter" : "OR filter"),
              value: matchAll,
              onChanged: (value) {
                setState(() {
                  matchAll = value;
                });
              },
            ),
            Expanded(
              child: holds.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : HoldFilterWallPhoto(
                      holds: holds,
                      rows: rows,
                      cols: cols,
                      baseWidth: baseWidth,
                      baseHeight: baseHeight,
                      selectedWs: selectedWs,
                      onTapHold: _toggleHold,
                      wallImageFile: wallImageFile,
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: _apply,
            icon: const Icon(Icons.filter_alt),
            label: Text(
              selectedWs.isEmpty
                  ? "Show all problems"
                  : "Apply ${matchAll ? 'AND' : 'OR'} filter (${selectedWs.length})",
            ),
          ),
        ),
      ),
    );
  }
}

class HoldPoint {
  final String label;
  final double x;
  final double y;

  const HoldPoint({required this.label, required this.x, required this.y});
}

class HoldFilterWallPhoto extends StatelessWidget {
  final List<HoldPoint> holds;
  final int rows;
  final int cols;
  final double baseWidth;
  final double baseHeight;
  final Set<int> selectedWs;
  final Function(String) onTapHold;
  final File? wallImageFile;

  const HoldFilterWallPhoto({
    super.key,
    required this.holds,
    required this.rows,
    required this.cols,
    required this.baseWidth,
    required this.baseHeight,
    required this.selectedWs,
    required this.onTapHold,
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

                  final double baseCircle = (160.0 / cols).clamp(40.0, 80.0);

                  return Positioned(
                    left: sx - (baseCircle / 2),
                    top: sy - (baseCircle / 2),
                    width: baseCircle,
                    height: baseCircle,
                    child: _HoldFilterButton(
                      label: h.label,
                      rows: rows,
                      cols: cols,
                      selectedWs: selectedWs,
                      baseCircle: baseCircle,
                      onTapHold: onTapHold,
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

class _HoldFilterButton extends StatelessWidget {
  final String label;
  final int rows;
  final int cols;
  final Set<int> selectedWs;
  final double baseCircle;
  final Function(String) onTapHold;

  const _HoldFilterButton({
    required this.label,
    required this.rows,
    required this.cols,
    required this.selectedWs,
    required this.baseCircle,
    required this.onTapHold,
  });

  @override
  Widget build(BuildContext context) {
    final wsIndex = tryWsIndexFromLabel(label, cols, rows);
    if (wsIndex == null) return const SizedBox.shrink();

    final selected = selectedWs.contains(wsIndex);

    return GestureDetector(
      onTap: () => onTapHold(label),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Builder(
            builder: (_) {
              final double hitSize = (240 / max(rows, cols)).clamp(12, 40);
              return SizedBox(
                width: hitSize,
                height: hitSize,
                child: const ColoredBox(color: Colors.transparent),
              );
            },
          ),
          if (selected) ...[
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
                border: Border.all(color: Colors.blue, width: 4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
