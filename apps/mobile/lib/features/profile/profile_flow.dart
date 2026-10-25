import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_route.dart';
import '../../theme/app_tokens.dart';
import 'profile_done_screen.dart';
import 'profile_form_screen.dart';
import 'profile_prompt_screen.dart';

/// Opens "Complete your profile": the consent screen (no Skip, PRD 4.2), then
/// the ID scan and selfie, then a confirmation.
///
/// Finishing comes back to the screen that called this and then runs
/// [afterFinish] (the first sign-in goes on to the appointments). The
/// declaration only unlocks booking once it is approved.
void openProfile(BuildContext context, {VoidCallback? afterFinish}) {
  final navigator = Navigator.of(context);
  final base = ModalRoute.of(context);
  final reduced = AppMotion.reduced(context);
  void push(Widget page) =>
      unawaited(navigator.push<void>(appRoute(page, reduced: reduced)));
  void finish() {
    navigator.popUntil((route) => route == base || route.isFirst);
    afterFinish?.call();
  }

  push(
    ProfilePromptScreen(
      onStart: () => push(
        ProfileFormScreen(
          onSent: () => push(ProfileDoneScreen(onContinue: finish)),
        ),
      ),
    ),
  );
}
