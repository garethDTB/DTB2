import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BleCastService {
  static final Guid serviceUuid = Guid("12345678-1234-5678-1234-56789abcdef0");

  // Existing write characteristic
  static final Guid writeCharUuid = Guid(
    "12345678-1234-5678-1234-56789abcdef1",
  );

  // New Pi -> Flutter notification characteristic
  static final Guid notifyCharUuid = Guid(
    "12345678-1234-5678-1234-56789abcdef2",
  );

  static BluetoothDevice? _device;
  static BluetoothCharacteristic? _writeChar;
  static BluetoothCharacteristic? _notifyChar;

  static String? _connectedBoardName;

  static bool _isConnecting = false;
  static bool _isWriting = false;

  static bool _setupMode = false;

  static Timer? _disconnectTimer;

  static StreamSubscription<List<int>>? _notifySubscription;

  static final StreamController<Map<String, dynamic>> _responseController =
      StreamController<Map<String, dynamic>>.broadcast();

  // ============================================================
  // RESPONSE STREAM
  // ============================================================

  Stream<Map<String, dynamic>> get responses => _responseController.stream;

  // ============================================================
  // NORMAL CASTING
  // ============================================================

  Future<void> sendTestMessage({required String boardName}) async {
    await sendMessage({"type": "connection_check"}, boardName: boardName);
  }

  Future<void> sendMessage(
    Map<String, dynamic> message, {
    required String boardName,
  }) async {
    if (_isWriting) {
      print("⏳ BLE write already running - waiting...");

      while (_isWriting) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    _isWriting = true;

    try {
      final char = await _getWriteCharacteristic(boardName);

      final payload = utf8.encode(jsonEncode(message));

      await char.write(payload, withoutResponse: true);

      print(
        "✅ BLE message sent to $boardName: "
        "${jsonEncode(message)}",
      );

      // Setup must stay connected
      if (!_setupMode) {
        await _handleDisconnectMode();
      }
    } catch (e) {
      print("❌ BLE send failed: $e");

      await _clearConnection();

      rethrow;
    } finally {
      _isWriting = false;
    }
  }

  // ============================================================
  // SETUP MODE
  // ============================================================

  Future<void> startSetup({required String boardName}) async {
    print("🛠️ Starting BLE setup mode for $boardName");

    _setupMode = true;

    _disconnectTimer?.cancel();

    await _getWriteCharacteristic(boardName);

    await _ensureNotifications();

    print("✅ BLE setup mode ready");
  }

  Future<void> endSetup() async {
    print("🛠️ Ending BLE setup mode");

    _setupMode = false;

    await disconnect();
  }

  // ============================================================
  // CONNECTION CHECK
  // ============================================================

  Future<void> requestConnectionStatus({required String boardName}) async {
    await startSetup(boardName: boardName);

    await sendMessage({"type": "connection_check"}, boardName: boardName);
  }

  // ============================================================
  // WIFI SETUP
  // ============================================================

  Future<void> setupWifi({
    required String boardName,
    required String ssid,
    required String password,
  }) async {
    print("========================================");
    print("📡 BleCastService.setupWifi()");
    print("📡 Board: $boardName");
    print("📡 SSID: $ssid");
    print("📡 setupMode before: $_setupMode");
    print("========================================");

    await startSetup(boardName: boardName);

    print("📡 startSetup complete");
    print("📡 Sending wifi_setup now...");

    await sendMessage({
      "type": "wifi_setup",
      "ssid": ssid,
      "password": password,
    }, boardName: boardName);

    print("📡 wifi_setup write completed");
  }

  // ============================================================
  // RESTART BOARD
  // ============================================================

  Future<void> restartBoard({required String boardName}) async {
    print("🔄 Requesting board restart: $boardName");

    // Make sure we are connected and notifications are active.
    await startSetup(boardName: boardName);

    await sendMessage({"type": "restart_board"}, boardName: boardName);

    print("🔄 Restart request sent");
  }

  // ============================================================
  // DISCONNECT MODE FOR NORMAL CASTING
  // ============================================================

  Future<void> _handleDisconnectMode() async {
    if (_setupMode) {
      print("🛠️ Setup mode: keeping BLE connected");
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    final mode = prefs.getString('bluetoothMode') ?? 'auto';

    _disconnectTimer?.cancel();

    if (mode == 'exclusive') {
      print("🔒 BLE exclusive mode: keeping connection open");
      return;
    }

    if (mode == 'shared') {
      print("👥 BLE shared mode: disconnecting in 5 seconds");

      _disconnectTimer = Timer(const Duration(seconds: 5), () => disconnect());

      return;
    }

    print("⏱️ BLE auto mode: disconnecting in 30 seconds");

    _disconnectTimer = Timer(const Duration(seconds: 30), () => disconnect());
  }

  // ============================================================
  // GET WRITE CHARACTERISTIC
  // ============================================================

  Future<BluetoothCharacteristic> _getWriteCharacteristic(
    String boardName,
  ) async {
    if (_device != null &&
        _writeChar != null &&
        _connectedBoardName == boardName) {
      final connected = await _isDeviceConnected(_device!);

      if (connected) {
        return _writeChar!;
      }

      await _clearConnection();
    }

    if (_device != null && _connectedBoardName != boardName) {
      print(
        "🔁 Switching BLE board from "
        "$_connectedBoardName to $boardName",
      );

      await disconnect();
    }

    if (_isConnecting) {
      while (_isConnecting) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (_device != null &&
          _writeChar != null &&
          _connectedBoardName == boardName) {
        final connected = await _isDeviceConnected(_device!);

        if (connected) {
          return _writeChar!;
        }
      }
    }

    _isConnecting = true;

    try {
      print("📡 BLE connecting to $boardName...");

      final isSupported = await FlutterBluePlus.isSupported;

      if (!isSupported) {
        throw Exception("Bluetooth LE is not supported on this device.");
      }

      final adapterState = await FlutterBluePlus.adapterState.first;

      if (adapterState != BluetoothAdapterState.on) {
        throw Exception("Bluetooth is not switched on.");
      }

      BluetoothDevice? targetDevice;

      await FlutterBluePlus.stopScan();

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 4),
        withServices: [serviceUuid],
      );

      try {
        targetDevice = await FlutterBluePlus.scanResults
            .expand((results) => results)
            .where((result) {
              final name = result.device.platformName.trim();

              return name == boardName;
            })
            .map((result) => result.device)
            .first
            .timeout(const Duration(seconds: 5));
      } on TimeoutException {
        throw Exception("No $boardName found nearby.");
      } finally {
        await FlutterBluePlus.stopScan();
      }

      print(
        "✅ Found board: "
        "${targetDevice.platformName}",
      );

      await targetDevice.connect(
        license: License.free,
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      final services = await targetDevice.discoverServices();

      BluetoothCharacteristic? foundWriteChar;

      BluetoothCharacteristic? foundNotifyChar;

      for (final service in services) {
        if (service.uuid == serviceUuid) {
          for (final c in service.characteristics) {
            if (c.uuid == writeCharUuid) {
              foundWriteChar = c;
            }

            if (c.uuid == notifyCharUuid) {
              foundNotifyChar = c;
            }
          }
        }
      }

      if (foundWriteChar == null) {
        throw Exception("DTB write characteristic not found.");
      }

      if (foundNotifyChar == null) {
        throw Exception("DTB notify characteristic not found.");
      }

      _device = targetDevice;

      _writeChar = foundWriteChar;

      _notifyChar = foundNotifyChar;

      _connectedBoardName = boardName;

      print("✅ BLE connected to $boardName");

      return foundWriteChar;
    } finally {
      _isConnecting = false;
    }
  }

  // ============================================================
  // NOTIFICATIONS
  // ============================================================

  Future<void> _ensureNotifications() async {
    final notifyChar = _notifyChar;

    final device = _device;

    if (notifyChar == null || device == null) {
      throw Exception("BLE notify characteristic unavailable.");
    }

    if (_notifySubscription != null) {
      return;
    }

    _notifySubscription = notifyChar.onValueReceived.listen((value) {
      if (value.isEmpty) {
        return;
      }

      try {
        final text = utf8.decode(value);

        print("📥 BLE response: $text");

        final decoded = jsonDecode(text);

        if (decoded is Map<String, dynamic>) {
          _responseController.add(decoded);
        }
      } catch (e) {
        print("❌ BLE response decode failed: $e");
      }
    });

    // FlutterBluePlus recommends cleaning
    // subscriptions when disconnected.
    device.cancelWhenDisconnected(_notifySubscription!);

    await notifyChar.setNotifyValue(true);

    print("🔔 BLE notifications enabled");
  }

  // ============================================================
  // CONNECTION STATE
  // ============================================================

  Future<bool> _isDeviceConnected(BluetoothDevice device) async {
    final state = await device.connectionState.first;

    return state == BluetoothConnectionState.connected;
  }

  // ============================================================
  // CLEAR CONNECTION
  // ============================================================

  static Future<void> _clearConnection() async {
    _disconnectTimer?.cancel();

    try {
      await _notifySubscription?.cancel();
    } catch (_) {}

    _notifySubscription = null;

    _device = null;
    _writeChar = null;
    _notifyChar = null;
    _connectedBoardName = null;
  }

  // ============================================================
  // DISCONNECT
  // ============================================================

  static Future<void> disconnect() async {
    _disconnectTimer?.cancel();

    try {
      await _notifySubscription?.cancel();
    } catch (_) {}

    _notifySubscription = null;

    try {
      await _device?.disconnect();

      print("🔌 BLE disconnected");
    } catch (_) {}

    _device = null;
    _writeChar = null;
    _notifyChar = null;
    _connectedBoardName = null;
  }
}
