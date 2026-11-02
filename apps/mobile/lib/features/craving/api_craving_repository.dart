import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'craving_models.dart';
import 'craving_repository.dart';

/// [CravingRepository] over the BenMahdia API (backend/app/routers/cravings.py).
class ApiCravingRepository implements CravingRepository {
  ApiCravingRepository({
    required Uri baseUrl,
    required String? Function() token,
    required Future<bool> Function() refresh,
    http.Client? client,
    DateTime Function()? clock,
  }) : _base = baseUrl,
       _token = token,
       _refresh = refresh,
       _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final Uri _base;
  final String? Function() _token;
  final Future<bool> Function() _refresh;
  final http.Client _client;
  final DateTime Function() _clock;
  Future<bool>? _refreshing;

  static const _timeout = Duration(seconds: 15);

  @override
  DateTime now() => _clock();

  Future<Object?> _send(String method, String path, {Object? body}) async {
    var response = await _once(method, path, body);
    if (response.statusCode == 401 && await _refreshOnce()) {
      response = await _once(method, path, body);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const CravingUnavailable();
    }
    try {
      final text = utf8.decode(response.bodyBytes);
      return text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      throw const CravingUnavailable();
    }
  }

  /// A refresh token is single-use, so several expired requests must await
  /// the same rotation instead of each spending the old token.
  Future<bool> _refreshOnce() {
    final active = _refreshing;
    if (active != null) return active;
    final refresh = _refresh();
    return _refreshing = refresh.whenComplete(() => _refreshing = null);
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
      throw const CravingUnavailable();
    } on http.ClientException {
      throw const CravingUnavailable();
    }
  }

  CravingLog _log(Object? json) {
    try {
      final m = json! as Map<String, dynamic>;
      return CravingLog(
        id: m['id'] as String,
        before: m['intensity_before'] as int,
        after: m['intensity_after'] as int?,
        halt: {
          for (final k in (m['halt'] as List<dynamic>))
            Halt.values.byName(k as String),
        },
        startedAt: DateTime.parse(m['created_at'] as String),
        passedAt: m['passed_at'] == null
            ? null
            : DateTime.parse(m['passed_at'] as String),
      );
    } on Object {
      throw const CravingUnavailable();
    }
  }

  @override
  Future<CravingLog> start({
    required int intensity,
    required Set<Halt> halt,
  }) async => _log(
    await _send(
      'POST',
      '/v1/me/cravings',
      body: {
        'intensity_before': intensity,
        'halt': [for (final h in halt) h.name],
      },
    ),
  );

  @override
  Future<CravingLog> markPassed(CravingLog log, int intensity) async => _log(
    await _send(
      'POST',
      '/v1/me/cravings/${log.id}/passed',
      body: {'intensity_after': intensity},
    ),
  );

  @override
  Future<List<CravingLog>> recent() async {
    final json = await _send('GET', '/v1/me/cravings');
    if (json is! List<dynamic>) throw const CravingUnavailable();
    return [for (final item in json) _log(item)];
  }
}
