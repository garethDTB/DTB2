import 'dart:async';

import 'package:flutter/material.dart';

import 'services/ble_cast_service.dart';

class ConnectionsSetupPage extends StatefulWidget {
  final String wallId;

  const ConnectionsSetupPage({super.key, required this.wallId});

  @override
  State<ConnectionsSetupPage> createState() => _ConnectionsSetupPageState();
}

class _ConnectionsSetupPageState extends State<ConnectionsSetupPage> {
  final BleCastService _bleService = BleCastService();

  final TextEditingController _ssidController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  StreamSubscription<Map<String, dynamic>>? _responseSubscription;

  bool _connectingBluetooth = false;
  bool _sendingWifi = false;

  bool _bluetoothConnected = false;
  bool _wifiConnected = false;
  bool _internetConnected = false;
  int? _signalStrength;
  String _wifiMac = "";
  bool _dnsWorking = false;
  bool _showPassword = false;

  bool _showWifiSetup = false;
  bool _showTechnicalDetails = false;
  bool _showInternetStage = true;
  bool _startupConfirmed = false;

  bool _bootTestConfirmed = false;
  String _currentSsid = "";
  String _ipAddress = "";
  String _statusMessage = "";
  bool _restartingBoard = false;
  bool _restartConfirmed = false;
  bool _ledTestConfirmed = false;
  bool _framesRunning = false;
  bool _waitingForFrames = false;
  bool _waitingForBoardReady = false;

  String get _boardName => "DTB Board ${widget.wallId}";

  bool get _complete =>
      _bluetoothConnected &&
      _wifiConnected &&
      _internetConnected &&
      _dnsWorking &&
      _restartConfirmed &&
      _startupConfirmed;

