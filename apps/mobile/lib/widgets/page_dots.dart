import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Pager dots; the active one stretches into a pill. Follows the reading
/// direction, so the first dot sits on the right in Arabic.
class PageDots extends StatelessWidget {
  const PageDots({
    super.key,
    required this.count,
    required this.index,
    required this.semanticLabel,
  });

  final int count;
  final int index;

  /// e.g. "Page 2 of 3".
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.of(context, AppMotion.medium);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpace.sm,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: duration,
              curve: AppMotion.curve,
              width: i == index ? AppSpace.xl : AppSpace.sm,
              height: AppSpace.sm,
              decoration: BoxDecoration(
                color: i == index ? AppColors.teal500 : AppColors.sand300,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
        ],
      ),
    );
  }
}
