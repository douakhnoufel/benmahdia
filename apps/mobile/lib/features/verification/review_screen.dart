import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/entrance.dart';
import '../../widgets/staggered_reveal.dart';
import 'verification_models.dart';
import 'verification_widgets.dart';

/// Step 3: the checks slide in one by one, then the patient submits. The
/// screen then cross-fades to the "under review" state; the account stays
/// pending until the clinic approves it (PRD 4.2).
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.quality,
    required this.onRetake,
    this.onSubmit,
  });

  /// Result of the on-device ID photo checks.
  final IdQuality quality;

  /// Goes back to retake the ID photos when a check failed.
  final VoidCallback onRetake;

  /// Sends the photos for review. Null in the demo: submitting only shows
  /// the pending state.
  final Future<void> Function()? onSubmit;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _sending = false;
  bool _submitted = false;

  Future<void> _submit() async {
    setState(() => _sending = true);
    try {
      await widget.onSubmit?.call();
      if (!mounted) return;
      setState(() => _submitted = true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: AppMotion.of(context, AppMotion.slow),
          switchInCurve: AppMotion.curve,
          switchOutCurve: AppMotion.curve,
          child: _submitted
              ? const _PendingView(key: ValueKey('pending'))
              : _ReviewView(
                  key: const ValueKey('review'),
                  quality: widget.quality,
                  sending: _sending,
                  onSubmit: _submit,
                  onRetake: widget.onRetake,
                ),
        ),
      ),
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({
    super.key,
    required this.quality,
    required this.sending,
    required this.onSubmit,
    required this.onRetake,
  });

  final IdQuality quality;
  final bool sending;
  final VoidCallback onSubmit;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final canSubmit = quality.passed && !sending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowTopBar(title: l10n.verifyTitle, step: 3, total: 3),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.screenHorizontal,
              vertical: AppSpace.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(l10n.reviewTitle, style: text.headlineLarge),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(l10n.reviewBody, style: text.bodyLarge),
                const SizedBox(height: AppSpace.xl),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.sm,
                    ),
                    child: StaggeredReveal(
                      spacing: 0,
                      children: [
                        _CheckRow(label: l10n.reviewSelfie, passed: true),
                        _CheckRow(label: l10n.reviewIdSides, passed: true),
                        _CheckRow(
                          label: l10n.reviewSharp,
                          passed: quality.sharp,
                        ),
                        _CheckRow(
                          label: l10n.reviewNoGlare,
                          passed: quality.noGlare,
                        ),
                        _CheckRow(
                          label: l10n.reviewCorners,
                          passed: quality.wholeCard,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: AppColors.teal600,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(l10n.reviewPrivacy, style: text.bodyMedium),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenHorizontal,
            0,
            AppSpace.screenHorizontal,
            AppSpace.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpace.md,
            children: [
              if (!quality.passed)
                OutlinedButton(
                  onPressed: onRetake,
                  child: Text(l10n.reviewRetake),
                ),
              FilledButton(
                onPressed: canSubmit ? onSubmit : null,
                child: sending
                    ? const SizedBox.square(
                        dimension: AppSpace.xl - AppSpace.xs,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : Text(l10n.reviewSubmit),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.passed});

  final String label;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final color = passed ? AppColors.success : AppColors.danger;
    return Semantics(
      checked: passed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Container(
              width: AppSpace.xl + AppSpace.xs,
              height: AppSpace.xl + AppSpace.xs,
              decoration: BoxDecoration(
                color: AppColors.tint(color),
                shape: BoxShape.circle,
              ),
              child: Icon(
                passed ? Icons.check_rounded : Icons.close_rounded,
                size: AppSpace.lg + 2,
                color: color,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.textStrong),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingView extends StatelessWidget {
  const _PendingView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.screenHorizontal),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Entrance(
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppColors.teal50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  size: AppSpace.xxxl,
                  color: AppColors.teal600,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            Entrance(
              offset: AppSpace.lg,
              child: Column(
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.pendingTitle,
                      textAlign: TextAlign.center,
                      style: text.headlineLarge,
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    l10n.pendingBody,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge,
                  ),
                  const SizedBox(height: AppSpace.xl),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.sm,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.tint(AppColors.warning),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Text(
                          l10n.pendingStatus,
                          style: text.labelMedium?.copyWith(
                            color: AppColors.textStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
