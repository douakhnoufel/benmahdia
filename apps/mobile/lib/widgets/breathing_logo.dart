import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_mark.dart';

/// The app mark breathing: three rings slowly grow and fade while the mark
/// swells a little, one breath per [AppMotion.breath]. It loops until removed
/// and stays still when the OS asks for reduced motion. Decorative.
class BreathingLogo extends StatefulWidget {
  const BreathingLogo({super.key, this.size = 240});

  /// Width and height of the whole drawing, rings included.
  final double size;

  @override
  State<BreathingLogo> createState() => _BreathingLogoState();
}

class _BreathingLogoState extends State<BreathingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: AppMotion.breath,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BreathPainter(breath: _breath),
          child: SizedBox.square(
            dimension: widget.size,
            child: Center(
              child: AnimatedBuilder(
                animation: _breath,
                builder: (context, child) => Transform.scale(
                  scale: 1 + 0.05 * _inhale(_breath.value),
                  child: child,
                ),
                child: AppMark(size: widget.size * 0.34, onDark: true),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 0 → 1 → 0 over one breath, smooth at both ends so the loop has no seam.
double _inhale(double t) => (1 - math.cos(2 * math.pi * t)) / 2;

class _BreathPainter extends CustomPainter {
  _BreathPainter({required this.breath}) : super(repaint: breath);

  final Animation<double> breath;

  static const _rings = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    final minRadius = maxRadius * 0.24;
    final t = breath.value;
    final glow = _inhale(t);

    canvas.drawCircle(
      center,
      maxRadius * (0.62 + 0.06 * glow),
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.sand300.withValues(alpha: 0.28 + 0.14 * glow),
            AppColors.sand300.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: maxRadius)),
    );

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < _rings; i++) {
      final phase = (t + i / _rings) % 1;
      ring.color = AppColors.teal200.withValues(alpha: 0.5 * (1 - phase));
      canvas.drawCircle(
        center,
        minRadius + (maxRadius - minRadius) * phase,
        ring,
      );
    }
  }

  @override
  bool shouldRepaint(_BreathPainter old) => old.breath != breath;
}
