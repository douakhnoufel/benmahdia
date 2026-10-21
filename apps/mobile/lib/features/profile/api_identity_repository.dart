import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'identity_models.dart';
import 'identity_repository.dart';

/// [IdentityRepository] over the BenMahdia API (`/v1/me/identity`).
class ApiIdentityRepository implements IdentityRepository {
  ApiIdentityRepository({
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
  Future<IdentityState> status() async =>
      _state(await _send('GET', 'v1/me/identity'));

  @override
  Future<IdentityState> declare(
    IdentityDraft draft,
    Uint8List selfieJpeg,
  ) async => _state(
    await _send(
      'POST',
      'v1/me/identity',
      body: {
        'id_number': draft.idNumber,
        'full_name': draft.fullName,
        'birth_date': draft.birthIso,
        'selfie_jpeg_base64': base64Encode(selfieJpeg),
      },
    ),
  );

  Future<Map<String, dynamic>> _send(
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
    throw _failure(decoded);
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
      throw const IdentityUnavailable();
    } on http.ClientException {
      throw const IdentityUnavailable();
    }
  }

  static IdentityFailure _failure(Object? body) {
    final detail = body is Map ? body['detail'] : null;
    final code = detail is Map ? detail['code'] : null;
    return switch (code) {
      'id_already_linked' => const IdAlreadyLinked(),
      'too_many_submissions' => const TooManySubmissions(),
      'already_declared' || 'already_approved' => const AlreadyDecided(),
      'invalid_id_number' => const InvalidDetails(IdField.idNumber),
      'invalid_name' => const InvalidDetails(IdField.fullName),
      'invalid_birth_date' => const InvalidDetails(IdField.birthDate),
      'invalid_selfie' => const InvalidDetails(IdField.selfie),
      _ => const IdentityUnavailable(),
    };
  }

  static IdentityState _state(Map<String, dynamic> json) => IdentityState(
    status: switch (json['status']) {
      'declared' => IdStatus.declared,
      'approved' => IdStatus.approved,
      'rejected' => IdStatus.rejected,
      _ => IdStatus.none,
    },
    rejectReason: json['reject_reason'] as String?,
    submissionsLeft: json['submissions_left'] as int? ?? 0,
  );
}
