import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/auth/auth_models.dart';
import '../features/auth/phone_number.dart';

/// What the phone keeps between launches: the chosen language and the login
/// (tokens), in the platform's encrypted storage. Every call swallows
/// storage errors: the app then just behaves as if nothing was saved.
class LocalStore {
  const LocalStore._();

  static const _storage = FlutterSecureStorage();
  static const _localeKey = 'locale';
  static const _sessionKey = 'session';

  static Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object {
      return null;
    }
  }

  static Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on Object {
      // Not saved; nothing else to do.
    }
  }

  static Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on Object {
      // Nothing saved to remove.
    }
  }

  static Future<Locale?> readLocale() async {
    final code = await _read(_localeKey);
    return code == 'ar' || code == 'fr' ? Locale(code!) : null;
  }

  static Future<void> writeLocale(Locale locale) =>
      _write(_localeKey, locale.languageCode);

  static Future<AuthSession?> readSession() async {
    final raw = await _read(_sessionKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final phone = json['phone'] as String?;
      return AuthSession(
        accessToken: json['access'] as String,
        refreshToken: json['refresh'] as String,
        user: AuthUser(
          id: json['user'] as String,
          verified: json['verified'] as bool,
          phone: phone == null ? null : PhoneNumber.tryParse(phone),
        ),
      );
    } on Object {
      await _delete(_sessionKey);
      return null;
    }
  }

  static Future<void> writeSession(AuthSession session) => _write(
    _sessionKey,
    jsonEncode({
      'access': session.accessToken,
      'refresh': session.refreshToken,
      'user': session.user.id,
      'verified': session.user.verified,
      'phone': session.user.phone?.e164,
    }),
  );

  static Future<void> clearSession() => _delete(_sessionKey);

  /// How many times the app was opened, so the splash can alternate its
  /// logo from one launch to the next. 0 when unknown.
  static Future<int> readLaunchCount() async =>
      int.tryParse(await _read(_launchesKey) ?? '') ?? 0;

  static Future<void> writeLaunchCount(int count) =>
      _write(_launchesKey, '$count');

  static const _launchesKey = 'launches';
}
