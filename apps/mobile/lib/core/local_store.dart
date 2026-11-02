import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/auth/auth_models.dart';
import '../features/craving/craving_models.dart';
import '../features/auth/phone_number.dart';

/// What the phone keeps between launches: the chosen language and the login
/// (tokens), in the platform's encrypted storage. Every call swallows
/// storage errors: the app then just behaves as if nothing was saved.
class LocalStore {
  const LocalStore._();

  static const _storage = FlutterSecureStorage();
  static const _localeKey = 'locale';
  static const _sessionKey = 'session';
  static const _ifThenKey = 'if_then_plan';

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

  /// The patient's own plan, "When ___, I will ___" (habit-tracking design,
  /// step 1). It stays on the phone: "Only you".
  static Future<IfThenPlan?> readIfThenPlan() async {
    final raw = await _read(_ifThenKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return IfThenPlan(
        when: json['when'] as String,
        then: json['then'] as String,
      );
    } on Object {
      // Unreadable: drop it rather than keep failing on it.
      await _delete(_ifThenKey);
      return null;
    }
  }

  static Future<void> writeIfThenPlan(IfThenPlan plan) =>
      _write(_ifThenKey, jsonEncode({'when': plan.when, 'then': plan.then}));
}
