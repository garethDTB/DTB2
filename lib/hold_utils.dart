import 'package:flutter/foundation.dart';

/// ------------------------------------------------------------------
/// Grade Conversions
/// ------------------------------------------------------------------

/// Convert French grade → V grade
String frenchToVGrade(String french) {
  final map = {
    '4a': 'VB',
    '4b': 'VB',
    '4c': 'V0',
    '5a': 'V1',
    '5a+': 'V1',
    '5b': 'V1–V2',
    '5b+': 'V2',
    '5c': 'V2',
    '5c+': 'V2–V3',
    '6a': 'V3',
    '6a+': 'V3–V4',
    '6b': 'V4',
    '6b+': 'V4–V5',
    '6c': 'V5',
    '6c+': 'V6',
    '7a': 'V6–V7',
    '7a+': 'V7',
    '7b': 'V7–V8',
    '7b+': 'V8',
    '7c': 'V8–V9',
    '7c+': 'V9',
    '8a': 'V9–V10',
    '8a+': 'V10',
    '8b': 'V10–V11',
    '8b+': 'V11',
    '8c': 'V11–V12',
    '8c+': 'V12',
  };

  return map[french.toLowerCase()] ?? french;
}

/// Convert V grade → French grade
String vToFrench(String v) {
  final reverse = {
    'VB': '4a',
    'V0': '4c',
    'V1': '5a',
    'V2': '5b+',
    'V3': '6a',
    'V4': '6b',
    'V5': '6c',
    'V6': '6c+',
    'V7': '7a+',
    'V8': '7b+',
    'V9': '7c+',
    'V10': '8a+',
    'V11': '8b+',
    'V12': '8c+',
  };
  return reverse[v.toUpperCase()] ?? v;
}

/// ------------------------------------------------------------------
/// Points Mapping
/// ------------------------------------------------------------------

/// Mapping from French grade → points value
const Map<String, int> gradePoints = {
  '20d': 1,
  '8c+': 1350,
  '8c': 1300,
  '8b+': 1250,
  '8b': 1200,
  '8a+': 1050,
  '8a': 1000,
  '8': 1000,
  '7c+': 950,
  '7c': 900,
  '7b+': 850,
  '7b': 800,
  '7a+': 750,
  '7a': 700,
  '7': 700,
  '6c+': 650,
  '6c': 600,
  '6b+': 550,
  '6b': 500,
  '6a+': 450,
  '6a': 400,
  '6': 400,
  '5c+': 350,
  '5c': 300,
  '5b+': 250,
  '5b': 200,
  '5a+': 150,
  '5a': 100,
  '5': 100,
  '4c+': 95,
  '4c': 90,
  '4b+': 85,
  '4b': 80,
  '4a+': 75,
  '4a': 50,
  '4': 50,
};

/// Get points for a given French grade
int getPointsForGrade(String grade) {
  return gradePoints[grade.toLowerCase()] ?? 0;
}

/// ------------------------------------------------------------------
/// Hold Label Conversions
/// ------------------------------------------------------------------

class HoldUtils {
  /// ✅ Keep raw label (no AA/BB conversion)
  static String normalizeLabel(String label) {
    return label.trim();
  }

  /// Convert "A1" style label → index (1-based).
  static int wsIndexFromLabel(String label, int cols, int rows) {
    final m = RegExp(r'^(.)(\d+)$').firstMatch(label.trim());
    if (m == null) throw ArgumentError('Bad hold label: $label');

    final letter = m.group(1)!; // e.g. "A", "Z", "[", "\"
    final rowNum = int.parse(m.group(2)!);

    // ASCII col (A=65 → 0, B=66 → 1, …, Z=90 → 25, [=91 → 26, …)
    int col = letter.codeUnitAt(0) - 65;

    final rowIdx = rowNum - 1; // zero-based row
    final ws = rowIdx * cols + col + 1;
    return ws;
  }

  /// Safe version, returns null if invalid
  static int? tryWsIndexFromLabel(String label, int cols, int rows) {
    try {
      return wsIndexFromLabel(label, cols, rows);
    } catch (_) {
      return null;
    }
  }

  /// Convert index (1-based) → ASCII style label ("A1", "Z10", "[3", …).
  static String labelForWs(int ws, int cols, int rows) {
    final zero = ws - 1;
    final row = zero ~/ cols;
    final col = zero % cols;

    return "${_colLetters(col)}${row + 1}";
  }

  /// Convert "hold53" → ASCII label.
  static String convertHoldId(String holdId, int cols, int rows) {
    final match = RegExp(r'hold(\d+)').firstMatch(holdId);
    if (match == null) return holdId;

    final index = int.tryParse(match.group(1)!);
    if (index == null || index <= 0) return holdId;

    return labelForWs(index, cols, rows);
  }

  /// Helper: col → ASCII char (A=0, Z=25, [=26, …).
  static String _colLetters(int col) {
    return String.fromCharCode(65 + col);
  }
}

/// ------------------------------------------------------------------
/// 🔙 Backwards compatibility wrappers (so existing code still compiles)
/// ------------------------------------------------------------------

int? tryWsIndexFromLabel(String label, int cols, int rows) =>
    HoldUtils.tryWsIndexFromLabel(label, cols, rows);

String labelForWs(int ws, int cols, int rows) =>
    HoldUtils.labelForWs(ws, cols, rows);

String convertHoldId(String holdId, int cols, int rows) =>
    HoldUtils.convertHoldId(holdId, cols, rows);
