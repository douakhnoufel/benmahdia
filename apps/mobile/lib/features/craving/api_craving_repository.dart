import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../recovery/recovery_models.dart';
import 'craving_models.dart';
import 'craving_repository.dart';

/// [CravingRepository] over the BenMahdia API
/// (backend/app/routers/cravings.py): `/v1/me/cravings`.
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
  static const _path = 'v1/me/cravings';

  @override
  DateTime now() => _clock();

  // --- http -----------------------------------------------------------------

  Future<Object?> _send(String method, String path, {Object? body}) async {
    var response = await _once(method, path, body);
    if (response.statusCode == 401 && await _refreshOnce()) {
      response = await _once(method, path, body);
    }
    final code = _code(response);
    if (response.statusCode == 403 && code == 'recovery_locked') {
      throw const RecoveryLocked();
    }
    if (response.statusCode == 409 && code == 'craving_already_passed') {
      throw const CravingAlreadyPassed();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const RecoveryUnavailable();
    }
    try {
      final text = utf8.decode(response.bodyBytes);
      return text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      throw const RecoveryUnavailable();
    }
  }

  /// The API's error code, e.g. "recovery_locked"; null when there is none.
  static String? _code(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final detail = body is Map ? body['detail'] : null;
      final code = detail is Map ? detail['code'] : null;
      return code is String ? code : null;
    } on FormatException {
      return null;
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
      throw const RecoveryUnavailable();
    } on http.ClientException {
      throw const RecoveryUnavailable();
    }
  }

  // --- parsing --------------------------------------------------------------

  /// A malformed answer is "unavailable", never a crash.
  static CravingLog _logFrom(Object? json) {
    try {
      final m = json! as Map<String, dynamic>;
      return CravingLog(
        id: m['id'] as String,
        startedAt: DateTime.parse(m['started_at'] as String).toLocal(),
        intensityBefore: m['intensity_before'] as int,
        triggers: [
          for (final t in (m['triggers'] as List? ?? const [])) ?_triggerOf(t),
        ],
        passedAt: switch (m['passed_at']) {
          final String at => DateTime.parse(at).toLocal(),
          _ => null,
        },
        intensityAfter: m['intensity_after'] as int?,
      );
    } on Object {
      throw const RecoveryUnavailable();
    }
  }

  /// A trigger the app does not know yet is dropped, not a failure.
  static CravingTrigger? _triggerOf(Object? name) {
    for (final t in CravingTrigger.values) {
      if (t.name == name) return t;
    }
    return null;
  }

  // --- calls ----------------------------------------------------------------

  @override
  Future<CravingLog> start({
    required int intensity,
    List<CravingTrigger> triggers = const [],
  }) async => _logFrom(
    await _send(
      'POST',
      _path,
      body: {
        'intensity': intensity,
        'triggers': [
          for (final t in {...triggers}) t.name,
        ],
      },
    ),
  );

  @override
  Future<CravingLog> markPassed(
    CravingLog log, {
    required int intensity,
  }) async => _logFrom(
    await _send('PATCH', '$_path/${log.id}', body: {'intensity': intensity}),
  );

  @override
  Future<List<CravingLog>> recent({int days = 30}) async {
    final json = await _send('GET', '$_path?days=$days');
    if (json is! List) throw const RecoveryUnavailable();
    return [for (final row in json) _logFrom(row)];
  }
}
