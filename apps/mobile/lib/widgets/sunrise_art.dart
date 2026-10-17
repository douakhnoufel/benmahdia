import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Sunrise over soft hills. [rise] (0..1) lifts the sun and draws the arcs in;
/// [glow] (0..1) breathes the halo.
class SunriseArt extends StatelessWidget {
  const SunriseArt({super.key, required this.rise, required this.glow});

  final Animation<double> rise;
  final Animation<double> glow;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SunrisePainter(rise: rise, glow: glow),
      ),
    );
  }
}

class _SunrisePainter extends CustomPainter {
  _SunrisePainter({required this.rise, required this.glow})
    : super(repaint: Listenable.merge([rise, glow]));

  final Animation<double> rise;
  final Animation<double> glow;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rise.value;
    final g = glow.value;
    final horizon = size.height * 0.78;
    final sunRadius = size.shortestSide * 0.14;
    final sunY = horizon + sunRadius - (sunRadius + size.height * 0.32) * r;
    final center = Offset(size.width / 2, sunY);

    for (var i = 3; i >= 1; i--) {
      final haloRadius = sunRadius * (1 + i * 0.9) * (1 + 0.06 * g);
      canvas.drawCircle(
        center,
        haloRadius,
        Paint()..color = AppColors.teal100.withValues(alpha: 0.25 + 0.1 * g),
      );
    }

    canvas.drawCircle(center, sunRadius, Paint()..color = AppColors.sand400);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..color = AppColors.teal300;
    for (var i = 1; i <= 3; i++) {
      final arcRadius = size.width * (0.22 + 0.13 * i);
      final rect = Rect.fromCircle(
        center: Offset(size.width / 2, horizon),
        radius: arcRadius,
      );
      final path = Path()..addArc(rect, 3.14159, 3.14159);
      for (final metric in path.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * r), arcPaint);
      }
    }

    final hills = Path()
      ..moveTo(0, horizon)
      ..quadraticBezierTo(
        size.width * 0.25,
        horizon - size.height * 0.12,
        size.width * 0.5,
        horizon,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        horizon + size.height * 0.1,
        size.width,
        horizon - size.height * 0.04,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hills, Paint()..color = AppColors.teal200);

    final front = Path()
      ..moveTo(0, horizon + size.height * 0.08)
      ..quadraticBezierTo(
        size.width * 0.4,
        horizon - size.height * 0.04,
        size.width,
        horizon + size.height * 0.1,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(front, Paint()..color = AppColors.teal300);
  }

  @override
  bool shouldRepaint(_SunrisePainter old) =>
      old.rise != rise || old.glow != glow;
}
