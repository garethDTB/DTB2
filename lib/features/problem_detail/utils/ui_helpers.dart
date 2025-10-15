import 'package:flutter/material.dart';

/// Shows a temporary bottom message overlay.
void showBottomMessage(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  final entry = OverlayEntry(
    builder: (context) => SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          color: Colors.black87,
          padding: const EdgeInsets.all(12),
          child: Text(
            message,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 2), entry.remove);
}
