import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  static const String _apiFromEnvironment = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_apiFromEnvironment.isNotEmpty) return _apiFromEnvironment;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }

  static const Duration requestTimeout = Duration(seconds: 20);

  static const Duration streamIdleTimeout = Duration(seconds: 120);
}
