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
  }) : _base = baseUrl,
       _token = token,
       _refresh = refresh,
       _client = client ?? http.Client();

  final Uri _base;
  final String? Function() _token;
  final Future<bool> Function() _refresh;
  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  Future<Object?> _send(String method, String path, [Object? body]) async {
    var response = await _once(method, path, body);
    if (response.statusCode == 401 && await _refresh()) {
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

  /// A malformed answer is "unavailable", never a crash.
  static CravingLog _from(Object? json) {
    try {
      final m = json! as Map<String, dynamic>;
      return CravingLog(
        id: m['id'] as String,
        startedAt: DateTime.parse(m['started_at'] as String).toLocal(),
        before: m['intensity_before'] as int,
        triggers: [
          for (final t in m['triggers'] as List<dynamic>)
            HaltTrigger.values.byName(t as String),
        ],
        passedAt: switch (m['passed_at']) {
          final String s => DateTime.parse(s).toLocal(),
          _ => null,
        },
        after: m['intensity_after'] as int?,
      );
    } on Object {
      throw const CravingUnavailable();
    }
  }

  @override
  Future<CravingLog> start(int intensity, List<HaltTrigger> triggers) async =>
      _from(
        await _send('POST', '/v1/me/cravings', {
          'intensity': intensity,
          'triggers': [for (final t in triggers) t.name],
        }),
      );

  @override
  Future<CravingLog> passed(String id, int intensity) async => _from(
    await _send('PATCH', '/v1/me/cravings/$id', {'intensity': intensity}),
  );

  @override
  Future<List<CravingLog>> recent({int days = 30}) async {
    final json = await _send('GET', '/v1/me/cravings?days=$days');
    if (json is! List<dynamic>) throw const CravingUnavailable();
    return [for (final j in json) _from(j)];
  }
}
