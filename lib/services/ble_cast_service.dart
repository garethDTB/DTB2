import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BleCastService {
  static final Guid serviceUuid = Guid("12345678-1234-5678-1234-56789abcdef0");

  static final Guid charUuid = Guid("12345678-1234-5678-1234-56789abcdef1");

  static BluetoothDevice? _device;
  static BluetoothCharacteristic? _castChar;

  static bool _isConnecting = false;
  static bool _isWriting = false;

  static Timer? _disconnectTimer;

  Future<void> sendTestMessage() async {
    await sendMessage({"problem": "test"});
  }

  Future<void> sendMessage(Map<String, dynamic> message) async {
    if (_isWriting) {
      print("⚠️ BLE write already running, ignoring duplicate");
      return;
    }

    _isWriting = true;

    try {
      final char = await _getCastCharacteristic();

      final payload = utf8.encode(jsonEncode(message));

      await char.write(payload, withoutResponse: false);

      print("✅ BLE message sent");

      await _handleDisconnectMode();
    } catch (e) {
      print("❌ BLE cast failed: $e");

      _device = null;
      _castChar = null;
      _disconnectTimer?.cancel();

      rethrow;
    } finally {
      _isWriting = false;
    }
  }

  Future<void> _handleDisconnectMode() async {
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

  Future<BluetoothCharacteristic> _getCastCharacteristic() async {
    if (_device != null && _castChar != null) {
      final connected = await _isDeviceConnected(_device!);

      if (connected) {
        return _castChar!;
      }

      _device = null;
      _castChar = null;
    }

    if (_isConnecting) {
      while (_isConnecting) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (_device != null && _castChar != null) {
        final connected = await _isDeviceConnected(_device!);
        if (connected) {
          return _castChar!;
        }
      }
    }

    _isConnecting = true;

    try {
      print("📡 BLE connecting to DTB Board...");

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
              final name = result.device.platformName;
              return name.contains("DTB Board");
            })
            .map((result) => result.device)
            .first
            .timeout(const Duration(seconds: 5));
      } on TimeoutException {
        throw Exception("No DTB Board found nearby.");
      } finally {
        await FlutterBluePlus.stopScan();
      }

      print("✅ Found DTB Board: ${targetDevice.platformName}");

      await targetDevice.connect(
        license: License.free,
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      final services = await targetDevice.discoverServices();

      BluetoothCharacteristic? foundChar;

      for (final service in services) {
        if (service.uuid == serviceUuid) {
          for (final c in service.characteristics) {
            if (c.uuid == charUuid) {
              foundChar = c;
              break;
            }
          }
        }
      }

      if (foundChar == null) {
        throw Exception("DTB cast characteristic not found.");
      }

      _device = targetDevice;
      _castChar = foundChar;

      print("✅ BLE ready and kept connected");

      return foundChar;
    } finally {
      _isConnecting = false;
    }
  }

  Future<bool> _isDeviceConnected(BluetoothDevice device) async {
    final state = await device.connectionState.first;
    return state == BluetoothConnectionState.connected;
  }

  static Future<void> disconnect() async {
    _disconnectTimer?.cancel();

    try {
      await _device?.disconnect();
      print("🔌 BLE disconnected");
    } catch (_) {}

    _device = null;
    _castChar = null;
  }
}
