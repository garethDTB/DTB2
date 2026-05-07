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
  String? _town;
  String? _country;
  String? _gender;
  String? _dob;
  String? _bio;
  bool _shareWithFriends = false;
  bool _blackList = false;
  bool _guestMode = false;

  // 👇 NEW superuser flag
  bool _isSuperuser = false;

  // GETTERS
  bool get isGuest => _guestMode;
  bool get isLoggedIn => _loggedIn;
  String? get username => _username;
  String? get email => _email;
  String? get displayName => _displayName;
  String? get town => _town;
  String? get country => _country;
  String? get gender => _gender;
  String? get dob => _dob;
  bool get shareWithFriends => _shareWithFriends;
  bool get blackList => _blackList;
  String? get bio => _bio;
  // 👇 NEW getter
  bool get isSuperuser => _isSuperuser;

  /// ---------------------------------------------------
  /// LOGIN
  /// ---------------------------------------------------
  Future<bool> login(ApiService api, String username, String password) async {
    try {
      final url = Uri.parse("${api.baseUrl}/users/login");

      debugPrint("LOGIN URL: $url");

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("LOGIN RESPONSE: $data");

        _loggedIn = true;
        _username = data["username"] ?? data["User"];
        _email = data["email"] ?? data["Email"];
        _displayName =
            data["display_name"] ?? data["displayName"] ?? data["DisplayName"];
        _town = data["town"] ?? data["Town"];
        _country = data["country"] ?? data["Country"];
        _gender = data["gender"] ?? data["Gender"];
        _dob = data["dob"] ?? data["DOB"];
        _bio = data["bio"] ?? data["Bio"];

        _shareWithFriends =
            data["share_with_friends"] == true ||
            data["shareWithFriends"] == true ||
            data["ShareWithFriends"] == true;

        _blackList = data["BlackList"] == true || data["blackList"] == true;

        _isSuperuser =
            data["is_superuser"] == true ||
            data["isSuperuser"] == true ||
            data["Superuser"] == true;

        notifyListeners();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool("loggedIn", true);
        await prefs.setString("username", _username!);
        await prefs.setString("email", _email ?? "");
        await prefs.setString("displayName", _displayName ?? "");
        await prefs.setString("town", _town ?? "");
        await prefs.setString("country", _country ?? "");
        await prefs.setString("gender", _gender ?? "");
        await prefs.setString("dob", _dob ?? "");
        await prefs.setBool("shareWithFriends", _shareWithFriends);
        await prefs.setBool("blackList", _blackList);
        await prefs.setString("bio", _bio ?? "");
        // 👇 Persist superuser flag
        await prefs.setBool("isSuperuser", _isSuperuser);

        return true;
      }
    } catch (e) {
      debugPrint("❌ Login error: $e");
    }

    return false;
  }

  /// ---------------------------------------------------
  /// REGISTER
  /// ---------------------------------------------------
  Future<bool> register(
    ApiService api,
    String username,
    String email,
    String password, {
    String? displayName,
    String? town,
    String? country,
    String? gender,
    String? dob,
    String? bio,
    bool shareWithFriends = false,
    bool blackList = false,
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
          "town": town ?? "",
          "country": country ?? "",
          "gender": gender ?? "",
          "dob": dob ?? "",
          "bio": bio ?? "",
          "shareWithFriends": shareWithFriends,
          "BlackList": blackList,
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

  /// ---------------------------------------------------
  /// RESET PASSWORD
  /// ---------------------------------------------------
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
        return false; // no matching user
      } else {
        debugPrint("❌ Reset failed: ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Reset password error: $e");
    }

    return false;
  }

  /// ---------------------------------------------------
  /// AUTO LOGIN
  /// ---------------------------------------------------
  Future<void> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();

    // Guest mode
    if (prefs.getBool("guestMode") ?? false) {
      _guestMode = true;
      notifyListeners();
      return;
    }

    if (prefs.getBool("loggedIn") ?? false) {
      _loggedIn = true;
      _username = prefs.getString("username");
      _email = prefs.getString("email");
      _displayName = prefs.getString("displayName");
      _town = prefs.getString("town");
      _country = prefs.getString("country");
      _gender = prefs.getString("gender");
      _dob = prefs.getString("dob");
      _shareWithFriends = prefs.getBool("shareWithFriends") ?? false;
      _blackList = prefs.getBool("blackList") ?? false;
      _bio = prefs.getString("bio");

      // 👇 Restore superuser value
      _isSuperuser = prefs.getBool("isSuperuser") ?? false;

      notifyListeners();
    }
  }

  /// ---------------------------------------------------
  /// LOGOUT
  /// ---------------------------------------------------
  Future<void> logout() async {
    _loggedIn = false;
    _guestMode = false;
    _username = null;
    _email = null;
    _displayName = null;
    _isSuperuser = false; // reset superuser on logout
    _town = null;
    _country = null;
    _gender = null;
    _dob = null;
    _shareWithFriends = false;
    _blackList = false;
    _bio = null;

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("loggedIn");
    await prefs.remove("username");
    await prefs.remove("email");
    await prefs.remove("displayName");
    await prefs.remove("guestMode");
    await prefs.remove("isSuperuser"); // 👈 remove superuser persistence
    await prefs.remove("town");
    await prefs.remove("country");
    await prefs.remove("gender");
    await prefs.remove("dob");
    await prefs.remove("shareWithFriends");
    await prefs.remove("blackList");
    await prefs.remove("bio");
  }

  /// ---------------------------------------------------
  /// GUEST MODE
  /// ---------------------------------------------------
  Future<void> setGuestMode(bool enabled) async {
    _guestMode = enabled;
    _loggedIn = false;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("guestMode", enabled);
  }

  Future<void> tryAutoGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    _guestMode = prefs.getBool("guestMode") ?? false;
    if (_guestMode) notifyListeners();
  }

  /// ---------------------------------------------------
  /// CONFIRM PASSWORD (reauth gate for sensitive actions)
  /// ---------------------------------------------------
  Future<bool> confirmPassword(ApiService api, String password) async {
    if (_guestMode) return false;

    final u = _username;
    if (u == null || u.isEmpty) return false;

    try {
      final url = Uri.parse("${api.baseUrl}/users/login");

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": u, "password": password}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ Confirm password error: $e");
      return false;
    }
  }

  Future<void> updateLocalProfile({
    String? email,
    String? displayName,
    String? town,
    String? country,
    String? gender,
    String? dob,
    bool? shareWithFriends,
    bool? blackList,
    String? bio,
  }) async {
    if (email != null) _email = email;
    if (displayName != null) _displayName = displayName;
    if (town != null) _town = town;
    if (country != null) _country = country;
    if (gender != null) _gender = gender;
    if (dob != null) _dob = dob;
    if (shareWithFriends != null) _shareWithFriends = shareWithFriends;
    if (blackList != null) _blackList = blackList;
    if (bio != null) _bio = bio;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (email != null) await prefs.setString("email", email);
    if (displayName != null) await prefs.setString("displayName", displayName);
    if (town != null) await prefs.setString("town", town);
    if (country != null) await prefs.setString("country", country);
    if (gender != null) await prefs.setString("gender", gender);
    if (dob != null) await prefs.setString("dob", dob);
    if (shareWithFriends != null) {
      await prefs.setBool("shareWithFriends", shareWithFriends);
    }
    if (blackList != null) {
      await prefs.setBool("blackList", blackList);
    }
    if (bio != null) await prefs.setString("bio", bio);
  }
}
