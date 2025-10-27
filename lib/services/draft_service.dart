import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

import '../hold_utils.dart'; // for tryWsIndexFromLabel

class DraftService {
  final String wallId;
  final int cols;
  final int rows;

  DraftService(this.wallId, {required this.cols, required this.rows});

  /// Path to drafts file
  Future<File> _getDraftsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File("${dir.path}/${wallId}_drafts.csv");
  }

  /// Append a new draft
  ///
  /// Always saves holds as `holdNNN` IDs for consistency.
  /// If feetMode=2, adds a "feet" marker followed by all foot holds.
  Future<bool> appendDraft(
    List<int> confirmedWs, {
    required String fullName,
    required String grade,
    required String comment,
    required String setter,
    required int stars,
    required int footMode,
    Set<int> feetSelected = const {},
    List<String> feetTokens = const [], // footMode=1 tokens
    int maxDrafts = 10,
  }) async {
    final file = await _getDraftsFile();

    // Limit number of drafts
    if (await file.exists()) {
      final lines = await file.readAsLines();
      if (lines.length >= maxDrafts) {
        return false;
      }
    }

    // ✅ Always save hold IDs
    final holdIds = confirmedWs.map((ws) => "hold$ws").toList();

    final row = <String>[
      fullName,
      grade,
      comment,
      setter,
      stars.toString(),
      ...holdIds,
    ];

    // ✅ feetMode=2 → add "feet" marker + selected foot holds
    if (footMode == 2 && feetSelected.isNotEmpty) {
      row.add("feet");
      row.addAll(feetSelected.map((ws) => "hold$ws"));
    }

    // ✅ feetMode=1 → keep named tokens
    if (footMode == 1 && feetTokens.isNotEmpty) {
      row.addAll(feetTokens);
    }

    debugPrint(
      "💾 DRAFT SAVE → '$fullName' with ${holdIds.length} holds, "
      "feetMode=$footMode "
      "(${footMode == 2 ? feetSelected.length : feetTokens.length} feet)",
    );

    final sink = file.openWrite(mode: FileMode.append);
    sink.writeln(row.join("\t"));
    await sink.flush();
    await sink.close();
    return true;
  }

  /// Remove a draft row
  Future<void> removeDraft(List<String> row) async {
    final file = await _getDraftsFile();
    if (!await file.exists()) return;

    final lines = await file.readAsLines();
    final newLines = lines
        .where((line) => line.trim() != row.join("\t"))
        .toList();

    await file.writeAsString(newLines.join("\n"));
    debugPrint("🗑️ Draft removed: '${row[0]}'");
  }

  /// Load all drafts as raw rows
  Future<List<List<String>>> loadDrafts() async {
    final file = await _getDraftsFile();
    if (!await file.exists()) return [];
    final lines = await file.readAsLines();
    return lines.map((l) => l.split("\t")).toList();
  }

  /// Restore selection from a given draft row
  ///
  /// Supports both old drafts saved as labels (e.g. "A5") and
  /// new drafts saved as IDs ("hold123").
  /// Also restores "feet" marker if present.
  Map<String, dynamic> restoreSelection(List<String> draftRow) {
    debugPrint("📥 DRAFT LOAD → $draftRow");

    final holdsPart = draftRow.sublist(5);
    final selected = <int>{};
    final selectionOrder = <int>[];
    final feetSelected = <int>{};

    bool inFeetSection = false;

    for (final token in holdsPart) {
      if (token == "feet") {
        inFeetSection = true;
        continue;
      }

      int? ws;
      if (token.startsWith("hold")) {
        ws = int.tryParse(token.substring(4));
      } else {
        ws = tryWsIndexFromLabel(token, cols, rows);
      }

      debugPrint("   ↳ $token => wsIndex=$ws (feet=$inFeetSection)");
      if (ws != null) {
        if (inFeetSection) {
          feetSelected.add(ws);
        } else {
          selected.add(ws);
          selectionOrder.add(ws);
        }
      }
    }

    return {
      "selected": selected,
      "selectionOrder": selectionOrder,
      "feetSelected": feetSelected,
    };
  }
}
