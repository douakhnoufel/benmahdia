import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../auth/auth_flow.dart';
import '../booking/booking_flow.dart';
import '../intro/intro_screen.dart';
import '../splash/splash_screen.dart';
import '../verification/verification_flow.dart';
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
          // Account first (PRD 12.1), then the identity check.
          onCreateAccount: () =>
              openSignUp(context, onSignedIn: (_) => openVerification(context)),
          // Verified patients go to their appointments; others finish the
          // identity check first.
          onLogin: () => openLogin(
            context,
            onSignedIn: (session) => session.user.verified
                ? openAppointments(context)
                : openVerification(context),
          ),
        ),
      },
    );
  }
}
