import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  final String baseUrl;

  ApiService(this.baseUrl);

  Future<List<Map<String, dynamic>>> getWallTicks(String wallId) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/ticks');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load ticks');
    }
  }

  Future<void> updateTick(String wallId, String problem, int delta) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/ticks');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'problem': problem, 'delta': delta}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update tick');
    }
  }
}
