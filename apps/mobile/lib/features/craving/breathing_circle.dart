import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';

/// Urge surfing: a circle that grows while the patient breathes in, holds,
/// then shrinks while they breathe out — inhale 4 · hold 4 · exhale 6
/// (habit-tracking design). It loops until the screen is left, and stays
/// still (one calm instruction, no countdown) when the OS asks for reduced
/// motion.
class BreathingCircle extends StatefulWidget {
  const BreathingCircle({super.key, this.size = 200});

  /// Width and height of the whole drawing.
  final double size;

  @override
  State<BreathingCircle> createState() => _BreathingCircleState();
}

/// One stretch of a breath.
enum _Phase { inhale, hold, exhale }

class _BreathingCircleState extends State<BreathingCircle>
    with SingleTickerProviderStateMixin {
  static const _cycle = Duration(
    milliseconds:
        0 +
        AppMotion.breatheInMs +
        AppMotion.breatheHoldMs +
        AppMotion.breatheOutMs,
  );

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: _cycle,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: the circle is still, so nothing pulses on screen.
    if (AppMotion.reduced(context)) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      unawaited(_breath.repeat());
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  /// Where in the breath [t] (0-1) falls, and how far through that stretch.
  static (_Phase, double) _at(double t) {
    final ms = t * _cycle.inMilliseconds;
    if (ms < AppMotion.breatheInMs) {
      return (_Phase.inhale, ms / AppMotion.breatheInMs);
    }
    final held = ms - AppMotion.breatheInMs;
    if (held < AppMotion.breatheHoldMs) {
      return (_Phase.hold, held / AppMotion.breatheHoldMs);
    }
    final out = held - AppMotion.breatheHoldMs;
    return (_Phase.exhale, (out / AppMotion.breatheOutMs).clamp(0, 1));
  }

  /// 0.68 (emptied) to 1 (full).
  static double _scale(_Phase phase, double done) => switch (phase) {
    _Phase.inhale => 0.68 + 0.32 * Curves.easeInOut.transform(done),
    _Phase.hold => 1,
    _Phase.exhale => 1 - 0.32 * Curves.easeInOut.transform(done),
  };

  int _secondsLeft(_Phase phase, double done) {
    final total = switch (phase) {
      _Phase.inhale => AppMotion.breatheInMs,
      _Phase.hold => AppMotion.breatheHoldMs,
      _Phase.exhale => AppMotion.breatheOutMs,
    };
    return (total * (1 - done) / 1000).ceil().clamp(1, 60);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final still = AppMotion.reduced(context);

    String word(_Phase phase) => switch (phase) {
      _Phase.inhale => l10n.momentBreatheIn,
      _Phase.hold => l10n.momentBreatheHold,
      _Phase.exhale => l10n.momentBreatheOut,
    };

    return Semantics(
      label: l10n.momentBreatheSlowly,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.teal50,
            ),
            child: Center(
              child: still
                  ? _Bubble(
                      size: widget.size * 0.84,
                      title: l10n.momentBreatheSlowly,
                      style: text,
                    )
                  : AnimatedBuilder(
                      animation: _breath,
                      builder: (context, _) {
                        final (phase, done) = _at(_breath.value);
                        return _Bubble(
                          size: widget.size * 0.84 * _scale(phase, done),
                          title: word(phase),
                          seconds: _secondsLeft(phase, done),
                          style: text,
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The teal bubble with the current instruction inside it.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.size,
    required this.title,
    required this.style,
    this.seconds,
  });

  final double size;
  final String title;
  final TextTheme style;
  final int? seconds;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.teal600,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: style.titleMedium?.copyWith(color: AppColors.onPrimary),
            ),
            if (seconds case final left?)
              Text(
                '$left',
                style: style.headlineMedium?.copyWith(
                  color: AppColors.onPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