  @override
  void initState() {
    super.initState();

    _responseSubscription = _bleService.responses.listen(_handleBleResponse);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectAndCheck();
    });
  }

  @override
  void dispose() {
    _responseSubscription?.cancel();
    _ssidController.dispose();
    _passwordController.dispose();

    // Do NOT call endSetup() here.
    //
    // We want BLE setup mode to remain active
    // when returning to WallSetupPage because
    // Map and Mirror will need the connection.

    super.dispose();
  }

  // ============================================================
  // CONNECT TO BOARD
  // ============================================================

  Future<void> _connectAndCheck() async {
    if (_connectingBluetooth) return;

    setState(() {
      _connectingBluetooth = true;
      _statusMessage = "Looking for $_boardName...";
    });

    try {
      await _bleService.requestConnectionStatus(boardName: _boardName);

      if (!mounted) return;

      setState(() {
        _bluetoothConnected = true;
        _statusMessage = "Bluetooth connected. Checking board...";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _bluetoothConnected = false;
        _wifiConnected = false;
        _internetConnected = false;
        _statusMessage = "Bluetooth connection failed: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          _connectingBluetooth = false;
        });
      }
    }
  }

  // ============================================================
  // HANDLE PI RESPONSES
  // ============================================================

  void _handleBleResponse(Map<String, dynamic> data) {
    final type = data["type"];

    if (type != "connection_status" && type != "wifi_status") {
      return;
    }

    final wifi = data["wifi"] == true;

    final internet = data["internet"] == true;

    final ssid = (data["ssid"] ?? "").toString();

    final ip = (data["ip"] ?? "").toString();

    final connecting = data["connecting"] == true;

    final success = data["success"] == true;

    final error = (data["error"] ?? "").toString();

    final signal = data["signal"];

    final mac = (data["mac"] ?? "").toString();

    final dns = data["dns"] == true;

    final boardReady = data["board_ready"] == true;
    if (!mounted) return;

    setState(() {
      _bluetoothConnected = true;
      _wifiConnected = wifi;
      _internetConnected = internet;

      _currentSsid = ssid;
      _ipAddress = ip;

      // NEW
      _signalStrength = signal is int
          ? signal
          : int.tryParse(signal?.toString() ?? "");

      _wifiMac = mac;
      _dnsWorking = dns;

      _framesRunning = boardReady;

      // existing code continues below here...

      if (ssid.isNotEmpty && _ssidController.text.isEmpty) {
        _ssidController.text = ssid;
      }
      if (!_waitingForBoardReady) {
        if (connecting) {
          _statusMessage =
              "Connecting the board to $ssid...\n\n"
              "Please wait while the connection is tested.";
        } else if (type == "wifi_status" && success) {
          _statusMessage =
              "Wi-Fi setup successful.\n\n"
              "Connected to: $ssid\n"
              "Internet connection confirmed.";
        } else if (error.contains("was not found")) {
          _statusMessage =
              "$error\n\n"
              "Check the Wi-Fi network name and try again.";
        } else if (error.contains("previous network has been restored")) {
          _statusMessage =
              "The board could not connect using those Wi-Fi details.\n\n"
              "The previous working network has been restored.\n\n"
              "Check the Wi-Fi password and try again.";
        } else if (error.contains("browser login")) {
          _statusMessage =
              "The board connected to Wi-Fi, but Internet access is blocked.\n\n"
              "This network may require a browser login or acceptance page.\n\n"
              "Try another network, use Ethernet, or ask the centre's IT team "
              "to whitelist this controller.\n\n"
              "Wi-Fi MAC: $_wifiMac";
        } else if (error.isNotEmpty) {
          _statusMessage =
              "$error\n\n"
              "Check the Wi-Fi details and try again.";
        } else if (wifi && internet) {
          _statusMessage = "Board is connected and online.";
        } else if (wifi && !internet) {
          _statusMessage =
              "The board is connected to Wi-Fi but has no Internet access.\n\n"
              "This network may require a browser login.";
        } else {
          _statusMessage = "The board is not connected to Wi-Fi.";
        }

        if (!connecting) {
          _sendingWifi = false;
        }
      }
    });
  }

  Future<void> _restartBoard() async {
    if (_restartingBoard) return;

    setState(() {
      _restartingBoard = true;
      _restartConfirmed = false;
      _bootTestConfirmed = false;
      _framesRunning = false;

      _statusMessage =
          "Board is restarting...\n\n"
          "Waiting for the controller to restart.";
    });

    try {
      // --------------------------------------------------------
      // 1. SEND RESTART COMMAND FIRST
      // --------------------------------------------------------

      print("🔄 Sending restart_board to $_boardName");

      await _bleService.restartBoard(boardName: _boardName);

      print("🔄 Restart command sent");

      // Give the Pi time to actually shut down.
      await Future.delayed(const Duration(seconds: 8));

      // --------------------------------------------------------
      // 2. FORGET OLD BLE CONNECTION
      // --------------------------------------------------------

      await BleCastService.disconnect();

      if (!mounted) return;

      setState(() {
        _bluetoothConnected = false;
        _wifiConnected = false;
        _internetConnected = false;
        _dnsWorking = false;

        _statusMessage =
            "Board is restarting...\n\n"
            "Looking for $_boardName";
      });

      // --------------------------------------------------------
      // 3. WAIT FOR BLE TO COME BACK
      // --------------------------------------------------------

      bool reconnected = false;

      for (int attempt = 0; attempt < 20; attempt++) {
        if (!mounted) return;

        try {
          await _bleService.requestConnectionStatus(boardName: _boardName);

          reconnected = true;
          break;
        } catch (_) {
          if (!mounted) return;

          setState(() {
            _statusMessage =
                "Board is restarting...\n\n"
                "Looking for $_boardName\n"
                "Attempt ${attempt + 1} of 20";
          });

          await Future.delayed(const Duration(seconds: 3));
        }
      }

      if (!mounted) return;

      if (!reconnected) {
        setState(() {
          _restartingBoard = false;

          _statusMessage =
              "The board did not reconnect after restarting.\n\n"
              "Check that the controller has power and try again.";
        });

        return;
      }

      // --------------------------------------------------------
      // 4. BLE IS BACK - NOW WAIT FOR FRAMES2
      // --------------------------------------------------------

      setState(() {
        _waitingForBoardReady = true;

        _statusMessage =
            "Bluetooth and network are back.\n\n"
            "Waiting for the wall to finish loading...";
      });

      bool framesReady = false;

      for (int attempt = 0; attempt < 50; attempt++) {
        if (!mounted) return;

        await _bleService.requestConnectionStatus(boardName: _boardName);

        await Future.delayed(const Duration(seconds: 3));

        if (_framesRunning) {
          framesReady = true;
          break;
        }

        if (!mounted) return;

        setState(() {
          _statusMessage =
              "Network connection confirmed.\n\n"
              "Waiting for wall software to start...\n"
              "Check ${attempt + 1} of 50";
        });
      }

      if (!mounted) return;

      if (!framesReady) {
        setState(() {
          _restartingBoard = false;

          _statusMessage =
              "The controller restarted and reconnected,\n"
              "but the wall software did not start.\n\n"
              "Check the controller or try again.";
        });

        return;
      }

      // --------------------------------------------------------
      // 5. EVERYTHING HAS STARTED
      // --------------------------------------------------------

      // --------------------------------------------------------
      // 5. EVERYTHING HAS STARTED
      // --------------------------------------------------------

      // Do one final full status check now that Frames is running.
      await _bleService.requestConnectionStatus(boardName: _boardName);

      await Future.delayed(const Duration(seconds: 1));

      if (!mounted) return;

      if (!_bluetoothConnected ||
          !_wifiConnected ||
          !_internetConnected ||
          !_dnsWorking) {
        setState(() {
          _waitingForBoardReady = false;
          _restartingBoard = false;
          _restartConfirmed = false;

          _statusMessage =
              "The wall software has started, but the final "
              "connection check did not pass.\n\n"
              "Check the Internet connection and try again.";
        });

        return;
      }

      setState(() {
        _waitingForBoardReady = false;
        _restartConfirmed = true;
        _restartingBoard = false;

        _statusMessage =
            "Controller restarted successfully.\n\n"
            "Bluetooth, Wi-Fi, Internet and DNS are working.\n"
            "The wall software is running.\n"
            "LED 0 should now be green.";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _waitingForBoardReady = false;
        _restartingBoard = false;

        _statusMessage =
            "The controller restarted and reconnected,\n"
            "but the wall did not finish loading.\n\n"
            "Check the controller or try again.";
      });
    }
  }

  // ============================================================
  // WIFI SETUP
  // ============================================================

  Future<void> _connectWifi() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;

    print("========================================");
    print("📶 WIFI SETUP BUTTON PRESSED");
    print("📶 Board: $_boardName");
    print("📶 SSID: $ssid");
    print("📶 Password length: ${password.length}");
    print("📶 Bluetooth connected: $_bluetoothConnected");
    print("========================================");

    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a Wi-Fi network name.")),
      );
      return;
    }

    setState(() {
      _sendingWifi = true;

      _statusMessage = "Sending Wi-Fi details to the board...";
    });

    try {
      await _bleService.setupWifi(
        boardName: _boardName,
        ssid: ssid,
        password: password,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _sendingWifi = false;
        _statusMessage = "Wi-Fi setup failed: $e";
      });
    }
  }

  // ============================================================
  // STATUS ROW
  // ============================================================

  Widget _statusRow({
    required IconData icon,
    required String title,
    required bool ok,
    String? subtitle,
  }) {
    return ListTile(
      leading: Icon(
        ok ? Icons.check_circle : icon,
        color: ok ? Colors.green : Colors.grey,
      ),
      title: Text(title),
      subtitle: subtitle == null || subtitle.isEmpty ? null : Text(subtitle),
      trailing: Text(
        ok ? "Connected" : "Required",
        style: TextStyle(
          color: ok ? Colors.green : Colors.grey,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _signalLabel(int? dbm) {
    if (dbm == null) return "Unknown";
    if (dbm >= -60) return "Excellent";
    if (dbm >= -67) return "Good";
    if (dbm >= -75) return "Fair";
    return "Poor";
  }

  Widget _bootStage({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bootArrow() {
    return const Padding(
      padding: EdgeInsets.only(left: 9, top: 3, bottom: 3),
      child: Icon(Icons.arrow_downward, size: 15, color: Colors.grey),
    );
  }
  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Connections")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.wallId,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 16),
          if (_showInternetStage) ...[
            // ============================================================
            // CONNECTION STATUS
            // ============================================================
            Card(
              child: Column(
                children: [
                  _statusRow(
                    icon: Icons.bluetooth,
                    title: "Bluetooth",
                    ok: _bluetoothConnected,
                    subtitle: _bluetoothConnected
                        ? _boardName
                        : "Looking for the DTB controller",
                  ),

                  const Divider(height: 1),

                  _statusRow(
                    icon: Icons.wifi,
                    title: "Wi-Fi",
                    ok: _wifiConnected,
                    subtitle: _currentSsid.isEmpty
                        ? "Not connected"
                        : _currentSsid,
                  ),

                  const Divider(height: 1),

                  _statusRow(
                    icon: Icons.language,
                    title: "Internet",
                    ok: _internetConnected,
                    subtitle: _internetConnected
                        ? "Internet connection working"
                        : "No Internet connection",
                  ),

                  const Divider(height: 1),

                  _statusRow(
                    icon: Icons.network_wifi,
                    title: "Signal",
                    ok: _signalStrength != null && _signalStrength! >= -75,
                    subtitle: _signalStrength == null
                        ? "Unknown"
                        : "${_signalLabel(_signalStrength)} "
                              "(${_signalStrength} dBm)",
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ============================================================
            // TECHNICAL DETAILS
            // ============================================================
            Card(
              child: ExpansionTile(
                initiallyExpanded: _showTechnicalDetails,
                onExpansionChanged: (value) {
                  setState(() {
                    _showTechnicalDetails = value;
                  });
                },
                leading: const Icon(Icons.info_outline),
                title: const Text("Technical details"),
                children: [
                  ListTile(
                    leading: const Icon(Icons.router_outlined),
                    title: const Text("IP address"),
                    subtitle: Text(_ipAddress.isEmpty ? "Unknown" : _ipAddress),
                  ),

                  const Divider(height: 1),

                  ListTile(
                    leading: const Icon(Icons.perm_device_information_outlined),
                    title: const Text("Wi-Fi MAC"),
                    subtitle: Text(_wifiMac.isEmpty ? "Unknown" : _wifiMac),
                  ),

                  const Divider(height: 1),

                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: const Text("DNS"),
                    subtitle: Text(
                      _dnsWorking
                          ? "Name resolution working"
                          : "DNS unavailable",
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ============================================================
            // BLUETOOTH RETRY
            // ============================================================
            if (_connectingBluetooth)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              ),

            if (!_bluetoothConnected && !_connectingBluetooth)
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _connectAndCheck,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text("Try Bluetooth Again"),
                ),
              ),

            const SizedBox(height: 16),

            // ============================================================
            // WIFI
            // ============================================================
            if (_bluetoothConnected)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.wifi),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _wifiConnected && _currentSsid.isNotEmpty
                                  ? "Connected to $_currentSsid"
                                  : "Board Wi-Fi",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (!_showWifiSetup) ...[
                        const SizedBox(height: 12),

                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _showWifiSetup = true;
                            });
                          },
                          icon: const Icon(Icons.settings),
                          label: Text(
                            _wifiConnected ? "Change Wi-Fi" : "Set Up Wi-Fi",
                          ),
                        ),
                      ],

                      if (_showWifiSetup) ...[
                        const SizedBox(height: 16),

                        TextField(
                          controller: _ssidController,
                          decoration: const InputDecoration(
                            labelText: "Wi-Fi network name",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.wifi),
                          ),
                        ),

                        const SizedBox(height: 12),

                        TextField(
                          controller: _passwordController,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            labelText: "Wi-Fi password",
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showPassword = !_showPassword;
                                });
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _bluetoothConnected && !_sendingWifi
                                ? _connectWifi
                                : null,
                            icon: _sendingWifi
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.wifi_find),
                            label: Text(
                              _sendingWifi
                                  ? "Connecting..."
                                  : "Connect Board to Wi-Fi",
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        TextButton(
                          onPressed: () {
                            setState(() {
                              _showWifiSetup = false;
                            });
                          },
                          child: const Text("Cancel"),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (_showInternetStage) ...[
              const SizedBox(height: 20),

              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed:
                      _bluetoothConnected &&
                          _wifiConnected &&
                          _internetConnected &&
                          _dnsWorking
                      ? () {
                          setState(() {
                            _showInternetStage = false;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text("Next"),
                ),
              ),
            ],
          ],

          const SizedBox(height: 16),

          // ============================================================
          // STARTUP TEST
          // ============================================================
          if (!_showInternetStage && !_startupConfirmed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.power_settings_new),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Controller Startup Test",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _restartingBoard ? null : _restartBoard,
                        icon: const Icon(Icons.restart_alt),
                        label: Text(
                          _restartingBoard
                              ? "Restarting Board..."
                              : "Restart & Test Controller",
                        ),
                      ),
                    ),

                    if (_restartingBoard && _statusMessage.isNotEmpty) ...[
                      const SizedBox(height: 16),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const CircularProgressIndicator(),

                            const SizedBox(height: 12),

                            Text(_statusMessage, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    const Text("Watch LED 0 during startup:"),

                    const SizedBox(height: 14),

                    _bootStage(
                      icon: Icons.circle,
                      title: "Yellow",
                      subtitle: "Launcher started",
                    ),

                    _bootArrow(),

                    _bootStage(
                      icon: Icons.circle,
                      title: "Blue",
                      subtitle: "Bluetooth running",
                    ),

                    _bootArrow(),

                    _bootStage(
                      icon: Icons.circle,
                      title: "White",
                      subtitle: "Internet available and time synchronised",
                    ),

                    _bootArrow(),

                    _bootStage(
                      icon: Icons.lightbulb,
                      title: "All LEDs On",
                      subtitle: "Display software and LEDs starting",
                    ),

                    _bootArrow(),

                    _bootStage(
                      icon: Icons.circle,
                      title: "Green",
                      subtitle: "Wall fully running",
                    ),

                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "If LED 0 turns red:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),

                          SizedBox(height: 6),

                          Text(
                            "Yellow → Red\n"
                            "Bluetooth failed to start. "
                            "Major controller fault — contact DTB.",
                          ),

                          SizedBox(height: 8),

                          Text(
                            "Yellow → Blue → Red\n"
                            "Bluetooth is working but there is "
                            "no Internet connection.",
                          ),
                          const SizedBox(height: 10),

                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _showInternetStage = true;
                                });
                              },
                              icon: const Icon(Icons.wifi),
                              label: const Text("Back to Internet Setup"),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),

          // ============================================================
          // CONFIRM BOOT SEQUENCE
          // ============================================================
          if (!_showInternetStage &&
              _restartConfirmed &&
              !_startupConfirmed) ...[
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 42),

                    const SizedBox(height: 12),

                    const Text(
                      "Did the startup sequence complete correctly?",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      "Yellow → Blue → White\n"
                      "All LEDs illuminated\n"
                      "LED 0 finished Green",
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _bootTestConfirmed = true;
                                _startupConfirmed = true;

                                _statusMessage =
                                    "Controller startup completed successfully.";
                              });
                            },
                            icon: const Icon(Icons.check),
                            label: const Text("Yes"),
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _bootTestConfirmed = false;

                                _statusMessage =
                                    "The startup sequence did not "
                                    "complete correctly.\n\n"
                                    "Check which stage the startup "
                                    "stopped at.";
                              });
                            },
                            icon: const Icon(Icons.close),
                            label: const Text("No"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ============================================================
          // SETUP COMPLETE
          // ============================================================
          if (_startupConfirmed) ...[
            const SizedBox(height: 16),

            Card(
              color: Colors.green.shade50,
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 48),

                    SizedBox(height: 12),

                    Text(
                      "Controller Test Passed",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),

                    SizedBox(height: 12),

                    Text(
                      "Bluetooth connected\n"
                      "Internet connected\n"
                      "Time synchronised\n"
                      "Wall software running",
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ============================================================
          // CURRENT STATUS MESSAGE
          // ============================================================

          // Only show general status during the Internet setup stage.
          // During Controller Test, the restart status is shown inside
          // the Controller Test card instead.
          if (_showInternetStage &&
              _statusMessage.isNotEmpty &&
              !_startupConfirmed)
            Card(
              color: Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_statusMessage, textAlign: TextAlign.center),
              ),
            ),

          const SizedBox(height: 24),

          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _complete
                  ? () {
                      Navigator.pop(context, true);
                    }
                  : null,
              icon: const Icon(Icons.check),
              label: const Text("Continue"),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
