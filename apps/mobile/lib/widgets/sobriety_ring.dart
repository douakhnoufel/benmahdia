import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Circular day counter (DESIGN.md "Sobriety ring"). The ring fills and the
/// number counts up to [days] over [AppMotion.ringFill]; when [days] changes
/// it animates on from where it is. At or past [goal] a sand milestone badge
/// pops in at the ring tip.
class SobrietyRing extends StatelessWidget {
  const SobrietyRing({
    super.key,
    required this.days,
    required this.goal,
    required this.label,
    required this.semanticLabel,
    this.size = 168,
  });

  final int days;

  /// Days that complete the ring (the next milestone).
  final int goal;

  /// Caption under the number, e.g. "days clean".
  final String label;

  /// What a screen reader says for the whole ring, e.g. "42 of 60 days".
  final String semanticLabel;

  final double size;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stroke = size * 0.075;
    final badge = stroke * 2.6;

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: days.toDouble()),
          duration: AppMotion.of(context, AppMotion.ringFill),
          curve: AppMotion.curve,
          builder: (context, value, caption) {
            final fraction = goal <= 0 ? 0.0 : (value / goal).clamp(0.0, 1.0);
            final reached = days >= goal && value >= days;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RingPainter(fraction: fraction, stroke: stroke),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${value.round()}',
                        style: text.displayLarge?.copyWith(
                          color: AppColors.teal700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      ?caption,
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Transform.translate(
                    offset: Offset(0, stroke / 2 - badge / 2),
                    child: AnimatedScale(
                      scale: reached ? 1 : 0,
                      duration: AppMotion.of(context, AppMotion.medium),
                      curve: AppMotion.pop,
                      child: _MilestoneBadge(size: badge),
                    ),
                  ),
                ),
              ],
            );
          },
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
        ),
      ),
    );
  }
}

class _MilestoneBadge extends StatelessWidget {
  const _MilestoneBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.sand400,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 2),
        boxShadow: AppShadows.card,
      ),
      child: Icon(
        Icons.star_rounded,
        size: size * 0.6,
        color: AppColors.onSand,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.stroke});

  final double fraction;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final ring = bounds.deflate(stroke / 2);

    canvas.drawArc(
      ring,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.teal100,
    );
    if (fraction <= 0) return;

    final sweep = 2 * math.pi * fraction;
    canvas.drawArc(
      ring,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          endAngle: sweep,
          transform: const GradientRotation(-math.pi / 2),
          colors: const [AppColors.teal500, AppColors.teal400],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.stroke != stroke;
}
