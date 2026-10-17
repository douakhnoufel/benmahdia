import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/lang_toggle.dart';
import '../../widgets/sunrise_art.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.onCreateAccount,
    required this.onLogin,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onLogin;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final Animation<double> _riseCurve = CurvedAnimation(
    parent: _rise,
    curve: AppMotion.curve,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduced(context)) {
      _rise.value = 1;
    } else {
      unawaited(_rise.forward());
      unawaited(_glow.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _rise.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final artHeight = (MediaQuery.sizeOf(context).height * 0.32).clamp(
      170.0,
      300.0,
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.screenHorizontal,
                vertical: AppSpace.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Brand(
                          name: l10n.appName,
                          tagline: l10n.appTagline,
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      const SizedBox(width: 150, child: LangToggle()),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xl),
                  ExcludeSemantics(
                    child: SizedBox(
                      height: artHeight,
                      child: SunriseArt(rise: _riseCurve, glow: _glow),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.welcomeTitle,
                      textAlign: TextAlign.center,
                      style: text.headlineLarge,
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    l10n.welcomeBody,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge,
                  ),
                  const SizedBox(height: AppSpace.xxl),
                  FilledButton(
                    onPressed: widget.onCreateAccount,
                    child: Text(l10n.createAccount),
                  ),
                  const SizedBox(height: AppSpace.md),
                  OutlinedButton(
                    onPressed: widget.onLogin,
                    child: Text(l10n.haveAccount),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Flexible(
                        child: Text(l10n.secureFooter, style: text.bodySmall),
                      ),
                    ],
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

class _Brand extends StatelessWidget {
  const _Brand({required this.name, required this.tagline});

  final String name;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.teal500,
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: const Icon(Icons.spa_rounded, color: AppColors.onPrimary),
        ),
        const SizedBox(width: AppSpace.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge?.copyWith(color: AppColors.teal700),
              ),
              Text(
                tagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
