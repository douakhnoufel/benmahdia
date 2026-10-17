import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

export '../../widgets/flow_top_bar.dart';

/// Where the live camera preview will go. A calm gradient until the camera
/// is wired.
class CameraPlaceholder extends StatelessWidget {
  const CameraPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.1),
          radius: 0.9,
          colors: [AppColors.teal700, AppColors.teal900],
        ),
      ),
    );
  }
}

/// Small rounded status on the camera screens. Announced by screen readers
/// when it changes.
class CameraStatusPill extends StatelessWidget {
  const CameraStatusPill({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppColors.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Why we need this photo" line with a lock, under each capture step.
class PrivacyLine extends StatelessWidget {
  const PrivacyLine({super.key, required this.text, this.onDark = false});

  final String text;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final color = onDark ? AppColors.teal100 : AppColors.textMuted;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 16, color: color),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
