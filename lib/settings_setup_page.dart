import 'dart:convert';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class SettingsSetupPage extends StatefulWidget {
  final String wallId;

  const SettingsSetupPage({super.key, required this.wallId});

  @override
  State<SettingsSetupPage> createState() => _SettingsSetupPageState();
}

class _SettingsSetupPageState extends State<SettingsSetupPage> {
  bool _loading = true;
  String? _error;

  static const Map<int, List<int>> kitDimensions = {
    50: [10, 5],
    100: [10, 10],
    150: [15, 10],
    200: [20, 10],
    250: [25, 10],
    300: [20, 15],
    350: [25, 14],
    400: [20, 20],
    450: [25, 18],
    500: [25, 20],
    550: [25, 22],
  };

  int? _selectedKit;

  bool _symmetrical = false;

  String _feetMode = "None";

  final TextEditingController _friendlyNameController = TextEditingController();

  final TextEditingController _angleController = TextEditingController();

  final TextEditingController _latitudeController = TextEditingController();

  final TextEditingController _longitudeController = TextEditingController();

  final TextEditingController _newSuperuserController = TextEditingController();

  String _primarySuperuser = "";

  final List<String> _additionalSuperusers = [];

  List<String> _settingsLines = [];

  @override
  void initState() {
    super.initState();

    _loadExistingSettings();
  }

  @override
  void dispose() {
    _friendlyNameController.dispose();
    _angleController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _newSuperuserController.dispose();

    super.dispose();
  }

  Future<File> _getLocalWallFile(String wallId, String filename) async {
    final dir = await getApplicationDocumentsDirectory();

    return File('${dir.path}/walls/$wallId/$filename');
  }

  Future<File> _getLocalWallList() async {
    final dir = await getApplicationDocumentsDirectory();

    return File('${dir.path}/walls/global/walllist.csv');
  }

  int? _kitFromDimensions(int columns, int rows) {
    for (final entry in kitDimensions.entries) {
      final dims = entry.value;

      if (dims[0] == columns && dims[1] == rows) {
        return entry.key;
      }
    }

    return null;
  }

  Future<void> _loadExistingSettings() async {
    try {
      // ------------------------------------------------------
      // SETTINGS FILE
      // ------------------------------------------------------

      final settingsFile = await _getLocalWallFile(widget.wallId, "Settings");

      if (!await settingsFile.exists()) {
        throw Exception("Local Settings file not found.");
      }

      final settingsLines = await settingsFile.readAsLines();

      if (settingsLines.length < 17) {
        throw Exception("Settings file is incomplete.");
      }

      final columns = int.tryParse(settingsLines[0].trim()) ?? 0;

      final rows = int.tryParse(settingsLines[1].trim()) ?? 0;

      final symmetry = settingsLines[2].trim() == "1";

      final feetValue = settingsLines[6].trim();

      final superuserLine = settingsLines[16].trim();

      final superusers = superuserLine
          .split(",")
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      // ------------------------------------------------------
      // WALLLIST
      // ------------------------------------------------------

      final wallListFile = await _getLocalWallList();

      if (!await wallListFile.exists()) {
        throw Exception("Local walllist.csv not found.");
      }

      final raw = await wallListFile.readAsString();

      final lines = const LineSplitter().convert(raw);

      List<String>? wallValues;

      for (final line in lines) {
        final values = line.split(",");

        if (values.length > 6 && values[6].trim() == widget.wallId) {
          wallValues = values;
          break;
        }
      }

      if (wallValues == null) {
        throw Exception("Wall ${widget.wallId} was not found in walllist.csv.");
      }

      final friendlyName = wallValues.length > 2 ? wallValues[2].trim() : "";

      final angle = wallValues.length > 3 ? wallValues[3].trim() : "";

      final latitude = wallValues.length > 4 ? wallValues[4].trim() : "";

      final longitude = wallValues.length > 5 ? wallValues[5].trim() : "";

      if (!mounted) return;

      setState(() {
        _settingsLines = settingsLines;

        _selectedKit = _kitFromDimensions(columns, rows);

        _symmetrical = symmetry;

        _feetMode = feetValue == "0"
            ? "None"
            : feetValue == "1"
            ? "Options"
            : "Specific";

        _friendlyNameController.text = friendlyName;

        _angleController.text = angle;

        _latitudeController.text = latitude;

        _longitudeController.text = longitude;

        if (superusers.isNotEmpty) {
          _primarySuperuser = superusers.first;

          _additionalSuperusers
            ..clear()
            ..addAll(superusers.skip(1));
        }

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _useCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location services are switched off.")),
        );

        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Location permission is required to use the phone's position.",
            ),
          ),
        );

