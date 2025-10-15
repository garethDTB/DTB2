import 'package:flutter/material.dart';

/// Returns a color for each hold type.
Color colorForHoldType(String type) {
  switch (type) {
    case 'start':
      return Colors.green.withOpacity(0.2);
    case 'finish':
      return Colors.red.withOpacity(0.2);
    case 'feet':
      return Colors.yellow.withOpacity(0.2);
    default:
      return Colors.blue.withOpacity(0.2);
  }
}

/// Normalizes holds into a standard format.
List<Map<String, String>> normalizeHolds(dynamic raw) {
  if (raw == null || raw is! List || raw.isEmpty) return [];

  if (raw.first is Map) {
    return raw.cast<Map<String, String>>();
  }

  final strHolds = raw.cast<String>();
  final result = <Map<String, String>>[];

  int feetIndex = strHolds.indexWhere((h) => h.toLowerCase() == "feet");

  if (feetIndex != -1) {
    if (strHolds.length >= 2) {
      result.add({'type': 'start', 'label': strHolds[0]});
      result.add({'type': 'start', 'label': strHolds[1]});
    } else {
      result.add({'type': 'start', 'label': strHolds[0]});
    }
    if (feetIndex > 1) {
      result.add({'type': 'finish', 'label': strHolds[feetIndex - 1]});
    }
    for (int i = 2; i < feetIndex - 1; i++) {
      result.add({'type': 'intermediate', 'label': strHolds[i]});
    }
    for (int i = feetIndex + 1; i < strHolds.length; i++) {
      result.add({'type': 'feet', 'label': strHolds[i]});
    }
  } else {
    if (strHolds.length >= 2) {
      result.add({'type': 'start', 'label': strHolds[0]});
      result.add({'type': 'start', 'label': strHolds[1]});
    } else {
      result.add({'type': 'start', 'label': strHolds[0]});
    }
    if (strHolds.length > 3) {
      for (int i = 2; i < strHolds.length - 1; i++) {
        result.add({'type': 'intermediate', 'label': strHolds[i]});
      }
    }
    if (strHolds.length > 1) {
      result.add({'type': 'finish', 'label': strHolds.last});
    }
  }
  return result;
}
