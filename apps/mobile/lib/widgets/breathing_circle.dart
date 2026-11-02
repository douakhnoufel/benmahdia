import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';

/// The three parts of one breath.
enum BreathPhase { inhale, hold, exhale }

/// Seconds of each part: breathe in 4, hold 4, breathe out 6.
const breathInhale = 4;
const breathHold = 4;
const breathExhale = 6;
const breathCycle = breathInhale + breathHold + breathExhale;

/// The part of the breath [elapsed] falls in, and how full the lungs are
/// (0 empty, 1 full) at that moment. Pure, so tests can check the rhythm.
({BreathPhase phase, double fill}) breathAt(Duration elapsed) {
  final t = (elapsed.inMicroseconds / Duration.microsecondsPerSecond) %
      breathCycle;
  if (t < breathInhale) return (phase: BreathPhase.inhale, fill: t / breathInhale);
  if (t < breathInhale + breathHold) return (phase: BreathPhase.hold, fill: 1);
  return (
    phase: BreathPhase.exhale,
    fill: 1 - (t - breathInhale - breathHold) / breathExhale,
  );
}

/// A circle that grows while the patient breathes in, rests while they hold
/// and shrinks while they breathe out, with the instruction written inside.
/// With reduced motion the circle stays still and only the words change.
class BreathingCircle extends StatefulWidget {
  const BreathingCircle({super.key, this.size = 220});

  final double size;

  @override
  State<BreathingCircle> createState() => _BreathingCircleState();
}

class _BreathingCircleState extends State<BreathingCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: breathCycle),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_controller.repeat());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _word(AppLocalizations l10n, BreathPhase phase) => switch (phase) {
    BreathPhase.inhale => l10n.momentInhale,
    BreathPhase.hold => l10n.momentHold,
    BreathPhase.exhale => l10n.momentExhale,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final reduced = AppMotion.reduced(context);
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final now = breathAt(_controller.duration! * _controller.value);
          final fill = reduced ? 1.0 : now.fill;
          final scale = 0.6 + 0.4 * fill;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size,
                height: widget.size,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.teal50,
                ),
              ),
              Container(
                width: widget.size * scale,
                height: widget.size * scale,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.teal600,
                ),
              ),
              Semantics(
                liveRegion: true,
                child: Text(
                  _word(l10n, now.phase),
                  style: text.titleLarge?.copyWith(color: AppColors.onPrimary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
