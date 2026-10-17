import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../booking/booking_widgets.dart';
import 'auth_models.dart';
import 'auth_repository.dart';
import 'auth_widgets.dart';
import 'phone_number.dart';
import 'social_sign_in.dart';

enum _Busy { phone, google, apple }

/// Create an account: a phone number (an SMS code follows), or Google /
/// Apple. Anyone can sign up; the clinic verifies identity before anything
/// clinical unlocks (PRD 4.1, 12.1).
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({
    super.key,
    required this.onCodeSent,
    required this.onSignedIn,
    required this.onLogin,
  });

  final void Function(PhoneNumber phone, OtpTicket ticket) onCodeSent;

  /// Google / Apple finished; the account may still need a phone number.
  final ValueChanged<AuthSession> onSignedIn;
  final VoidCallback onLogin;

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _phone = TextEditingController();
  String? _phoneError;
  String? _failure;
  _Busy? _busy;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final l10n = AppLocalizations.of(context);
    final phone = PhoneNumber.tryParse(_phone.text);
    if (phone == null) {
      setState(() => _phoneError = l10n.authPhoneInvalid);
      return;
    }
    setState(() {
      _phoneError = null;
      _failure = null;
      _busy = _Busy.phone;
    });
    try {
      final ticket = await ref
          .read(authRepositoryProvider)
          .requestCode(phone, OtpPurpose.signUp);
      if (mounted) widget.onCodeSent(phone, ticket);
    } on AuthFailure catch (f) {
      if (mounted) setState(() => _failure = authFailureText(l10n, f));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _social(SocialProvider provider) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _failure = null;
      _busy = provider == SocialProvider.google ? _Busy.google : _Busy.apple;
    });
    try {
      final session = await signInWith(ref, provider);
      if (session != null && mounted) widget.onSignedIn(session);
    } on AuthFailure catch (f) {
      if (mounted) setState(() => _failure = authFailureText(l10n, f));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = _busy != null;
    return AuthPage(
      title: l10n.authSignUpTitle,
      body: l10n.authSignUpBody,
      showLanguage: true,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpace.sm,
        children: [
          SwitchLine(
            question: l10n.authHaveAccount,
            action: l10n.authLoginLink,
            onPressed: widget.onLogin,
          ),
          Text(
            l10n.authTerms,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      children: [
        PhoneField(
          controller: _phone,
          errorText: _phoneError,
          onSubmitted: (_) => busy ? null : _sendCode(),
          onChanged: (_) {
            if (_phoneError != null) setState(() => _phoneError = null);
          },
        ),
        FailureNote(message: _failure),
        BusyButton(
          label: l10n.authContinue,
          busy: _busy == _Busy.phone,
          onPressed: busy ? null : _sendCode,
        ),
        const OrDivider(),
        SocialButton(
          provider: SocialProvider.google,
          busy: _busy == _Busy.google,
          onPressed: busy ? null : () => _social(SocialProvider.google),
        ),
        SocialButton(
          provider: SocialProvider.apple,
          busy: _busy == _Busy.apple,
          onPressed: busy ? null : () => _social(SocialProvider.apple),
        ),
        InfoLine(text: l10n.authSocialNote, icon: Icons.verified_user_outlined),
      ],
    );
  }
}
