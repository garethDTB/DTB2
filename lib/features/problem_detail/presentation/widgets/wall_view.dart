import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dtb2/hold_utils.dart';
import 'package:dtb2/mirror_utils.dart';
import 'package:dtb2/hold_point.dart';

class WallView extends StatelessWidget {
  final List<HoldPoint> holds;
  final List<Map<String, String>> holdsList;
  final double baseWidth;
  final double baseHeight;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;
  final Color Function(String) colorForHoldType;
  final bool isMirrored;
  final File? wallImageFile;
  final int cols;
  final int rows;

  const WallView({
    super.key,
    required this.holds,
    required this.holdsList,
    required this.baseWidth,
    required this.baseHeight,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.colorForHoldType,
    required this.isMirrored,
    required this.wallImageFile,
    required this.cols,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final bg = wallImageFile != null
        ? Image.file(wallImageFile!, fit: BoxFit.fill)
        : Image.asset('assets/walls/default/wall.png', fit: BoxFit.fill);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! < 0) {
          onSwipeLeft();
        } else if (details.primaryVelocity! > 0) {
          onSwipeRight();
        }
      },
      child: holds.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : InteractiveViewer(
              minScale: 0.6,
              maxScale: 3.0,
              child: AspectRatio(
                aspectRatio: baseWidth / baseHeight,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        Positioned.fill(child: bg),

                        // Draw holds
                        ...holdsList.map((hold) {
                          final rawHoldId = hold['label']!;
                          var holdLabel = HoldUtils.convertHoldId(
                            rawHoldId,
                            cols,
                            rows,
                          );

                          if (isMirrored && holdLabel.toLowerCase() != "feet") {
                            holdLabel = MirrorUtils.mirrorHold(holdLabel);
                          }

                          final coords = holds.firstWhere(
                            (h) => h.label == holdLabel,
                            orElse: () =>
                                const HoldPoint(label: '', x: -1, y: -1),
                          );

                          if (coords.x < 0 || coords.y < 0) {
                            return const SizedBox.shrink();
                          }

                          final sx =
                              (coords.x / baseWidth) * constraints.maxWidth;
                          final sy =
                              (coords.y / baseHeight) * constraints.maxHeight;

                          return Positioned(
                            left: sx - 20,
                            top: sy - 20,
                            width: 40,
                            height: 40,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer white ring
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                // Inner coloured ring
                                Container(
                                  margin: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colorForHoldType(hold['type']!),
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ),
            ),
    );
  }
}
