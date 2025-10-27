import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../hold_point.dart';

class HoldLoader {
  /// Load holds from dicholdlist.txt for a given wall
  static Future<List<HoldPoint>> loadHolds(String wallId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/walls/$wallId/dicholdlist.txt');
      String data;
      if (await file.exists()) {
        data = await file.readAsString();
      } else {
        data = await rootBundle.loadString(
          'assets/walls/default/dicholdlist.txt',
        );
      }

      final Map<String, dynamic> decoded = jsonDecode(data);

      final keys = decoded.keys.toList();

      return decoded.entries
          .where((e) => e.value is List && e.value.length >= 2)
          .map((e) {
            final label = e.key; // "A1", "B5", etc
            final coords = e.value as List;

            // Generate a holdXX id based on index
            final idx = keys.indexOf(e.key) + 1;
            final id = "hold$idx";

            return HoldPoint(
              id: id,
              label: label,
              x: (coords[0] as num).toDouble(),
              y: (coords[1] as num).toDouble(),
            );
          })
          .toList();
    } catch (e) {
      return [];
    }
  }
}
