import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'account_models.dart';
import 'account_repository.dart';

/// [AccountRepository] over the BenMahdia API (`/v1/me`).
class ApiAccountRepository implements AccountRepository {
  ApiAccountRepository({
    required Uri baseUrl,
    required String? Function() token,
    required Future<bool> Function() refresh,
    http.Client? client,
  }) : _base = baseUrl,
       _token = token,
       _refresh = refresh,
       _client = client ?? http.Client();

  final Uri _base;
  final String? Function() _token;
  final Future<bool> Function() _refresh;
  final http.Client _client;

  static const _timeout = Duration(seconds: 30);

  @override
  Future<Me> me() async => Me.fromJson(await _sendJson('GET', 'v1/me'));

  @override
  Future<Me> setEmail(String? email) async => Me.fromJson(
    await _sendJson('PUT', 'v1/me/email', body: {'email': email}),
  );

  @override
  Future<void> deleteAccount({String? password}) async {
    var response = await _once('DELETE', 'v1/me', {'password': password});
    if (response.statusCode == 401 &&
        _errorCode(response) != 'wrong_credentials' &&
        await _refresh()) {
      response = await _once('DELETE', 'v1/me', {'password': password});
    }
    if (response.statusCode == 204) return;
    if (response.statusCode == 401 &&
        _errorCode(response) == 'wrong_credentials') {
      throw const WrongPassword();
    }
    throw const AccountUnavailable();
  }

  static String? _errorCode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final detail = decoded is Map ? decoded['detail'] : null;
      final code = detail is Map ? detail['code'] : null;
      return code is String ? code : null;
    } on FormatException {
      return null;
    }
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    Object? body,
  }) async {
    var response = await _once(method, path, body);
    if (response.statusCode == 401 && await _refresh()) {
      response = await _once(method, path, body);
    }
    final text = utf8.decode(response.bodyBytes);
    final decoded = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded is Map<String, dynamic> ? decoded : const {};
    }
    final detail = decoded is Map ? decoded['detail'] : null;
    final code = detail is Map ? detail['code'] : null;
    throw code == 'invalid_email'
        ? const InvalidEmail()
        : const AccountUnavailable();
  }

  Future<http.Response> _once(String method, String path, Object? body) async {
    final request = http.Request(method, _base.resolve(path))
      ..headers['content-type'] = 'application/json'
      ..headers['accept'] = 'application/json';
    final token = _token();
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    try {
      return await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
    } on TimeoutException {
      throw const AccountUnavailable();
    } on http.ClientException {
      throw const AccountUnavailable();
    }
  }
}
