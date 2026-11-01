import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/local_store.dart';
import 'core/locale_provider.dart';
import 'features/auth/auth_models.dart';
import 'features/auth/auth_repository.dart';
import 'features/start/app_start.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final locale = await LocalStore.readLocale();
  final saved = await LocalStore.readSession();
  final container = ProviderContainer(
    overrides: [
      if (locale != null)
        localeProvider.overrideWith(() => LocaleNotifier(locale)),
    ],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: BenMahdiaApp(
        home: AppStart(ready: _restoreSession(container, saved)),
      ),
    ),
  );
}

/// Signs the patient back in from the saved login: the refresh token is
/// swapped for a new pair. A login the server no longer accepts is
/// forgotten; with no network the patient simply signs in again.
Future<void> _restoreSession(
  ProviderContainer container,
  AuthSession? saved,
) async {
  if (saved == null) return;
  try {
    final fresh = await container
        .read(authRepositoryProvider)
        .refresh(saved)
        .timeout(const Duration(seconds: 8));
    container.read(sessionProvider.notifier).set(fresh);
  } on AuthFailure {
    await container.read(sessionProvider.notifier).clear();
  } on Object {
    // Offline or slow server: keep the saved login for next time.
  }
}

class BenMahdiaApp extends ConsumerWidget {
  const BenMahdiaApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(locale),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );
  }
}
