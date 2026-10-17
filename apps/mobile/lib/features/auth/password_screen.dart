import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'auth_models.dart';
import 'auth_widgets.dart';
import 'password_rules.dart';

enum PasswordMode { create, reset }

/// Choose a password (new account) or a new one (after a reset code). The
/// button wakes up once every rule on the checklist is met.
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key, required this.mode, required this.onSubmit});

  final PasswordMode mode;

  /// Saves the password; may throw [AuthFailure].
  final Future<void> Function(String password) onSubmit;

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _failure;
  bool _busy = false;

  bool get _ready =>
      PasswordRule.allMetBy(_password.text) && _password.text == _confirm.text;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_ready || _busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.onSubmit(_password.text);
    } on AuthFailure catch (f) {
      if (mounted) setState(() => _failure = authFailureText(l10n, f));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final create = widget.mode == PasswordMode.create;
    void changed(String _) => setState(() => _failure = null);
    return AuthPage(
      title: create ? l10n.authPasswordTitle : l10n.authPasswordResetTitle,
      body: create ? l10n.authPasswordCreateBody : l10n.authPasswordResetBody,
      children: [
        PasswordField(
          controller: _password,
          label: l10n.authPasswordLabel,
          newPassword: true,
          textInputAction: TextInputAction.next,
          onChanged: changed,
        ),
        PasswordField(
          controller: _confirm,
          label: l10n.authPasswordConfirmLabel,
          newPassword: true,
          onChanged: changed,
          onSubmitted: (_) => _submit(),
        ),
        PasswordChecklist(password: _password.text, confirm: _confirm.text),
        FailureNote(message: _failure),
        BusyButton(
          label: create ? l10n.authCreateAccountButton : l10n.authSavePassword,
          busy: _busy,
          onPressed: _ready ? _submit : null,
        ),
      ],
    );
  }
}
