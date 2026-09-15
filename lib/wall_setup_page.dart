import 'package:flutter/material.dart';
import 'connections_setup_page.dart';
import 'services/ble_cast_service.dart';
import 'settings_setup_page.dart';
import 'picture_setup_page.dart';
import 'map_setup_page.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'services/dropbox_auth_service.dart';
import 'services/dropbox_file_service.dart';
import 'mirror_setup_page.dart';

class WallSetupPage extends StatefulWidget {
  final String wallId;

  const WallSetupPage({super.key, required this.wallId});

  @override
  State<WallSetupPage> createState() => _WallSetupPageState();
}

class _WallSetupPageState extends State<WallSetupPage> {
  // ------------------------------------------------------------
  // CONNECTION STATUS
  // ------------------------------------------------------------
  final BleCastService _bleService = BleCastService();
  bool _bluetoothConnected = false;
  bool _internetConnected = false;

  bool get _connectionsComplete => _bluetoothConnected && _internetConnected;

  // ------------------------------------------------------------
  // SECTION STATUS
  // ------------------------------------------------------------

  bool _settingsComplete = false;
  bool _pictureComplete = false;
  bool _mapComplete = false;
  bool _mirrorComplete = false;

  // This will eventually be read from Settings line 3.
  bool _isSymmetrical = false;

  bool _submitting = false;

  String _submitStatus = "";

  // ------------------------------------------------------------
  // SUBMIT RULE
  // ------------------------------------------------------------

  bool get _canSubmit {
    return _connectionsComplete &&
        _settingsComplete &&
        _pictureComplete &&
        _mapComplete &&
        (!_isSymmetrical || _mirrorComplete);
  }

  @override
  void initState() {
    super.initState();

    _loadWallSetupInfo();
  }

