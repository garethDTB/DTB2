import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle, ByteData;

class ApiService {
  final String baseUrl;

  ApiService(this.baseUrl);

  /// ------------------------------
  /// Helpers
  /// ------------------------------
  Future<dynamic> _getJson(Uri url) async {
    final response = await http.get(url);
    if (response.statusCode == 200) {
      if (response.body.isEmpty) return {};
      return json.decode(response.body);
    } else {
      throw Exception('Request failed [${response.statusCode}] for $url');
    }
  }

  Future<dynamic> _postJson(Uri url, Map<String, dynamic> payload) async {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(payload),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'POST failed [${response.statusCode}] for $url\nPayload: $payload',
      );
    }

    if (response.body.isEmpty) return {};
    return json.decode(response.body);
  }

  Future<SharedPreferences> get _prefs async =>
      await SharedPreferences.getInstance();

  /// ------------------------------
  /// TICKS
  /// ------------------------------
  Future<List<Map<String, dynamic>>> getWallTicks(String wallId) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/ticks');
    final data = await _getJson(url);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> updateTick(String wallId, String problem, int delta) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/ticks');
    final payload = {"Problem": problem, "Wall": wallId, "Delta": delta};
    await _postJson(url, payload);
  }

  /// ------------------------------
  /// LIKES
  /// ------------------------------
  Future<Map<String, dynamic>> getWallLikes(String wallId, String user) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/likes?user=$user');
    final decoded = await _getJson(url);
    return {
      "aggregated":
          (decoded["aggregated"] as List?)?.cast<Map<String, dynamic>>() ?? [],
      "user": decoded["user"] as Map<String, dynamic>? ?? {},
    };
  }

  Future<void> addLike(String wallId, String user, String problem) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/likes');
    final payload = {
      "User": user,
      "Problem": problem,
      "Wall": wallId,
      "Like": true,
    };
    await _postJson(url, payload);
    await _updateLocalLikesCache(wallId, problem, like: true);
  }

  Future<void> removeLike(String wallId, String user, String problem) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/likes');
    final payload = {
      "User": user,
      "Problem": problem,
      "Wall": wallId,
      "Like": false,
    };
    await _postJson(url, payload);
    await _updateLocalLikesCache(wallId, problem, like: false);
  }

  /// ------------------------------
  /// SESSIONS
  /// ------------------------------
  Future<List<Map<String, dynamic>>> getSessions(
    String wallId,
    String user,
  ) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/sessions?user=$user');
    final data = await _getJson(url);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createSession(
    String wallId,
    String user, {
    int score = 0,
    List<Map<String, dynamic>> attempts = const [],
    List<Map<String, dynamic>> sent = const [],
    String? date,
  }) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/sessions');
    final payload = {
      "User": user,
      "Score": score,
      "Attempts": attempts,
      "Sent": sent,
    };
    if (date != null) payload["Date"] = date;

    final data = await _postJson(url, payload);
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> addAttempt(
    String wallId,
    String user,
    String problem,
    String grade,
  ) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/sessions/attempt');
    final payload = {
      "User": user,
      "Wall": wallId,
      "Problem": problem,
      "Grade": grade,
      "Number": 1,
    };
    final data = await _postJson(url, payload);
    return data as Map<String, dynamic>; // full updated session
  }

  Future<Map<String, dynamic>> addTick(
    String wallId,
    String user,
    String problem,
    String grade,
    int points, {
    bool flash = false,
  }) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/sessions/tick');
    final payload = {
      "User": user,
      "Wall": wallId,
      "Problem": problem,
      "Grade": grade,
      "Points": points,
      "Flash": flash,
    };
    final data = await _postJson(url, payload);
    return data as Map<String, dynamic>; // full updated session
  }

  /// ------------------------------
  /// Local likes cache
  /// ------------------------------
  Future<void> _updateLocalLikesCache(
    String wallId,
    String problem, {
    required bool like,
  }) async {
    final prefs = await _prefs;
    final rawCache = prefs.getString('likes_$wallId');

    Map<String, dynamic> decoded = rawCache != null
        ? jsonDecode(rawCache)
        : {"aggregated": [], "user": {}};

    final List<dynamic> aggregated = decoded['aggregated'] ?? [];
    final item = aggregated.cast<Map<String, dynamic>>().firstWhere(
      (e) => e['Problem'] == problem,
      orElse: () => {},
    );

    if (like) {
      if (item.isNotEmpty) {
        item['Count'] = (item['Count'] as int) + 1;
      } else {
        aggregated.add({"Problem": problem, "Count": 1});
      }
    } else {
      if (item.isNotEmpty) {
        item['Count'] = (item['Count'] as int) - 1;
        if (item['Count'] <= 0) aggregated.remove(item);
      }
    }

    final Map<String, dynamic> userLikes =
        (decoded['user'] as Map?)?.cast<String, dynamic>() ?? {};
    if (like) {
      userLikes[problem] = true;
    } else {
      userLikes.remove(problem);
    }

    decoded['aggregated'] = aggregated;
    decoded['user'] = userLikes;

    await prefs.setString('likes_$wallId', jsonEncode(decoded));
  }

  /// ------------------------------
  /// Delete a sent problem
  /// ------------------------------
  Future<Map<String, dynamic>> deleteSentProblem(
    String wallId,
    String sessionId,
    String problemName,
    String user,
  ) async {
    final url = Uri.parse(
      '$baseUrl/walls/$wallId/sessions/$sessionId/sent/$problemName?user=$user',
    );

    final resp = await http.delete(url);
    if (resp.statusCode != 200) {
      throw Exception(
        "Failed to delete sent problem [$problemName] from session $sessionId "
        "status [${resp.statusCode}] ${resp.body}",
      );
    }

    return json.decode(resp.body) as Map<String, dynamic>;
  }

  /// ------------------------------
  /// TEST.CSV loader from assets
  /// ------------------------------
  Future<List<Map<String, dynamic>>> getTestFile(String wallId) async {
    try {
      final raw = await rootBundle.loadString('assets/walls/$wallId/test.csv');
      final lines = const LineSplitter().convert(raw);

      if (lines.isEmpty) return [];

      final headers = lines.first.split(',');
      return lines.skip(1).map((line) {
        final values = line.split(',');
        return {
          for (int i = 0; i < headers.length && i < values.length; i++)
            headers[i].trim(): values[i].trim(),
        };
      }).toList();
    } catch (e) {
      throw Exception("❌ Failed to load test.csv for $wallId: $e");
    }
  }

  /// ------------------------------
  /// AUTH
  /// ------------------------------
  Future<Map<String, dynamic>> login(String username, String password) async {
    final url = Uri.parse('$baseUrl/login');
    final payload = {"username": username, "password": password};
    final data = await _postJson(url, payload);
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> register(
    String username,
    String realName,
    String password,
  ) async {
    final url = Uri.parse('$baseUrl/register');
    final payload = {
      "username": username,
      "real_name": realName,
      "password": password,
    };
    final data = await _postJson(url, payload);
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resetPassword(String username) async {
    final url = Uri.parse('$baseUrl/reset');
    final payload = {"username": username};
    final data = await _postJson(url, payload);
    return data as Map<String, dynamic>;
  }

  /// ------------------------------
  /// ACCOUNT DELETION
  /// ------------------------------
  Future<bool> deleteAccount(String username, String password) async {
    try {
      final url = Uri.parse('$baseUrl/users/delete');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"username": username, "password": password}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print("❌ Account deletion error: $e");
      return false;
    }
  }

  /// ------------------------------
  /// PROBLEMS
  /// ------------------------------
  Future<List<Map<String, dynamic>>> getWallProblems(String wallId) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/problems');
    final data = await _getJson(url);

    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    } else if (data is Map && data.containsKey('value')) {
      return (data['value'] as List).cast<Map<String, dynamic>>();
    } else {
      throw Exception("Unexpected response format for problems: $data");
    }
  }

  Future<String> getWallTestFile(String wallId, String username) async {
    final response = await http.get(
      Uri.parse("$baseUrl/walls/$wallId/test?user=$username"),
    );

    if (response.statusCode == 200) {
      return response.body; // raw CSV string
    } else {
      throw Exception("Failed to fetch test.csv: ${response.body}");
    }
  }

  Future<Map<String, dynamic>> saveProblem(
    String wallId,
    String problem,
    String grade,
    String comment,
    String setter,
    int stars,
    List<String> startHolds,
    List<String> intermediateHolds,
    String finishHold,
  ) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/problems');

    final payload = {
      "Wall": wallId,
      "Problem": problem,
      "Grade": grade,
      "Comment": comment,
      "Setter": setter,
      "Stars": stars,
      "StartHolds": startHolds,
      "IntermediateHolds": intermediateHolds,
      "FinishHold": finishHold,
    };

    final data = await _postJson(url, payload);
    return data as Map<String, dynamic>;
  }

  /// ------------------------------
  /// WHAT'S ON
  /// ------------------------------
  Future<Map<String, dynamic>?> getWhatsOn(String wallId) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/whatson');
    final data = await _getJson(url);
    if (data == null || data is! Map<String, dynamic>) return null;
    return data;
  }

  Future<String?> getProblemIdByName(String wallId, String problemName) async {
    final problems = await getWallProblems(wallId);
    final match = problems.firstWhere(
      (p) => (p['Problem'] as String).trim() == problemName.trim(),
      orElse: () => {},
    );
    return match.isNotEmpty ? match['id'] as String? : null;
  }

  /// ------------------------------
  /// PROBLEMS - DELETE
  /// ------------------------------
  Future<void> deleteProblem(String wallId, String problemId) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/problems/$problemId');

    final resp = await http.delete(url);
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception(
        "Failed to delete problem [$problemId] from wall [$wallId]. "
        "status [${resp.statusCode}] ${resp.body}",
      );
    }
  }

  /// ------------------------------
  /// COMMENTS
  /// ------------------------------
  Future<List<Map<String, dynamic>>> getComments(
    String wallId,
    String problemName,
  ) async {
    final url = Uri.parse(
      '$baseUrl/walls/$wallId/comments?problem=${Uri.encodeComponent(problemName)}',
    );
    final data = await _getJson(url);
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    } else if (data is Map && data.containsKey('value')) {
      return (data['value'] as List).cast<Map<String, dynamic>>();
    } else {
      return [];
    }
  }

  Future<void> saveComment(
    String wallId,
    String problemName,
    String user,
    String grade,
    String comment,
  ) async {
    final url = Uri.parse('$baseUrl/walls/$wallId/comments');
    final payload = {
      "User": user,
      "Wall": wallId,
      "Problem": problemName,
      "Grade": grade,
      "Comment": comment,
      "Date": DateTime.now().toIso8601String(),
    };
    await _postJson(url, payload);
  }
}
