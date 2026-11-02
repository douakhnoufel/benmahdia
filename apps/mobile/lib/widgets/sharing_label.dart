import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_tokens.dart';

/// Who can read what the patient writes here: only them, or their doctor too.
enum SharingKind { onlyYou, doctor }

class SharingLabel extends StatelessWidget {
  const SharingLabel(this.kind, {super.key});

  final SharingKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final (icon, label) = switch (kind) {
      SharingKind.onlyYou => (Icons.lock_outline_rounded, l10n.sharingOnlyYou),
      SharingKind.doctor => (Icons.visibility_outlined, l10n.sharingDoctor),
    };
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
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
    );
  }
}
