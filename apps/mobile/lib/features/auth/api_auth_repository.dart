import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_models.dart';
import 'auth_repository.dart';
import 'phone_number.dart';

/// [AuthRepository] over the BenMahdia API (backend/README.md). Maps the
/// API's error codes to [AuthFailure]s.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({required Uri baseUrl, http.Client? client})
    : _base = baseUrl,
      _client = client ?? http.Client();

  final Uri _base;
  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  static String _purpose(OtpPurpose p) => switch (p) {
    OtpPurpose.signUp => 'sign_up',
    OtpPurpose.resetPassword => 'reset_password',
    OtpPurpose.attachPhone => 'attach_phone',
  };

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async {
    final request = http.Request(method, _base.resolve(path))
      ..headers['content-type'] = 'application/json'
      ..headers['accept'] = 'application/json';
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
    } on TimeoutException {
      throw const NetworkFailure();
    } on http.ClientException {
      throw const NetworkFailure();
    }
    final decoded = response.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded is Map<String, dynamic> ? decoded : const {};
    }
    throw _failure(decoded);
  }

  static AuthFailure _failure(Object? body) {
    final detail = body is Map ? body['detail'] : null;
    final code = detail is Map ? detail['code'] : null;
    final retry = Duration(
      seconds: detail is Map && detail['retry_after'] is int
          ? detail['retry_after'] as int
          : 60,
    );
    return switch (code) {
      'phone_taken' => const PhoneTaken(),
      'code_wrong' => const WrongCode(),
      'code_expired' => const CodeExpired(),
      'too_many_attempts' => const TooManyAttempts(),
      'wrong_credentials' => const WrongCredentials(),
      'account_locked' => AccountLocked(retry),
      'rate_limited' => RateLimited(retry),
      'social_unavailable' => const SocialUnavailable(),
      // Anything unexpected reads as "could not connect, try again".
      _ => const NetworkFailure(),
    };
  }

  static AuthSession _session(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    final phone = user['phone'] as String?;
    return AuthSession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      user: AuthUser(
        id: user['id'] as String,
        verified: user['status'] == 'verified',
        phone: phone == null ? null : PhoneNumber.tryParse(phone),
      ),
    );
  }

  @override
  Future<OtpTicket> requestCode(PhoneNumber phone, OtpPurpose purpose) async {
    final json = await _send(
      'POST',
      'v1/auth/otp/request',
      body: {'phone': phone.e164, 'purpose': _purpose(purpose)},
    );
    return OtpTicket(
      resendAfter: Duration(seconds: json['resend_after'] as int? ?? 60),
    );
  }

  @override
  Future<String> verifyCode(
    PhoneNumber phone,
    OtpPurpose purpose,
    String code,
  ) async {
    final json = await _send(
      'POST',
      'v1/auth/otp/verify',
      body: {'phone': phone.e164, 'purpose': _purpose(purpose), 'code': code},
    );
    return json['phone_proof'] as String;
  }

  @override
  Future<AuthSession> register({
    required String phoneProof,
    required String password,
    required String language,
  }) async => _session(
    await _send(
      'POST',
      'v1/auth/register',
      body: {
        'phone_proof': phoneProof,
        'password': password,
        'language': language,
      },
    ),
  );

  @override
  Future<AuthSession> logIn(PhoneNumber phone, String password) async =>
      _session(
        await _send(
          'POST',
          'v1/auth/login',
          body: {'phone': phone.e164, 'password': password},
        ),
      );

  @override
  Future<AuthSession> resetPassword({
    required String phoneProof,
    required String password,
  }) async => _session(
    await _send(
      'POST',
      'v1/auth/password/reset',
      body: {'phone_proof': phoneProof, 'password': password},
    ),
  );

  // TODO(social): get the ID token with google_sign_in / sign_in_with_apple
  // once the client IDs exist, then POST it to v1/auth/google or
  // v1/auth/apple. The backend side is ready.
  @override
  Future<AuthSession> signInWithGoogle({required String language}) async =>
      throw const SocialUnavailable();

  @override
  Future<AuthSession> signInWithApple({required String language}) async =>
      throw const SocialUnavailable();

  @override
  Future<AuthSession> refresh(AuthSession session) async {
    final json = await _send(
      'POST',
      'v1/auth/refresh',
      body: {'refresh_token': session.refreshToken},
    );
    return _session(json);
  }

  @override
  Future<AuthSession> attachPhone(
    AuthSession session,
    String phoneProof,
  ) async {
    final json = await _send(
      'PUT',
      'v1/me/phone',
      body: {'phone_proof': phoneProof},
      token: session.accessToken,
    );
    final phone = PhoneNumber.tryParse(json['phone'] as String? ?? '');
    return phone == null
        ? session
        : session.withUser(session.user.withPhone(phone));
  }
}
