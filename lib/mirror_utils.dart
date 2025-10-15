import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MirrorUtils {
  static Map<String, String> _mirrorDic = {};

  /// Load MirrorDic.json (or .txt) from assets.
  static Future<void> loadMirrorDic({
    String assetPath = 'assets/walls/default/MirrorDic.txt',
  }) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final Map<String, dynamic> decoded = jsonDecode(raw);

      _mirrorDic = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      debugPrint(
        "✅ MirrorDic loaded from $assetPath with ${_mirrorDic.length} entries",
      );
    } catch (e) {
      debugPrint("❌ Failed to load MirrorDic from $assetPath: $e");
      _mirrorDic = {};
    }
  }

  /// Allow external code (WallLogPage, API, SharedPreferences) to override the map.
  static void setMirrorMap(Map<String, String> map) {
    _mirrorDic = map;
    debugPrint("✅ MirrorDic manually set with ${map.length} entries");
  }

  /// Get the entire dictionary (read-only).
  static Map<String, String> get mirrorDic => Map.unmodifiable(_mirrorDic);

  /// Save the current dictionary into SharedPreferences for a wall.
  static Future<void> saveToPrefs(String wallId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("mirrorDic_$wallId", jsonEncode(_mirrorDic));
    debugPrint("💾 MirrorDic saved for wall: $wallId");
  }

  /// Load dictionary from SharedPreferences for a wall.
  static Future<void> loadFromPrefs(String wallId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("mirrorDic_$wallId");

    if (raw != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(raw);
        _mirrorDic = decoded.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
        debugPrint(
          "✅ MirrorDic restored from prefs for wall: $wallId with ${_mirrorDic.length} entries",
        );
      } catch (e) {
        debugPrint("❌ Failed to parse MirrorDic from prefs for $wallId: $e");
      }
    } else {
      debugPrint("⚠️ No MirrorDic found in prefs for wall: $wallId");
    }
  }

  /// Look up the mirrored hold label.
  static String mirrorHold(String label) {
    if (_mirrorDic.isEmpty) {
      debugPrint("⚠️ MirrorDic not loaded, returning original: $label");
      return label;
    }

    final mirrored = _mirrorDic[label];
    if (mirrored != null) {
      debugPrint("🔁 Mirroring $label -> $mirrored");
      return mirrored;
    }

    debugPrint("⚠️ No mirror entry for $label, returning unchanged");
    return label;
  }
}
