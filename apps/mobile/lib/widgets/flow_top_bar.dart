import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';

/// Top of each step in a multi-step flow (verification, booking): back,
/// title, "step / total" and a thin bar that fills into this step as the
/// page opens (DESIGN.md "Stepper").
class FlowTopBar extends StatelessWidget {
  const FlowTopBar({
    super.key,
    required this.title,
    required this.step,
    required this.total,
    this.onDark = false,
  });

  final String title;
  final int step;
  final int total;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final fg = onDark ? AppColors.onPrimary : AppColors.textStrong;
    final muted = onDark ? AppColors.teal100 : AppColors.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            BackButton(color: fg),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(color: fg),
              ),
            ),
            SizedBox(
              width: 48,
              child: Semantics(
                label: l10n.verifyStepSemantics(step, total),
                excludeSemantics: true,
                child: Text(
                  l10n.verifyStep(step, total),
                  // Keep "1 / 3" in reading order inside Arabic text.
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.screenHorizontal,
          ),
          child: StepBar(step: step, total: total, onDark: onDark),
        ),
      ],
    );
  }
}

/// Thin progress bar from the start edge; fills from the previous step to
/// [step] when built.
class StepBar extends StatelessWidget {
  const StepBar({
    super.key,
    required this.step,
    required this.total,
    this.onDark = false,
  });

  final int step;
  final int total;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: (step - 1) / total, end: step / total),
        duration: AppMotion.of(context, AppMotion.slow),
        curve: AppMotion.curve,
        builder: (context, value, _) => ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: SizedBox(
            height: AppSpace.xs,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: onDark ? AppColors.teal800 : AppColors.sand200,
                ),
                FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: value,
                  child: ColoredBox(
                    color: onDark ? AppColors.teal300 : AppColors.teal500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
