import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import 'api_craving_repository.dart';
import 'craving_models.dart';
import 'fake_craving_repository.dart';

/// What the difficult-moment screen needs (habit-tracking design, step 1):
/// log a craving, say it has passed, and read the recent ones. Every call
/// throws `RecoveryLocked` until the first confirmed appointment, like the
/// rest of recovery.
abstract interface class CravingRepository {
  /// Current time. Injected so tests control "now".
  DateTime now();

  /// Logs a craving that is starting: [intensity] 1-10 and the HALT
  /// [triggers] behind it, if the patient named any.
  Future<CravingLog> start({
    required int intensity,
    List<CravingTrigger> triggers,
  });

  /// The craving has passed: records how strong it is now. Once only;
  /// a second call throws [CravingAlreadyPassed].
  Future<CravingLog> markPassed(CravingLog log, {required int intensity});

  /// The patient's own difficult moments over the last [days], newest first.
  Future<List<CravingLog>> recent({int days});
}

/// The cravings API when `API_BASE_URL` is set, otherwise sample data.
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
