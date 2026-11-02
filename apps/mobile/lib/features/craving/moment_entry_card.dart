import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_route.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import 'difficult_moment_screen.dart';

/// The way into the difficult-moment screen from the recovery home.
class MomentEntryCard extends StatelessWidget {
  const MomentEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: '${l10n.momentEntryTitle}. ${l10n.momentEntrySub}',
      onTap: () => _open(context),
      child: Material(
        color: AppColors.teal800,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => _open(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Row(
                spacing: AppSpace.md,
                children: [
                  const Icon(
                    Icons.air_rounded,
                    color: AppColors.teal200,
                    size: 28,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: AppSpace.xs,
                      children: [
                        Text(
                          l10n.momentEntryTitle,
                          style: text.titleMedium?.copyWith(
                            color: AppColors.onPrimary,
                          ),
                        ),
                        Text(
                          l10n.momentEntrySub,
                          style: text.bodySmall?.copyWith(
                            color: AppColors.teal100,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    unawaited(
      Navigator.of(context).push<void>(
        appRoute(
          const DifficultMomentScreen(),
          reduced: AppMotion.reduced(context),
        ),
      ),
    );
  }
}
