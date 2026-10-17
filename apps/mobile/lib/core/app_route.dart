import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Route used between onboarding and verification steps: a short fade with a
/// slide in from the reading direction's end edge (mirrored in RTL).
/// [reduced] (OS reduced motion) makes the change instant.
Route<T> appRoute<T>(Widget page, {required bool reduced}) {
  final duration = reduced ? Duration.zero : AppMotion.medium;
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final curve = CurveTween(curve: AppMotion.curve);
      return FadeTransition(
        opacity: animation.drive(curve),
        child: SlideTransition(
          position: animation.drive(
            Tween<Offset>(
              begin: Offset(rtl ? -_slide : _slide, 0),
              end: Offset.zero,
            ).chain(curve),
          ),
          child: child,
        ),
      );
    },
  );
}

/// How far (as a fraction of the screen width) a new page travels in.
const _slide = 0.08;
