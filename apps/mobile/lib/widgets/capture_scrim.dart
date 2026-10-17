import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Dims everything except [hole] (DESIGN.md "Capture frame"): an oval for
/// the selfie ([oval]) or a rounded card for the ID ([radius]).
class CaptureScrimPainter extends CustomPainter {
  const CaptureScrimPainter({
    required this.hole,
    this.oval = false,
    this.radius = AppRadius.card,
  });

  final Rect hole;
  final bool oval;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (oval) {
      path.addOval(hole);
    } else {
      path.addRRect(RRect.fromRectAndRadius(hole, Radius.circular(radius)));
    }
    canvas.drawPath(path, Paint()..color = AppColors.overlay);
  }

  @override
  bool shouldRepaint(CaptureScrimPainter old) =>
      old.hole != hole || old.oval != oval || old.radius != radius;
}
