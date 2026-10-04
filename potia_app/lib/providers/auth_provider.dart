import 'package:flutter/foundation.dart';

import '../models/auth_session.dart';
import '../models/user_model.dart';
import '../services/api_exception.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthProvider({required ApiService api, required StorageService storage})
      : _api = api,
        _storage = storage {
    _api.onUnauthorized = () => logout();
  }

  final ApiService _api;
  final StorageService _storage;

  AuthStatus _status = AuthStatus.unknown;
  UserModel? _user;
  bool _isLoading = false;
  String? _errorMessage;

  AuthStatus get status => _status;
  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  Future<bool> tryAutoLogin() async {
    final token = _storage.token;
    if (token == null) {
      _setStatus(AuthStatus.unauthenticated);
      return false;
    }

    _api.token = token;
    try {
      _user = await _api.me();
      await _storage.saveSession(token: token, user: _user!);
      _setStatus(AuthStatus.authenticated);
      return true;
    } on ApiException catch (error) {
      final cached = _storage.user;
      if (error.isNetworkError && cached != null) {
        _user = cached;
        _setStatus(AuthStatus.authenticated);
        return true;
      }
      await _clearSession();
      _setStatus(AuthStatus.unauthenticated);
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) =>
      _authenticate(() => _api.login(email: email.trim(), password: password));

  Future<bool> register({required String name, required String email, required String password}) =>
      _authenticate(() => _api.register(name: name.trim(), email: email.trim(), password: password));

  Future<void> logout() async {
    await _clearSession();
    _setStatus(AuthStatus.unauthenticated);
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> _authenticate(Future<AuthSession> Function() action) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final session = await action();
      _api.token = session.accessToken;
      _user = session.user;
      await _storage.saveSession(token: session.accessToken, user: session.user);
      _status = AuthStatus.authenticated;
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (error) {
      _errorMessage = 'Erro inesperado: $error';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _clearSession() async {
    _api.token = null;
    _user = null;
    await _storage.clear();
  }

  void _setStatus(AuthStatus status) {
    _status = status;
    notifyListeners();
  }
}
