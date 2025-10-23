import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

import '../hold_utils.dart'; // for tryWsIndexFromLabel

class ProblemService {
  final String wallId;
  final int cols;
  final int rows;

  ProblemService(this.wallId, {required this.cols, required this.rows});

  /// Path to problems file
  Future<File> _getProblemsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File("${dir.path}/$wallId.csv");
  }

  /// Load all problems as raw rows
  Future<List<List<String>>> loadProblems() async {
    final file = await _getProblemsFile();
    if (!await file.exists()) return [];
    final lines = await file.readAsLines();
    return lines.map((l) => l.split("\t")).toList();
  }

  /// Append a new problem row
  Future<void> appendProblem(List<String> row) async {
    final file = await _getProblemsFile();
    final sink = file.openWrite(mode: FileMode.append);
    sink.writeln(row.join("\t"));
    await sink.flush();
    await sink.close();
    debugPrint("💾 PROBLEM SAVE → '${row[0]}' with ${row.length - 5} holds");
  }

  /// Replace an existing problem row (by name match)
  Future<void> updateProblem(
    String problemName,
    List<String> updatedRow,
  ) async {
    final file = await _getProblemsFile();
    if (!await file.exists()) return;

    final lines = await file.readAsLines();
    final newLines = <String>[];

    for (final line in lines) {
      final parts = line.split("\t");
      if (parts.isNotEmpty && parts[0].trim() == problemName.trim()) {
        newLines.add(updatedRow.join("\t")); // replace with new data
      } else {
        newLines.add(line);
      }
    }

    await file.writeAsString(newLines.join("\n"));
    debugPrint("✏️ Problem updated: '$problemName'");
  }

  /// Remove a problem row (by name match)
  Future<void> removeProblem(String problemName) async {
    final file = await _getProblemsFile();
    if (!await file.exists()) return;

    final lines = await file.readAsLines();
    final newLines = lines
        .where((line) => !line.startsWith(problemName))
        .toList();

    await file.writeAsString(newLines.join("\n"));
    debugPrint("🗑️ Problem removed: '$problemName'");
  }

  /// Restore selection (like DraftService) for editing
  Map<String, dynamic> restoreSelection(List<String> problemRow) {
    debugPrint("📥 PROBLEM LOAD → $problemRow");

    final holdsPart = problemRow.sublist(5);
    final selected = <int>{};
    final selectionOrder = <int>[];

    for (final label in holdsPart) {
      final ws = tryWsIndexFromLabel(label, cols, rows);
      debugPrint("   ↳ $label => wsIndex=$ws");
      if (ws != null) {
        selected.add(ws);
        selectionOrder.add(ws);
      }
    }

    return {"selected": selected, "selectionOrder": selectionOrder};
  }
}
