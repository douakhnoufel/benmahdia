import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import 'auth_models.dart';
import 'auth_repository.dart';
import 'auth_widgets.dart';
import 'phone_number.dart';
import 'social_sign_in.dart';

enum _Busy { password, google, apple }

/// Log in with phone + password, or Google / Apple. Five wrong passwords
/// lock the account for a while (PRD 4.1).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    required this.onSignedIn,
    required this.onForgot,
    required this.onCreateAccount,
  });

  final ValueChanged<AuthSession> onSignedIn;

  /// Receives what was typed in the phone field, to prefill the reset.
  final ValueChanged<String> onForgot;
  final VoidCallback onCreateAccount;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String? _phoneError;
  String? _failure;
  _Busy? _busy;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _clearErrors() {
    if (_phoneError != null || _failure != null) {
      setState(() {
        _phoneError = null;
        _failure = null;
      });
    }
  }

  Future<void> _logIn() async {
    final l10n = AppLocalizations.of(context);
    final phone = PhoneNumber.tryParse(_phone.text);
    if (phone == null) {
      setState(() => _phoneError = l10n.authPhoneInvalid);
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _failure = l10n.authWrongCredentials);
      return;
    }
    setState(() {
      _phoneError = null;
      _failure = null;
      _busy = _Busy.password;
    });
    try {
      final session = await ref
          .read(authRepositoryProvider)
          .logIn(phone, _password.text);
      ref.read(sessionProvider.notifier).set(session);
      if (mounted) widget.onSignedIn(session);
    } on AuthFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _failure = authFailureText(l10n, f);
        _password.clear();
      });
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
      title: l10n.authLoginTitle,
      body: l10n.authLoginBody,
      showLanguage: true,
      footer: SwitchLine(
        question: l10n.authNoAccount,
        action: l10n.authCreateLink,
        onPressed: widget.onCreateAccount,
      ),
      children: [
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpace.md,
            children: [
              PhoneField(
                controller: _phone,
                errorText: _phoneError,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _clearErrors(),
              ),
              PasswordField(
                controller: _password,
                label: l10n.authPasswordLabel,
                onChanged: (_) => _clearErrors(),
                onSubmitted: (_) => busy ? null : _logIn(),
              ),
            ],
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: busy ? null : () => widget.onForgot(_phone.text),
            child: Text(l10n.authForgot),
          ),
        ),
        FailureNote(message: _failure),
        BusyButton(
          label: l10n.authLoginButton,
          busy: _busy == _Busy.password,
          onPressed: busy ? null : _logIn,
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
      ],
    );
  }
}
