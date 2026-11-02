import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../theme/app_tokens.dart';
import '../auth/auth_repository.dart';
import '../home/home_shell.dart';
import '../welcome/welcome_entry.dart';

/// Signs out: revokes the login on the server (best effort, so it works
/// offline), clears the saved credentials, and returns to the welcome screen.
Future<void> signOut(BuildContext context, WidgetRef ref) async {
  final session = ref.read(sessionProvider);
  if (session != null) {
    unawaited(
      ref
          .read(authRepositoryProvider)
          .logOut(session)
          .catchError((Object _) {}),
    );
  }
  final navigator = Navigator.of(context);
  final reduced = AppMotion.reduced(context);
  await ref.read(sessionProvider.notifier).clear();
  unawaited(
    navigator.pushAndRemoveUntil<void>(
      appRoute(
        Builder(
          builder: (entryContext) => welcomeEntry(
            entryContext,
            onOpenHome: () => openHome(entryContext),
          ),
        ),
        reduced: reduced,
      ),
      (route) => false,
    ),
  );
}
