import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import 'api_craving_repository.dart';
import 'craving_models.dart';
import 'fake_craving_repository.dart';

/// What the difficult-moment screen needs: start a moment, mark it passed,
/// and the recent ones.
abstract interface class CravingRepository {
  /// Current time. Injected so tests control "now".
  DateTime now();

  /// Opens a moment with its starting intensity (1-10) and the HALT states
  /// the patient named.
  Future<CravingLog> start({required int intensity, required Set<Halt> halt});

  /// Closes [log] with the intensity (1-10) once the craving has passed.
  Future<CravingLog> markPassed(CravingLog log, int intensity);

  /// The last 30 days, newest first.
  Future<List<CravingLog>> recent();
}

/// Where the patient's if-then plan lives: on the phone only.
abstract interface class IfThenPlanStore {
  Future<IfThenPlan?> read();

  /// Saves [plan]; null removes it.
  Future<void> write(IfThenPlan? plan);
}

/// The phone's encrypted storage. Errors are swallowed: the plan then just
/// is not remembered.
class SecureIfThenPlanStore implements IfThenPlanStore {
  const SecureIfThenPlanStore();

  static const _storage = FlutterSecureStorage();
  static const _key = 'if_then_plan';

  @override
  Future<IfThenPlan?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return IfThenPlan(
        ifText: json['if'] as String,
        thenText: json['then'] as String,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(IfThenPlan? plan) async {
    try {
      if (plan == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(
          key: _key,
          value: jsonEncode({'if': plan.ifText, 'then': plan.thenText}),
        );
      }
    } on Object {
      // Not saved; nothing else to do.
    }
  }
}

/// The craving API when `API_BASE_URL` is set, otherwise sample data.
final cravingRepositoryProvider = Provider<CravingRepository>((ref) {
  if (apiBaseUrl.isEmpty) return FakeCravingRepository();
  final auth = ref.read(authRepositoryProvider);
  return ApiCravingRepository(
    baseUrl: Uri.parse(apiBaseUrl),
    token: () => ref.read(sessionProvider)?.accessToken,
    refresh: () async {
      final session = ref.read(sessionProvider);
      if (session == null) return false;
      try {
        final AuthSession fresh = await auth.refresh(session);
        ref.read(sessionProvider.notifier).set(fresh);
        return true;
      } on AuthFailure {
        return false;
      }
    },
  );
});

final ifThenPlanStoreProvider = Provider<IfThenPlanStore>(
  (ref) => const SecureIfThenPlanStore(),
);
