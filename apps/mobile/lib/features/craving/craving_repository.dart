import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import 'api_craving_repository.dart';
import 'craving_models.dart';
import 'fake_craving_repository.dart';

/// Difficult-moment logs (habit-tracking design, step 1). The doctor of the
/// clinic sees them, so the screen carries the "Your doctor sees this" label.
abstract interface class CravingRepository {
  /// A craving starts at [intensity] (1-10) with the HALT [triggers].
  Future<CravingLog> start(int intensity, List<HaltTrigger> triggers);

  /// The craving passed; records [intensity] (1-10) now. Once only.
  Future<CravingLog> passed(String id, int intensity);

  /// The patient's moments over the last [days], newest first.
  Future<List<CravingLog>> recent({int days = 30});
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
