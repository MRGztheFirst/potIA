import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';

class StorageService {
  StorageService._(this._prefs);

  static const _tokenKey = 'potia.token';
  static const _userKey = 'potia.user';

  final SharedPreferences _prefs;

  static Future<StorageService> create() async => StorageService._(await SharedPreferences.getInstance());

  String? get token => _prefs.getString(_tokenKey);

  UserModel? get user {
    final raw = _prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession({required String token, required UserModel user}) async {
    await _prefs.setString(_tokenKey, token);
    await _prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  Future<void> clear() async {
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_userKey);
  }
}
