import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locale_provider.dart';
import 'auth_models.dart';
import 'auth_repository.dart';
import 'auth_widgets.dart';

/// Signs in with Google or Apple and remembers the session. Returns null
/// when the patient closed the sheet; throws other [AuthFailure]s.
Future<AuthSession?> signInWith(WidgetRef ref, SocialProvider provider) async {
  final repo = ref.read(authRepositoryProvider);
  final language = ref.read(localeProvider).languageCode;
  try {
    final session = switch (provider) {
      SocialProvider.google => await repo.signInWithGoogle(language: language),
      SocialProvider.apple => await repo.signInWithApple(language: language),
    };
    ref.read(sessionProvider.notifier).set(session);
    return session;
  } on SignInCancelled {
    return null;
  }
}
