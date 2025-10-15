import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsModel extends ChangeNotifier {
  String _gradeMode = "french";
  String get gradeMode => _gradeMode;

  SettingsModel() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _gradeMode = prefs.getString('gradeMode') ?? "french";
    notifyListeners();
  }

  Future<void> setGradeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gradeMode', mode);
    _gradeMode = mode;
    notifyListeners();
  }
}
