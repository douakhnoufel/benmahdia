import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The round app mark. Teal on light screens; white with a teal leaf on dark
/// ones ([onDark]).
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 44, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark ? AppColors.surface : AppColors.teal500,
        shape: BoxShape.circle,
        boxShadow: AppShadows.lg,
      ),
      child: Icon(
        Icons.spa_rounded,
        size: size * 0.5,
        color: onDark ? AppColors.teal500 : AppColors.onPrimary,
      ),
    );
  }
}
