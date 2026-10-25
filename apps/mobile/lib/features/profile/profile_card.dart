import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import 'identity_models.dart';

/// Shown on the appointments screen until the clinic approves the profile:
/// what is missing, what is happening, and the button for the next step.
///
/// The ID status label is "ID declared" for `declared`, and stays next to
/// `approved` ("ID declared · approved"); it never says "verified" (PRD 4.2).
class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.state,
    required this.onComplete,
    required this.onRefresh,
  });

  final IdentityState state;

  /// Start (or restart) the declaration.
  final VoidCallback onComplete;

  /// Ask the server whether the clinic has decided.
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final reason = state.rejectReason;
    final status = switch (state.status) {
      IdStatus.declared => l10n.profileIdDeclared,
      IdStatus.approved => l10n.profileIdDeclaredApproved,
      _ => null,
    };
    final (icon, title, body, label, action) = switch (state.status) {
      IdStatus.declared => (
        Icons.hourglass_top_rounded,
        l10n.profileCardDeclaredTitle,
        l10n.profileCardDeclaredBody,
        l10n.profileCardRefresh,
        onRefresh,
      ),
      IdStatus.approved => (
        Icons.check_circle_outline_rounded,
        l10n.profileIdDeclaredApproved,
        null,
        l10n.profileCardRefresh,
        null,
      ),
      IdStatus.rejected => (
        Icons.error_outline_rounded,
        l10n.profileCardRejectedTitle,
        [
          l10n.profileCardRejectedBody,
          if (reason != null && reason.isNotEmpty)
            l10n.profileCardReason(reason),
          if (state.submissionsLeft <= 0) l10n.profileErrTooMany,
        ].join('\n'),
        l10n.profileCardRetry,
        state.canSubmit ? onComplete : null,
      ),
      IdStatus.none => (
        Icons.badge_outlined,
        l10n.profileTitle,
        l10n.profileCardNoneBody,
        l10n.profileCardAction,
        onComplete,
      ),
    };
    return Card(
      key: const ValueKey('profile-card'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.teal700),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpace.sm,
                children: [
                  if (status != null && status != title)
                    Text(
                      status,
                      key: const ValueKey('profile-card-status'),
                      style: text.labelMedium?.copyWith(
                        color: AppColors.teal700,
                      ),
                    ),
                  Semantics(
                    header: true,
                    child: Text(title, style: text.titleMedium),
                  ),
                  if (body != null) Text(body, style: text.bodyMedium),
                  if (action != null)
                    FilledButton.tonal(
                      key: const ValueKey('profile-card-action'),
                      onPressed: action,
                      child: Text(label),
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
