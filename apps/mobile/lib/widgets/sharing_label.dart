import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';

/// Who can see a piece of the patient's own data (habit-tracking design:
/// "explain what the doctor can see", Algeria's law 18-07).
enum Sharing {
  /// Kept on the phone; nobody else sees it.
  onlyYou,

  /// Saved on the clinic's server: every doctor of the clinic sees it
  /// (PRD 3).
  doctorSees,
}

/// A small line beside anything the patient writes or logs, saying who can
/// see it. Never a warning colour: it informs, it does not alarm.
class SharingLabel extends StatelessWidget {
  const SharingLabel({super.key, required this.sharing});

  final Sharing sharing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final label = switch (sharing) {
      Sharing.onlyYou => l10n.sharingOnlyYou,
      Sharing.doctorSees => l10n.sharingDoctorSees,
    };
    final icon = switch (sharing) {
      Sharing.onlyYou => Icons.lock_outline_rounded,
      Sharing.doctorSees => Icons.visibility_outlined,
    };

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpace.xs,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          Flexible(
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