        return;
      }

      final position = await Geolocator.getCurrentPosition();

      if (!mounted) return;

      setState(() {
        _latitudeController.text = position.latitude.toStringAsFixed(6);

        _longitudeController.text = position.longitude.toStringAsFixed(6);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Wall position set to the phone's current position."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not get current position: $e")),
      );
    }
  }

  Future<void> _saveSettings() async {
    try {
      // --------------------------------------------------------
      // VALIDATE
      // --------------------------------------------------------

      if (_selectedKit == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select a supported kit size.")),
        );
        return;
      }

      final friendlyName = _friendlyNameController.text.trim();

      final angle = _angleController.text.trim();

      final latitude = _latitudeController.text.trim();

      final longitude = _longitudeController.text.trim();

      if (friendlyName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter a friendly wall name.")),
        );
        return;
      }

      // Your existing walllist parser uses commas,
      // so don't allow commas inside these fields.
      if (friendlyName.contains(",") || angle.contains(",")) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Wall name and angle cannot contain commas."),
          ),
        );
        return;
      }

      final latValue = double.tryParse(latitude);

      final lonValue = double.tryParse(longitude);

      if (latValue == null || latValue < -90 || latValue > 90) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter a valid latitude.")),
        );
        return;
      }

      if (lonValue == null || lonValue < -180 || lonValue > 180) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter a valid longitude.")),
        );
        return;
      }

      // --------------------------------------------------------
      // UPDATE SETTINGS
      // --------------------------------------------------------

      if (_settingsLines.length < 17) {
        throw Exception("Settings file is incomplete.");
      }

      final dimensions = kitDimensions[_selectedKit]!;

      final columns = dimensions[0];
      final rows = dimensions[1];

      // Line 1 - columns
      _settingsLines[0] = columns.toString();

      // Line 2 - rows
      _settingsLines[1] = rows.toString();

      // Line 3 - symmetrical
      _settingsLines[2] = _symmetrical ? "1" : "0";

      // Line 7 - feet mode
      _settingsLines[6] = _feetMode == "None"
          ? "0"
          : _feetMode == "Options"
          ? "1"
          : "2";

      // Line 17 - superusers
      final allSuperusers = <String>[
        _primarySuperuser,
        ..._additionalSuperusers,
      ].where((name) => name.trim().isNotEmpty).toList();

      _settingsLines[16] = allSuperusers.join(",");

      final settingsFile = await _getLocalWallFile(widget.wallId, "Settings");

      await settingsFile.writeAsString("${_settingsLines.join("\n")}\n");

      // --------------------------------------------------------
      // UPDATE WALLLIST.CSV
      // --------------------------------------------------------

      final wallListFile = await _getLocalWallList();

      final raw = await wallListFile.readAsString();

      final lines = const LineSplitter().convert(raw);

      bool wallFound = false;

      final updatedLines = <String>[];

      for (final line in lines) {
        final values = line.split(",");

        if (values.length > 6 && values[6].trim() == widget.wallId) {
          wallFound = true;

          // Column 2 = friendly name
          values[2] = friendlyName;

          // Column 3 = board angle
          values[3] = angle;

          // Column 4 = latitude
          values[4] = latitude;

          // Column 5 = longitude
          values[5] = longitude;

          updatedLines.add(values.join(","));
        } else {
          updatedLines.add(line);
        }
      }

      if (!wallFound) {
        throw Exception("Wall ${widget.wallId} was not found in walllist.csv.");
      }

      await wallListFile.writeAsString("${updatedLines.join("\n")}\n");

      // --------------------------------------------------------
      // SUCCESS
      // --------------------------------------------------------

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Wall settings saved locally."),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not save settings:\n$e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Wall Settings")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Wall Settings")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            TextField(
              enabled: false,
              controller: TextEditingController(text: widget.wallId),
              decoration: const InputDecoration(
                labelText: "Wall ID",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            DropdownButtonFormField<int>(
              value: _selectedKit,
              decoration: const InputDecoration(
                labelText: "Kit size",
                border: OutlineInputBorder(),
              ),
              hint: const Text("Custom / legacy dimensions"),
              items: kitDimensions.keys.map((kit) {
                final dims = kitDimensions[kit]!;

                return DropdownMenuItem<int>(
                  value: kit,
                  child: Text("$kit holds — ${dims[0]} × ${dims[1]}"),
                );
              }).toList(),

              // Temporarily disabled
              onChanged: null,
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _friendlyNameController,
              decoration: const InputDecoration(
                labelText: "Friendly wall name",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _angleController,
              decoration: const InputDecoration(
                labelText: "Board angle",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            const SizedBox(height: 24),

            Text(
              "Position",
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 6),

            const Text("This is used to identify nearby walls in the app."),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _useCurrentPosition,
                icon: const Icon(Icons.my_location),
                label: const Text("Use Phone's Current Position"),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _latitudeController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: "Latitude",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _longitudeController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: "Longitude",
                border: OutlineInputBorder(),
              ),
            ),

            SwitchListTile(
              title: const Text("Symmetrical wall"),
              value: _symmetrical,
              onChanged: (value) {
                setState(() {
                  _symmetrical = value;
                });
              },
            ),

            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: _feetMode,
              decoration: const InputDecoration(
                labelText: "Feet mode",
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: "None", child: Text("None")),
                DropdownMenuItem(value: "Options", child: Text("Feet options")),
                DropdownMenuItem(
                  value: "Specific",
                  child: Text("Specific feet"),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  _feetMode = value;
                });
              },
            ),

            const SizedBox(height: 24),

            ListTile(
              leading: const Icon(Icons.lock),
              title: Text(_primarySuperuser),
              subtitle: const Text("Primary superuser"),
            ),

            ..._additionalSuperusers.map(
              (user) => ListTile(
                leading: const Icon(Icons.person),
                title: Text(user),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(() {
                      _additionalSuperusers.remove(user);
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newSuperuserController,
                    decoration: const InputDecoration(
                      labelText: "Add superuser",
                      hintText: "Username",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final name = _newSuperuserController.text.trim();

                      if (name.isEmpty) {
                        return;
                      }

                      // Don't allow the primary user to be added again.
                      if (name == _primarySuperuser) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "This is already the primary superuser.",
                            ),
                          ),
                        );
                        return;
                      }

                      // Don't allow duplicates.
                      if (_additionalSuperusers.contains(name)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "This superuser has already been added.",
                            ),
                          ),
                        );
                        return;
                      }

                      setState(() {
                        _additionalSuperusers.add(name);
                        _newSuperuserController.clear();
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text("Add"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            const SizedBox(height: 24),

            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save),
                label: const Text("Save Settings"),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ), // ListView
      ), // SafeArea
    ); // Scaffold
  } // build()
}       // _SettingsSetupPageState