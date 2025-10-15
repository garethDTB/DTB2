import 'dart:convert';
import 'package:http/http.dart' as http;

/// Handles Dropbox OAuth token refresh.
/// Place this file in lib/services/dropbox_auth_service.dart
class DropboxAuthService {
  // Replace with your own values from Dropbox app console
  final String _appKey = "3tysfncn94sn3g2";
  final String _appSecret = "wkzqnx275x3uk24";
  final String _refreshToken =
      "A6I3k0bQK3QAAAAAAAAAAcdzAa7bUKRTJm7dmU2dGx-In01i6uPOqo6TmPX2SqOo";

  // Cache the access token in memory
  String? _cachedAccessToken;
  DateTime? _expiryTime;

  /// Get a valid access token.
  /// If cached token is still valid, reuse it.
  /// Otherwise, refresh it from Dropbox.
  Future<String> getAccessToken() async {
    // If we already have a valid cached token, return it
    if (_cachedAccessToken != null &&
        _expiryTime != null &&
        DateTime.now().isBefore(_expiryTime!)) {
      return _cachedAccessToken!;
    }

    final uri = Uri.parse("https://api.dropboxapi.com/oauth2/token");

    final response = await http.post(
      uri,
      headers: {
        "Authorization":
            "Basic ${base64Encode(utf8.encode("$_appKey:$_appSecret"))}",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: {"grant_type": "refresh_token", "refresh_token": _refreshToken},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      _cachedAccessToken = data["access_token"];
      final expiresIn = data["expires_in"]; // usually 14400 seconds (4h)
      _expiryTime = DateTime.now().add(Duration(seconds: expiresIn));

      return _cachedAccessToken!;
    } else {
      throw Exception("Failed to refresh Dropbox token: ${response.body}");
    }
  }
}
