import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../auth/auth_flow.dart';
import '../intro/intro_screen.dart';
import '../home/home_shell.dart';
import '../profile/profile_flow.dart';
import '../splash/splash_screen.dart';
import '../welcome/welcome_screen.dart';

enum _Stage { splash, intro, welcome }

/// Cold start: splash → intro slides → welcome, cross-fading between them.
class AppStart extends StatefulWidget {
  const AppStart({super.key, required this.ready});

  /// Startup work the splash waits for.
  final Future<void> ready;

  @override
  State<AppStart> createState() => _AppStartState();
}

class _AppStartState extends State<AppStart> {
  // TODO(onboarding): remember that the intro was seen and skip it next time.
  _Stage _stage = _Stage.splash;

  void _go(_Stage stage) => setState(() => _stage = stage);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.slow),
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      child: switch (_stage) {
        _Stage.splash => SplashScreen(
          key: const ValueKey(_Stage.splash),
          ready: widget.ready,
          onDone: () => _go(_Stage.intro),
        ),
        _Stage.intro => IntroScreen(
          key: const ValueKey(_Stage.intro),
          onDone: () => _go(_Stage.welcome),
        ),
        _Stage.welcome => WelcomeScreen(
          key: const ValueKey(_Stage.welcome),
          // Account first (PRD 12.1), then "Complete your profile" with a
          // Skip button: the ID scan and selfie are optional here, but
          // booking stays closed until the clinic approves them.
          onCreateAccount: () => openSignUp(
            context,
            onSignedIn: (_) =>
                openProfile(context, afterFinish: () => openHome(context)),
          ),
          // Everyone lands on the home shell (recovery tab); the
          // appointments tab shows what is missing from the profile.
          onLogin: () =>
              openLogin(context, onSignedIn: (_) => openHome(context)),
        ),
      },
    );
  }
}
