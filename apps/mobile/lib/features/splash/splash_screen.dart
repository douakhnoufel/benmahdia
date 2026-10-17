import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/breathing_logo.dart';

/// First screen: the breathing logo, shown until [ready] completes and for
/// at least [AppMotion.splashMinimum] so it never just flashes, then
/// [onDone].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.ready, required this.onDone});

  /// Startup work (restoring settings, session…). Must not fail.
  final Future<void> ready;
  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_finish());
  }

  Future<void> _finish() async {
    await Future.wait([
      widget.ready,
      Future<void>.delayed(AppMotion.splashMinimum),
    ]);
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.teal900,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.teal900, AppColors.teal700],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.screenHorizontal,
                vertical: AppSpace.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BreathingLogo(),
                  const SizedBox(height: AppSpace.lg),
                  Text(
                    l10n.appName,
                    textAlign: TextAlign.center,
                    style: text.displayLarge?.copyWith(
                      color: AppColors.onPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    l10n.splashLine1,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(color: AppColors.teal50),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    l10n.splashLine2,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: AppColors.sand300),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
