import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The round app mark: the clinic logo on a white disc, on light and dark
/// screens alike ([onDark] is kept for callers; the disc reads on both).
/// Decorative: screen readers skip it.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 44, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: AppShadows.lg,
      ),
      child: Image.asset(
        'assets/brand/logo.png',
        excludeFromSemantics: true,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
