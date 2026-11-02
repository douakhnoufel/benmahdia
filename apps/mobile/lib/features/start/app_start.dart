import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_tokens.dart';
import '../auth/auth_repository.dart';
import '../intro/intro_screen.dart';
import '../home/home_shell.dart';
import '../splash/life_quality_splash_screen.dart';
import '../welcome/welcome_entry.dart';

enum _Stage { splash, intro, welcome }

/// Cold start: splash → intro slides → welcome, cross-fading between them.
class AppStart extends StatefulWidget {
  const AppStart({
    super.key,
    required this.ready,
    this.splashVariant = SplashVariant.blue,
  });

  /// Startup work the splash waits for.
  final Future<void> ready;

  /// Which splash look this launch shows (alternates per launch).
  final SplashVariant splashVariant;

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
        _Stage.splash => LifeQualitySplashScreen(
          key: const ValueKey(_Stage.splash),
          variant: widget.splashVariant,
          ready: widget.ready,
          // A restored login goes straight to the app.
          onFinish: () =>
              ProviderScope.containerOf(context).read(sessionProvider) != null
              ? openHome(context)
              : _go(_Stage.intro),
        ),
        _Stage.intro => IntroScreen(
          key: const ValueKey(_Stage.intro),
          onDone: () => _go(_Stage.welcome),
        ),
        _Stage.welcome => welcomeEntry(
          context,
          key: const ValueKey(_Stage.welcome),
          onOpenHome: () => openHome(context),
        ),
      },
    );
  }
}
