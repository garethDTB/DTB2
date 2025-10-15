import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _gradeMode = "french";
  bool _autoSend = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _gradeMode = prefs.getString('gradeMode') ?? "french";
      _autoSend = prefs.getBool('autoSend') ?? false;
    });
  }

  Future<void> _saveGradeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gradeMode', mode);
    setState(() => _gradeMode = mode);
  }

  Future<void> _saveAutoSend(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoSend', value);
    setState(() => _autoSend = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 10),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  title: Text("Grade Display"),
                  subtitle: Text("Choose how grades are shown"),
                ),
                RadioListTile<String>(
                  title: const Text("French (6a, 7b+)"),
                  value: "french",
                  groupValue: _gradeMode,
                  onChanged: (v) => _saveGradeMode(v!),
                ),
                RadioListTile<String>(
                  title: const Text("V-Grades (V2, V6)"),
                  value: "vgrade",
                  groupValue: _gradeMode,
                  onChanged: (v) => _saveGradeMode(v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: SwitchListTile(
              title: const Text("Auto Send to Board"),
              subtitle: const Text("Automatically send problem when swiping"),
              value: _autoSend,
              onChanged: (v) => _saveAutoSend(v),
            ),
          ),
        ],
      ),
    );
  }
}
