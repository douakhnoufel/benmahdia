import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../auth/auth_widgets.dart';

/// "Complete your profile": says what is collected, who sees it and what
/// happens next, and asks for consent. The step is mandatory, with no Skip:
/// booking stays closed until the ID is declared and approved (PRD 4.1, 4.2).
class ProfilePromptScreen extends StatefulWidget {
  const ProfilePromptScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  State<ProfilePromptScreen> createState() => _ProfilePromptScreenState();
}

class _ProfilePromptScreenState extends State<ProfilePromptScreen> {
  bool _consent = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthPage(
      title: l10n.profileTitle,
      body: l10n.profilePromptBody,
      children: [
        _Point(icon: Icons.badge_outlined, text: l10n.profileWhatId),
        _Point(
          icon: Icons.face_retouching_natural,
          text: l10n.profileWhatSelfie,
        ),
        _Point(icon: Icons.fact_check_outlined, text: l10n.profileWhatApproval),
        CheckboxListTile(
          key: const ValueKey('profile-consent'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _consent,
          onChanged: (v) => setState(() => _consent = v ?? false),
          title: Text(l10n.profileConsent),
        ),
        FilledButton(
          key: const ValueKey('profile-start'),
          onPressed: _consent ? widget.onStart : null,
          child: Text(l10n.profileStart),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.teal700),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