  @override
  void dispose() {
    _bleService.endSetup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Wall Setup")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ============================================================
          // WALL NAME
          // ============================================================
          Text(
            widget.wallId,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 16),

          // ============================================================
          // WARNING
          // ============================================================
          Card(
            color: Colors.orange.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.orange.shade300),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 30,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Wall Setup changes the configuration of the physical "
                      "training board.\n\n"
                      "The DTB controller must have a working Bluetooth "
                      "connection and Internet connection before setup can "
                      "continue.\n\n"
                      "Changes are stored locally until Submit is selected.",
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ============================================================
          // CONNECTIONS
          // ============================================================
          _setupCard(
            icon: Icons.wifi,
            title: "Connections",
            subtitle: _connectionSubtitle(),
            complete: _connectionsComplete,
            enabled: true,
            onTap: _openConnections,
          ),

          const SizedBox(height: 12),

          // ============================================================
          // SETTINGS
          // ============================================================
          _setupCard(
            icon: Icons.tune,
            title: "Settings",
            subtitle:
                "Location, dimensions, symmetry, superusers and feet options",
            complete: _settingsComplete,
            enabled: _connectionsComplete,
            onTap: _openSettings,
          ),

          const SizedBox(height: 12),

          // ============================================================
          // PICTURE
          // ============================================================
          _setupCard(
            icon: Icons.photo_camera_outlined,
            title: "Picture",
            subtitle: "Choose, crop and prepare the photograph of the wall",
            complete: _pictureComplete,
            enabled: _connectionsComplete,
            onTap: _openPicture,
          ),

          const SizedBox(height: 12),

          // ============================================================
          // MAP
          // ============================================================
          _setupCard(
            icon: Icons.place_outlined,
            title: "Map",
            subtitle:
                "Match the wall photograph and hold positions to the LEDs",
            complete: _mapComplete,
            enabled: _connectionsComplete,
            onTap: _openMap,
          ),

          // ============================================================
          // MIRROR
          // Only appears when Settings line 3 = 1
          // ============================================================
          if (_isSymmetrical) ...[
            const SizedBox(height: 12),

            _setupCard(
              icon: Icons.compare_arrows,
              title: "Mirror",
              subtitle: "Check and edit the mirrored hold relationships",
              complete: _mirrorComplete,
              enabled: _connectionsComplete,
              onTap: _openMirror,
            ),
          ],

          const SizedBox(height: 28),

          // ============================================================
          // SUBMIT
          // ============================================================
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _canSubmit && !_submitting ? _submitWall : null,

              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(_submitting ? "Submitting..." : "Submit Wall Setup"),
            ),
          ),

          const SizedBox(height: 12),

          Center(
            child: Text(
              _submitStatusText(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _canSubmit ? Colors.green : Colors.grey,
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ================================================================
  // CONNECTION TEXT
  // ================================================================

  String _connectionSubtitle() {
    if (_connectionsComplete) {
      return "Bluetooth connected • Internet connected";
    }

    if (_bluetoothConnected && !_internetConnected) {
      return "Bluetooth connected • Internet required";
    }

    if (!_bluetoothConnected && _internetConnected) {
      return "Internet connected • Bluetooth required";
    }

    return "Bluetooth and Internet connection required";
  }

  // ================================================================
  // SUBMIT STATUS TEXT
  // ================================================================

  String _submitStatusText() {
    if (!_connectionsComplete) {
      return "Connect to the DTB controller and Internet before continuing.";
    }

    if (!_settingsComplete) {
      return "Complete Settings before submitting.";
    }

    if (!_pictureComplete) {
      return "Complete Picture setup before submitting.";
    }

    if (!_mapComplete) {
      return "Complete hold mapping before submitting.";
    }

    if (_isSymmetrical && !_mirrorComplete) {
      return "Complete Mirror setup before submitting.";
    }

    return "Setup complete and ready to submit.";
  }

  // ================================================================
  // SETUP CARD
  // ================================================================

  Widget _setupCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool complete,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        enabled: enabled,
        leading: Icon(
          complete
              ? Icons.check_circle
              : enabled
              ? icon
              : Icons.lock_outline,
          color: complete
              ? Colors.green
              : enabled
              ? null
              : Colors.grey,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: enabled ? null : theme.disabledColor,
          ),
        ),
        subtitle: Text(enabled ? subtitle : "Complete Connections first"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (complete)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text(
                  "Complete",
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Icon(enabled ? Icons.chevron_right : Icons.lock_outline),
          ],
        ),
        onTap: enabled ? onTap : null,
      ),
    );
  }

  Future<bool> _uploadIfChanged({
    required DropboxFileService service,
    required String dropboxPath,
    required File localFile,
  }) async {
    final changed = await service.localFileDiffersFromDropbox(
      dropboxPath,
      localFile,
    );

    if (!changed) {
      return false;
    }

    await service.uploadFile(dropboxPath, localFile);

    return true;
  }

  Future<bool> _updateWallListIfChanged({
    required DropboxFileService service,
  }) async {
    // ------------------------------------------------------------
    // DOWNLOAD THE LATEST MASTER WALLLIST FROM DROPBOX
    // ------------------------------------------------------------

    final remoteBytes = await service.downloadFileBytes('/walllist.csv');

    final remoteRaw = utf8.decode(remoteBytes);

    final remoteLines = const LineSplitter().convert(remoteRaw);

    if (remoteLines.isEmpty) {
      throw Exception("Dropbox walllist.csv is empty.");
    }

    // ------------------------------------------------------------
    // LOAD THE LOCALLY EDITED WALLLIST
    // ------------------------------------------------------------

    final dir = await getApplicationDocumentsDirectory();

    final localWallList = File('${dir.path}/walls/global/walllist.csv');

    if (!await localWallList.exists()) {
      throw Exception("Local walllist.csv was not found.");
    }

    final localRaw = await localWallList.readAsString();

    final localLines = const LineSplitter().convert(localRaw);

    // ------------------------------------------------------------
    // FIND THIS WALL IN THE LOCAL COPY
    // ------------------------------------------------------------

    List<String>? localWallValues;

    for (final line in localLines) {
      final values = line.split(',');

      if (values.length > 6 && values[6].trim() == widget.wallId) {
        localWallValues = values;
        break;
      }
    }

    if (localWallValues == null) {
      throw Exception(
        "Wall '${widget.wallId}' does not exist in the local walllist.csv.\n\n"
        "Setup cannot continue.",
      );
    }

    // ------------------------------------------------------------
    // FIND THIS WALL IN THE LATEST DROPBOX COPY
    // ------------------------------------------------------------

    int remoteWallIndex = -1;
    List<String>? remoteWallValues;

    for (int i = 0; i < remoteLines.length; i++) {
      final values = remoteLines[i].split(',');

      if (values.length > 6 && values[6].trim() == widget.wallId) {
        remoteWallIndex = i;
        remoteWallValues = values;
        break;
      }
    }

    if (remoteWallValues == null || remoteWallIndex < 0) {
      throw Exception(
        "Wall '${widget.wallId}' does not exist in the DTB wall list.\n\n"
        "This wall has not been provisioned by DTB, so no changes have been submitted.",
      );
    }

    if (remoteWallValues.length < 7 || localWallValues.length < 7) {
      throw Exception(
        "The walllist.csv entry for ${widget.wallId} is incomplete.",
      );
    }

    // ------------------------------------------------------------
    // ONLY THESE FOUR VALUES MAY BE CHANGED BY WALL SETUP
    //
    // 2 = friendly name
    // 3 = board angle
    // 4 = latitude
    // 5 = longitude
    // ------------------------------------------------------------

    final changed =
        remoteWallValues[2].trim() != localWallValues[2].trim() ||
        remoteWallValues[3].trim() != localWallValues[3].trim() ||
        remoteWallValues[4].trim() != localWallValues[4].trim() ||
        remoteWallValues[5].trim() != localWallValues[5].trim();

    if (!changed) {
      return false;
    }

    // ------------------------------------------------------------
    // MODIFY ONLY THIS WALL'S EDITABLE VALUES
    // ------------------------------------------------------------

    remoteWallValues[2] = localWallValues[2].trim();

    remoteWallValues[3] = localWallValues[3].trim();

    remoteWallValues[4] = localWallValues[4].trim();

    remoteWallValues[5] = localWallValues[5].trim();

    // Everything else in this row stays exactly as supplied
    // by the latest Dropbox walllist.

    final updatedLines = List<String>.from(remoteLines);

    updatedLines[remoteWallIndex] = remoteWallValues.join(',');

    final updatedRaw = '${updatedLines.join('\n')}\n';

    // ------------------------------------------------------------
    // TEMP FILE FOR UPLOAD
    // ------------------------------------------------------------

    final tempDir = await getTemporaryDirectory();

    final tempWallList = File('${tempDir.path}/walllist_submit.csv');

    await tempWallList.writeAsString(updatedRaw, flush: true);

    // ------------------------------------------------------------
    // UPLOAD THE MERGED MASTER WALLLIST
    // ------------------------------------------------------------

    await service.uploadFile('/walllist.csv', tempWallList);

    // Also update this phone's cache to the merged latest version.
    await localWallList.writeAsString(updatedRaw, flush: true);

    return true;
  }

  Future<void> _loadWallSetupInfo() async {
    try {
      final dir = await getApplicationDocumentsDirectory();

      final settingsFile = File('${dir.path}/walls/${widget.wallId}/Settings');

      if (!await settingsFile.exists()) {
        return;
      }

      final lines = await settingsFile.readAsLines();

      if (lines.length < 3) {
        return;
      }

      final symmetrical = lines[2].trim() == "1";

      if (!mounted) return;

      setState(() {
        _isSymmetrical = symmetrical;
      });
    } catch (e) {
      debugPrint("Could not read wall symmetry setting: $e");
    }
  }

  // ================================================================
  // SUBMIT
  // ================================================================

  Future<void> _submitWall() async {
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _submitStatus = "Preparing files...";
    });

    try {
      final dir = await getApplicationDocumentsDirectory();

      final wallDir = Directory('${dir.path}/walls/${widget.wallId}');

      final service = DropboxFileService(DropboxAuthService());

      // =========================================================
      // PRE-FLIGHT SAFETY CHECK
      //
      // Everything must already exist in Dropbox.
      // Wall Setup is allowed to MODIFY a DTB wall,
      // never provision a new one.
      // =========================================================

      setState(() {
        _submitStatus = "Checking DTB wall setup...";
      });

      // Master walllist must exist.
      final wallListBytes = await service.downloadFileBytes('/walllist.csv');

      final wallListRaw = utf8.decode(wallListBytes);

      final wallExists = const LineSplitter().convert(wallListRaw).any((line) {
        final values = line.split(',');

        return values.length > 6 && values[6].trim() == widget.wallId;
      });

      if (!wallExists) {
        throw Exception(
          "Wall '${widget.wallId}' is not in the DTB wall list.\n\n"
          "No files have been changed.",
        );
      }

      // All four wall files must already exist.
      await service.downloadFileBytes('/${widget.wallId}/Settings');

      await service.downloadFileBytes('/${widget.wallId}/holdlist.csv');

      await service.downloadFileBytes('/${widget.wallId}/dicholdlist.txt');

      await service.downloadFileBytes('/${widget.wallId}/wall.png');

      if (_isSymmetrical) {
        await service.downloadFileBytes('/${widget.wallId}/MirrorDic.txt');
      }

      // =========================================================
      // SETTINGS
      // =========================================================

      setState(() {
        _submitStatus = "Checking Settings...";
      });

      final settingsChanged = await _uploadIfChanged(
        service: service,
        dropboxPath: '/${widget.wallId}/Settings',
        localFile: File('${wallDir.path}/Settings'),
      );

      // =========================================================
      // HOLDLIST
      // =========================================================

      setState(() {
        _submitStatus = "Checking hold list...";
      });

      final holdListChanged = await _uploadIfChanged(
        service: service,
        dropboxPath: '/${widget.wallId}/holdlist.csv',
        localFile: File('${wallDir.path}/holdlist.csv'),
      );

      // =========================================================
      // MAPPING
      // =========================================================

      setState(() {
        _submitStatus = "Checking wall mapping...";
      });

      final mappingChanged = await _uploadIfChanged(
        service: service,
        dropboxPath: '/${widget.wallId}/dicholdlist.txt',
        localFile: File('${wallDir.path}/dicholdlist.txt'),
      );

      // =========================================================
      // WALL PICTURE
      // =========================================================

      setState(() {
        _submitStatus = "Checking wall picture...";
      });

      final pictureChanged = await _uploadIfChanged(
        service: service,
        dropboxPath: '/${widget.wallId}/wall.png',
        localFile: File('${wallDir.path}/wall.png'),
      );

      if (!mounted) return;

      setState(() {
        _submitting = false;
        _submitStatus = "";
      });

      bool mirrorChanged = false;

      if (_isSymmetrical) {
        setState(() {
          _submitStatus = "Checking mirror mapping...";
        });

        mirrorChanged = await _uploadIfChanged(
          service: service,
          dropboxPath: '/${widget.wallId}/MirrorDic.txt',
          localFile: File('${wallDir.path}/MirrorDic.txt'),
        );
      }

      // =========================================================
      // WALL INFORMATION
      // =========================================================

      setState(() {
        _submitStatus = "Checking wall information...";
      });

      final wallListChanged = await _updateWallListIfChanged(service: service);

      // =========================================================
      // RESULTS
      // =========================================================

      // =========================================================
      // RESULTS
      // =========================================================

      // These changes currently require DTB to update the
      // physical controller before they take effect.
      final requiresDtbUpdate =
          settingsChanged ||
          holdListChanged ||
          (_isSymmetrical && mirrorChanged);

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  requiresDtbUpdate
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle,
                  color: requiresDtbUpdate ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    requiresDtbUpdate ? "Wall Submitted" : "Wall Ready",
                  ),
                ),
              ],
            ),

            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!requiresDtbUpdate) ...[
                    const Text(
                      "Well done — your wall setup has been updated "
                      "successfully and is ready to use.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(height: 18),
                  ],

                  _submitResultRow("Settings", settingsChanged),
                  _submitResultRow("Hold list", holdListChanged),
                  _submitResultRow("Wall mapping", mappingChanged),
                  _submitResultRow("Wall picture", pictureChanged),
                  _submitResultRow("Wall information", wallListChanged),

                  if (_isSymmetrical)
                    _submitResultRow("Mirror mapping", mirrorChanged),

                  if (requiresDtbUpdate) ...[
                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange,
                            size: 32,
                          ),

                          SizedBox(height: 10),

                          Text(
                            "Physical Controller Update Required",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),

                          SizedBox(height: 10),

                          Text(
                            "Your changes have been submitted successfully, "
                            "but one or more changes require an update to the "
                            "physical DTB controller.\n\n"
                            "Please contact Digital Training Boards before "
                            "using the updated setup:\n\n"
                            "digitaltrainingboards@btinternet.com",
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text("OK"),
              ),
            ],
          );
        },
      );

      // The results window has been acknowledged.
      // Leave Wall Setup and return to the Settings page.
      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _submitting = false;
        _submitStatus = "";
      });

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text("Submit Failed"),
            content: Text(
              "An error occurred while submitting the wall setup:\n\n$e",
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text("OK"),
              ),
            ],
          );
        },
      );
    }
  }

  Widget _submitResultRow(String name, bool changed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            changed ? Icons.cloud_upload : Icons.check,
            color: changed ? Colors.blue : Colors.green,
          ),

          const SizedBox(width: 10),

          Expanded(child: Text(name)),

          Text(
            changed ? "Uploaded" : "Unchanged",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: changed ? Colors.blue : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // CONNECTIONS
  // ================================================================

  Future<void> _openConnections() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ConnectionsSetupPage(wallId: widget.wallId),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      setState(() {
        _bluetoothConnected = true;
        _internetConnected = true;
      });
    }
  }

  // ================================================================
  // SETTINGS
  // ================================================================

  Future<void> _openSettings() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsSetupPage(wallId: widget.wallId),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      setState(() {
        _settingsComplete = true;
      });

      await _loadWallSetupInfo();
    }
  }

  // ================================================================
  // PICTURE
  // ================================================================

  Future<void> _openPicture() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PictureSetupPage(wallId: widget.wallId),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      setState(() {
        _pictureComplete = true;
      });
    }
  }

  // ================================================================
  // MAP
  // ================================================================

  Future<void> _openMap() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => MapSetupPage(wallId: widget.wallId)),
    );

    if (!mounted) return;

    if (result == true) {
      setState(() {
        _mapComplete = true;
      });
    }
  }

  // ================================================================
  // MIRROR
  // ================================================================

  Future<void> _openMirror() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => MirrorSetupPage(wallId: widget.wallId)),
    );

    if (!mounted) return;

    if (result == true) {
      setState(() {
        _mirrorComplete = true;
      });
    }
  }

  // ================================================================
  // SUBMIT
  // ================================================================
}
