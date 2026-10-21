import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../auth/auth_widgets.dart';

/// The details reached the clinic.
class ProfileDoneScreen extends StatelessWidget {
  const ProfileDoneScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthPage(
      title: l10n.profileDoneTitle,
      body: l10n.profileDoneBody,
      children: [
        FilledButton(
          key: const ValueKey('profile-done'),
          onPressed: onContinue,
          child: Text(l10n.profileDoneAction),
        ),
      ],
    );
  }
}
