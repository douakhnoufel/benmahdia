import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';

enum BreathPhase { inhale, hold, exhale }

/// A calm breathing guide: inhale 4 s, hold 4 s, exhale 6 s, on a loop.
/// Under reduced motion the circle stays still and only the words change.
class BreathingCircle extends StatefulWidget {
  const BreathingCircle({super.key});

  @override
  State<BreathingCircle> createState() => _BreathingCircleState();
}

class _BreathingCircleState extends State<BreathingCircle> {
  static const _small = 0.6;
  static const _size = 200.0;

  BreathPhase _phase = BreathPhase.inhale;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  Duration _lengthOf(BreathPhase p) => switch (p) {
    BreathPhase.inhale => AppMotion.breatheIn,
    BreathPhase.hold => AppMotion.breatheHold,
    BreathPhase.exhale => AppMotion.breatheOut,
  };

  void _schedule() {
    _timer = Timer(_lengthOf(_phase), () {
      if (!mounted) return;
      setState(() {
        _phase = BreathPhase.values[(_phase.index + 1) % 3];
      });
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final label = switch (_phase) {
      BreathPhase.inhale => l10n.momentInhale,
      BreathPhase.hold => l10n.momentHold,
      BreathPhase.exhale => l10n.momentExhale,
    };
    final scale = _phase == BreathPhase.exhale ? _small : 1.0;
    final duration = _phase == BreathPhase.hold
        ? Duration.zero
        : AppMotion.of(context, _lengthOf(_phase));
    return Semantics(
      container: true,
      label: l10n.momentBreathe,
      liveRegion: true,
      value: label,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpace.md,
          children: [
            SizedBox(
              height: _size,
              child: Center(
                child: AnimatedScale(
                  scale: scale,
                  duration: duration,
                  curve: Curves.easeInOut,
                  child: Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.teal50,
                      border: Border.all(color: AppColors.teal600, width: 3),
                    ),
                  ),
                ),
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: text.titleLarge?.copyWith(color: AppColors.teal700),
            ),
          ],
        ),
      ),
    );
  }
}
