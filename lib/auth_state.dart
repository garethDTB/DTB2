import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'services/api_service.dart';

class AuthState extends ChangeNotifier {
  bool _loggedIn = false;
  String? _username;
  String? _email;
  String? _displayName;

  bool get isLoggedIn => _loggedIn;
  String? get username => _username;
  String? get email => _email;
  String? get displayName => _displayName;

  /// -------------------------
  /// LOGIN
  /// -------------------------
  Future<bool> login(ApiService api, String username, String password) async {
    try {
      final url = Uri.parse("${api.baseUrl}/users/login");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _loggedIn = true;
        _username = data["username"];
        _email = data["email"];
        _displayName = data["display_name"];
        notifyListeners();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool("loggedIn", true);
        await prefs.setString("username", _username!);
        await prefs.setString("email", _email ?? "");
        await prefs.setString("displayName", _displayName ?? "");
        return true;
      }
    } catch (e) {
      debugPrint("❌ Login error: $e");
    }
    return false;
  }

  /// -------------------------
  /// REGISTER
  /// -------------------------
  Future<bool> register(
    ApiService api,
    String username,
    String email,
    String password, {
    String? displayName,
  }) async {
    try {
      final url = Uri.parse("${api.baseUrl}/users/register");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "email": email,
          "password": password,
          "display_name": displayName ?? username,
        }),
      );

      if (response.statusCode == 201) {
        return true;
      } else if (response.statusCode == 400) {
        throw Exception("Username already exists");
      }
    } catch (e) {
      debugPrint("❌ Register error: $e");
      throw Exception("Registration failed");
    }
    return false;
  }

  /// -------------------------
  /// RESET PASSWORD
  /// -------------------------
  /// -------------------------
  /// RESET PASSWORD
  /// -------------------------
  Future<bool> resetPassword(
    ApiService api,
    String username,
    String email,
    String newPassword,
  ) async {
    try {
      final url = Uri.parse("${api.baseUrl}/users/reset");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "email": email,
          "newPassword": newPassword,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 404) {
        // no match of username + email in backend
        return false;
      } else {
        debugPrint("❌ Reset failed: ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Reset password error: $e");
    }
    return false;
  }

  /// -------------------------
  /// AUTO-LOGIN
  /// -------------------------
  Future<void> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool("loggedIn") ?? false) {
      _loggedIn = true;
      _username = prefs.getString("username");
      _email = prefs.getString("email");
      _displayName = prefs.getString("displayName");
      notifyListeners();
    }
  }

  /// -------------------------
  /// LOGOUT
  /// -------------------------
  Future<void> logout() async {
    _loggedIn = false;
    _username = null;
    _email = null;
    _displayName = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("loggedIn");
    await prefs.remove("username");
    await prefs.remove("email");
    await prefs.remove("displayName");
  }
}
