import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import 'api_identity_repository.dart';
import 'fake_identity_repository.dart';
import 'identity_models.dart';

/// The patient's ID declaration. The server is the authority: it stores only
/// a hash of the number, the name and birth date encrypted, and the selfie
/// encrypted for the doctor (PRD 4.2). Methods throw [IdentityFailure].
abstract interface class IdentityRepository {
  Future<IdentityState> status();

  /// Sends the confirmed fields and the live selfie (JPEG).
  Future<IdentityState> declare(IdentityDraft draft, Uint8List selfieJpeg);
}

final identityRepositoryProvider = Provider<IdentityRepository>((ref) {
  if (apiBaseUrl.isEmpty) return FakeIdentityRepository(autoApprove: true);
  final auth = ref.read(authRepositoryProvider);
  return ApiIdentityRepository(
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

/// The current status, read again each time a screen needs it. Invalidate it
/// after sending, or to check whether the clinic has decided.
final identityStateProvider = FutureProvider.autoDispose<IdentityState>(
  (ref) => ref.watch(identityRepositoryProvider).status(),
);
