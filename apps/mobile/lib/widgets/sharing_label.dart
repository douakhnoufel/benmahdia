import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';

/// Who can read something the patient wrote or logged.
enum Audience { onlyYou, yourDoctor }

/// A small pill that says who can see what is on screen: "Only you" or
/// "Your doctor sees this". Shown beside anything the patient records.
class SharingLabel extends StatelessWidget {
  const SharingLabel(this.audience, {super.key});

  final Audience audience;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final (icon, label) = switch (audience) {
      Audience.onlyYou => (Icons.lock_outline_rounded, l10n.sharingOnlyYou),
      Audience.yourDoctor => (
        Icons.visibility_outlined,
        l10n.sharingDoctor,
      ),
    };
    return Semantics(
      label: label,
      container: true,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.teal50,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpace.xs,
            children: [
              Icon(icon, size: 16, color: AppColors.teal700),
              Flexible(
                child: Text(
                  label,
                  style: text.bodySmall?.copyWith(color: AppColors.teal700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
