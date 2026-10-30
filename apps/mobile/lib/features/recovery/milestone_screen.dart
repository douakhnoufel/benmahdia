import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import 'recovery_models.dart';

/// The celebration of a milestone (PRD 5.1): the badge pops in once, then
/// the badges of the whole streak so far. Supportive wording only.
class MilestoneScreen extends StatefulWidget {
  const MilestoneScreen({super.key, required this.days, required this.name});

  /// The milestone reached, in days.
  final int days;

  /// What the patient stays away from, as the counter names it.
  final String name;

  @override
  State<MilestoneScreen> createState() => _MilestoneScreenState();
}

class _MilestoneScreenState extends State<MilestoneScreen>
    with SingleTickerProviderStateMixin {
  late final _pop = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion shows the badge at once.
    _pop
      ..duration = AppMotion.of(context, AppMotion.slow)
      ..forward();
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  /// Every milestone of this streak up to the one reached.
  List<int> get _earned => [
    for (final m in milestones)
      if (m <= widget.days) m,
    for (var y = 730; y <= widget.days; y += 365) y,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.screenHorizontal,
            vertical: AppSpace.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              ScaleTransition(
                scale: CurvedAnimation(parent: _pop, curve: AppMotion.pop),
                child: Center(child: _Badge(days: widget.days)),
              ),
              const SizedBox(height: AppSpace.xl),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  l10n.milestoneTitle,
                  textAlign: TextAlign.center,
                  style: text.headlineLarge,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                l10n.milestoneBody(widget.days, widget.name),
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: AppColors.textBody),
              ),
              const SizedBox(height: AppSpace.xl),
              Text(
                l10n.milestoneBadges,
                textAlign: TextAlign.center,
                style: text.labelLarge?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final m in _earned)
                    Chip(
                      avatar: Icon(
                        Icons.star_rounded,
                        size: AppType.h3.size,
                        color: AppColors.onSand,
                      ),
                      label: Text(l10n.bookDays(m)),
                      backgroundColor: AppColors.sand100,
                      side: const BorderSide(color: AppColors.sand300),
                    ),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.milestoneContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The milestone's day count on a sand medal.
class _Badge extends StatelessWidget {
  const _Badge({required this.days});

  final int days;

  /// On the 4 px grid, wide enough for a four-digit count in `display`.
  static const _medal = AppSpace.xxxl * 3;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ExcludeSemantics(
      child: Container(
        width: _medal,
        height: _medal,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.sand100,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.sand400, width: AppSpace.xs),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_rounded,
              color: AppColors.sand500,
              size: AppType.h1.size,
            ),
            Text(
              '$days',
              style: text.displaySmall?.copyWith(color: AppColors.textStrong),
            ),
          ],
        ),
      ),
    );
  }
}
