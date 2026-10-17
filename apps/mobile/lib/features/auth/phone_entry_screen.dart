import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'auth_models.dart';
import 'auth_repository.dart';
import 'auth_widgets.dart';
import 'phone_number.dart';

/// A number to send a code to: to reset a forgotten password, or to add a
/// number to a Google / Apple account ([OtpPurpose.attachPhone]).
class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({
    super.key,
    required this.purpose,
    required this.onCodeSent,
    this.initial,
  }) : assert(purpose != OtpPurpose.signUp, 'Sign-up has its own screen');

  final OtpPurpose purpose;
  final void Function(PhoneNumber phone, OtpTicket ticket) onCodeSent;
  final String? initial;

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  late final _phone = TextEditingController(text: widget.initial);
  String? _phoneError;
  String? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final phone = PhoneNumber.tryParse(_phone.text);
    if (phone == null) {
      setState(() => _phoneError = l10n.authPhoneInvalid);
      return;
    }
    setState(() {
      _phoneError = null;
      _failure = null;
      _busy = true;
    });
    try {
      final ticket = await ref
          .read(authRepositoryProvider)
          .requestCode(phone, widget.purpose);
      if (mounted) widget.onCodeSent(phone, ticket);
    } on AuthFailure catch (f) {
      if (mounted) setState(() => _failure = authFailureText(l10n, f));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reset = widget.purpose == OtpPurpose.resetPassword;
    return AuthPage(
      title: reset ? l10n.authForgotTitle : l10n.authAttachTitle,
      body: reset ? l10n.authForgotBody : l10n.authAttachBody,
      children: [
        PhoneField(
          controller: _phone,
          errorText: _phoneError,
          onSubmitted: (_) => _busy ? null : _send(),
          onChanged: (_) {
            if (_phoneError != null) setState(() => _phoneError = null);
          },
        ),
        FailureNote(message: _failure),
        BusyButton(
          label: l10n.authSendCode,
          busy: _busy,
          onPressed: _busy ? null : _send,
        ),
      ],
    );
  }
}
