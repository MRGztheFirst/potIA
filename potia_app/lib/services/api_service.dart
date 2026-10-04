import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../models/auth_session.dart';
import '../models/user_model.dart';
import 'api_exception.dart';
import 'sse_parser.dart';

class ApiService {
  ApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String baseUrl;
  String? _token;

  http.Client? _activeStreamClient;

  void Function()? onUnauthorized;

  set token(String? value) => _token = value;

  Future<AuthSession> login({required String email, required String password}) async {
    final json = await _send('POST', '/api/v1/auth/login', body: {'email': email, 'password': password});
    return AuthSession.fromJson(json);
  }

  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final json = await _send(
      'POST',
      '/api/v1/auth/register',
      body: {'name': name, 'email': email, 'password': password},
    );
    return AuthSession.fromJson(json);
  }

  Future<UserModel> me() async => UserModel.fromJson(await _send('GET', '/api/v1/auth/me', authenticated: true));

  Stream<String> streamChat(List<Map<String, dynamic>> messages) async* {
    final client = http.Client();
    _activeStreamClient = client;
    try {
      final request = http.Request('POST', _uri('/api/v1/chat'))
        ..headers.addAll(_headers(authenticated: true, accept: 'text/event-stream'))
        ..body = jsonEncode({'messages': messages, 'stream': true});

      final http.StreamedResponse response;
      try {
        response = await client.send(request).timeout(AppConfig.requestTimeout);
      } on TimeoutException {
        throw const ApiException('O servidor demorou para responder. Tente novamente.');
      } on http.ClientException {
        throw _connectionError();
      }

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw _errorFromResponse(response.statusCode, body, authenticated: true);
      }

      final events = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(AppConfig.streamIdleTimeout, onTimeout: (sink) {
            sink.addError(const ApiException('A resposta ficou parada por muito tempo. Tente novamente.'));
            sink.close();
          })
          .transform(const SseParser());

      await for (final event in events) {
        final payload = _decodeJson(event.data);
        switch (payload['type']) {
          case 'token':
            final content = payload['content'];
            if (content is String && content.isNotEmpty) yield content;
          case 'done':
            return;
          case 'error':
            throw ApiException(payload['detail'] as String? ?? 'Erro ao gerar a resposta.');
        }
      }
    } on http.ClientException {
      throw const ApiException('A conexão com a PotIA caiu no meio da resposta.');
    } finally {
      client.close();
      if (identical(_activeStreamClient, client)) _activeStreamClient = null;
    }
  }

  void cancelChatStream() {
    _activeStreamClient?.close();
    _activeStreamClient = null;
  }

  void dispose() {
    cancelChatStream();
    _client.close();
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers({bool authenticated = false, String accept = 'application/json'}) => {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': accept,
        if (authenticated && _token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    final request = http.Request(method, _uri(path))..headers.addAll(_headers(authenticated: authenticated));
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await _client.send(request).then(http.Response.fromStream).timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw const ApiException('O servidor demorou para responder. Tente novamente.');
    } on http.ClientException {
      throw _connectionError();
    } catch (error) {
      throw ApiException('Falha de comunicação com o servidor: $error');
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode >= 200 && response.statusCode < 300) return _decodeJson(text);
    throw _errorFromResponse(response.statusCode, text, authenticated: authenticated);
  }

  ApiException _errorFromResponse(int status, String body, {required bool authenticated}) {
    if (status == 401 && authenticated) onUnauthorized?.call();
    final detail = _decodeJson(body)['detail'];
    final message = detail is String && detail.isNotEmpty ? detail : _defaultMessage(status);
    return ApiException(message, statusCode: status);
  }

  String _defaultMessage(int status) => switch (status) {
        401 => 'Sessão expirada. Faça login novamente.',
        404 => 'Recurso não encontrado na API.',
        429 => 'Muitas requisições. Aguarde um pouquinho.',
        >= 500 => 'O servidor está com problemas. Tente mais tarde.',
        _ => 'Erro inesperado ($status).',
      };

  ApiException _connectionError() =>
      ApiException('Não foi possível conectar à PotIA em $baseUrl. Verifique se a API está rodando.');

  Map<String, dynamic> _decodeJson(String text) {
    if (text.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }
}
