import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Fades [child] in and lifts it into place when first built, and again
/// whenever [visible] turns true; fades it out when [visible] turns false.
/// Implicit: one target value, no controller.
class Entrance extends StatelessWidget {
  const Entrance({
    super.key,
    required this.child,
    this.visible = true,
    this.offset = AppSpace.xl,
  });

  final Widget child;
  final bool visible;

  /// How far below its place (in logical pixels) the child starts.
  final double offset;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: visible ? 1 : 0),
      duration: AppMotion.of(context, AppMotion.slow),
      curve: AppMotion.curve,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, offset * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
