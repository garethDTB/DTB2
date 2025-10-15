// lib/services/websocket_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class ProblemUpdaterService {
  static final ProblemUpdaterService instance =
      ProblemUpdaterService._internal();
  ProblemUpdaterService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnecting = false;

  int _reconnectDelay = 5; // seconds (will back off up to 60s)

  // ✅ Stream for incoming messages
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  /// Connect to Azure SignalR
  Future<void> connect() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      // Step 1: Negotiate
      final negotiateUrl =
          "https://problemswebapi20220905155830.azurewebsites.net/updater/negotiate?negotiateVersion=0";
      final response = await http.post(Uri.parse(negotiateUrl));
      if (response.statusCode != 200) {
        throw Exception("Negotiate failed: ${response.statusCode}");
      }
      final data = jsonDecode(response.body);
      final connectionId = data['connectionId'];
      print("🔑 Negotiated connectionId = $connectionId");

      // Step 2: Connect to WebSocket
      final wsUrl =
          "wss://problemswebapi20220905155830.azurewebsites.net/updater?id=$connectionId";
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      print("✅ Connected to Azure SignalR at $wsUrl");

      // Step 3: Send handshake
      final handshake =
          jsonEncode({"protocol": "json", "version": 1}) + "\u001e";
      _channel!.sink.add(handshake);
      print("🤝 Sent handshake: $handshake");

      // Step 4: Listen for messages
      _subscription = _channel!.stream.listen(
        (message) {
          print("📩 Received: $message");
          _reconnectDelay = 5; // reset reconnect delay

          try {
            final clean = message.toString().replaceAll('\u001e', '').trim();
            if (clean.isNotEmpty) {
              final decoded = jsonDecode(clean);
              _controller.add(decoded); // ✅ push into stream
            }
          } catch (e) {
            print("⚠️ Failed to decode WS message: $e");
          }
        },
        onError: (e) {
          print("⚠️ WebSocket error: $e");
          _scheduleReconnect();
        },
        onDone: () {
          print("❌ WebSocket closed");
          _scheduleReconnect();
        },
      );
    } catch (e) {
      print("⚠️ WebSocket connection failed: $e");
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  /// Send a problem update (SignalR format)
  void sendProblem(
    String user,
    String problemName,
    bool mirrored,
    String board,
  ) {
    if (_channel == null) {
      print("⚠️ WebSocket not connected, trying to reconnect...");
      connect().then((_) {
        print("⚠️ Problem not sent automatically, user must retry.");
      });
      return;
    }

    final msg = {
      "type": 1,
      "invocationId": DateTime.now().millisecondsSinceEpoch.toString(),
      "target": "UpdateProblem",
      "arguments": [user, problemName, mirrored, board],
    };

    final payload = jsonEncode(msg) + "\u001e"; // SignalR frame
    _channel!.sink.add(payload);
    print("📤 Sent UpdateProblem: $payload");
  }

  /// Force disconnect
  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close(status.goingAway);
    _channel = null;
    print("❌ WebSocket disconnected");
  }

  /// Schedule reconnect with exponential backoff
  void _scheduleReconnect() {
    if (_isConnecting) return;

    print("⏳ Scheduling reconnect in $_reconnectDelay seconds...");
    Future.delayed(Duration(seconds: _reconnectDelay), () {
      connect();
    });

    _reconnectDelay = (_reconnectDelay * 2).clamp(5, 60);
  }
}
