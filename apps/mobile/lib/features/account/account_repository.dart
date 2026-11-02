import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import 'account_models.dart';
import 'api_account_repository.dart';
import 'fake_account_repository.dart';

/// The signed-in account (Profile & Settings). The server is the authority.
/// Methods throw [AccountFailure].
abstract interface class AccountRepository {
  Future<Me> me();

  /// Sets the contact email, or clears it with null / empty.
  Future<Me> setEmail(String? email);

  /// Permanently closes the account (PRD 12.5). A password account must pass
  /// its password.
  Future<void> deleteAccount({String? password});
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  if (apiBaseUrl.isEmpty) return FakeAccountRepository();
  final auth = ref.read(authRepositoryProvider);
  return ApiAccountRepository(
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

/// The account, re-read whenever Profile & Settings opens. Invalidate it after
/// a change.
final meProvider = FutureProvider.autoDispose<Me>(
  (ref) => ref.watch(accountRepositoryProvider).me(),
);
