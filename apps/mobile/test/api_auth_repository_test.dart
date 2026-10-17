import 'dart:convert';

import 'package:benmahdia_mobile/features/auth/api_auth_repository.dart';
import 'package:benmahdia_mobile/features/auth/auth_models.dart';
import 'package:benmahdia_mobile/features/auth/phone_number.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _phone = PhoneNumber.tryParse('0661234567')!;

Map<String, Object?> _sessionJson({String status = 'pending_verification'}) => {
  'access_token': 'a',
  'refresh_token': 'r',
  'token_type': 'bearer',
  'expires_in': 900,
  'user': {
    'id': 'u-1',
    'role': 'patient',
    'status': status,
    'phone': '+213661234567',
    'language': 'ar',
    'has_password': true,
    'providers': <String>[],
  },
};

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late List<http.Request> sent;

  ApiAuthRepository repo(http.Response Function(http.Request) answer) {
    sent = [];
    return ApiAuthRepository(
      baseUrl: Uri.parse('http://api.test/'),
      client: MockClient((request) async {
        sent.add(request);
        return answer(request);
      }),
    );
  }

  test('requests a code with the server spelling of the purpose', () async {
    final ticket = await repo(
      (_) => _json(202, {'resend_after': 60, 'expires_in': 300}),
    ).requestCode(_phone, OtpPurpose.resetPassword);
    expect(ticket.resendAfter, const Duration(seconds: 60));
    expect(sent.single.url.toString(), 'http://api.test/v1/auth/otp/request');
    expect(jsonDecode(sent.single.body), {
      'phone': '+213661234567',
      'purpose': 'reset_password',
    });
  });

  test('reads a session', () async {
    final session = await repo(
      (_) => _json(200, _sessionJson(status: 'verified')),
    ).logIn(_phone, 'sobre2026');
    expect(session.accessToken, 'a');
    expect(session.user.verified, isTrue);
    expect(session.user.phone, _phone);
  });

  test('maps error codes', () async {
    Future<Object?> fail(int status, Map<String, Object?> detail) async {
      try {
        await repo((_) => _json(status, {'detail': detail})).logIn(_phone, 'x');
      } on AuthFailure catch (f) {
        return f;
      }
      return null;
    }

    expect(
      await fail(401, {'code': 'wrong_credentials'}),
      isA<WrongCredentials>(),
    );
    expect(await fail(409, {'code': 'phone_taken'}), isA<PhoneTaken>());
    expect(await fail(400, {'code': 'code_wrong'}), isA<WrongCode>());
    expect(await fail(410, {'code': 'code_expired'}), isA<CodeExpired>());
    expect(
      await fail(429, {'code': 'too_many_attempts'}),
      isA<TooManyAttempts>(),
    );
    final locked = await fail(423, {
      'code': 'account_locked',
      'retry_after': 900,
    });
    expect((locked! as AccountLocked).retryAfter, const Duration(minutes: 15));
    final limited = await fail(429, {
      'code': 'rate_limited',
      'retry_after': 40,
    });
    expect((limited! as RateLimited).retryAfter, const Duration(seconds: 40));
    expect(await fail(500, {'code': 'boom'}), isA<NetworkFailure>());
  });

  test('a dropped connection is a network failure', () async {
    final r = repo((_) => throw http.ClientException('offline'));
    expect(
      () => r.requestCode(_phone, OtpPurpose.signUp),
      throwsA(isA<NetworkFailure>()),
    );
  });

  test('adds the phone with the access token', () async {
    final session = AuthSession(
      accessToken: 'tok',
      refreshToken: 'r',
      user: const AuthUser(id: 'u-1', verified: false),
    );
    final updated = await repo(
      (_) => _json(200, {'phone': '+213771234567'}),
    ).attachPhone(session, 'proof');
    expect(sent.single.method, 'PUT');
    expect(sent.single.headers['authorization'], 'Bearer tok');
    expect(updated.user.phone?.e164, '+213771234567');
  });

  test('Google and Apple wait for their SDKs', () {
    final r = repo((_) => _json(200, {}));
    expect(
      () => r.signInWithGoogle(language: 'ar'),
      throwsA(isA<SocialUnavailable>()),
    );
  });
}
