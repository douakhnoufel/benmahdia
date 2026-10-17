import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import 'auth_models.dart';
import 'auth_repository.dart';
import 'auth_widgets.dart';
import 'phone_number.dart';

/// The 6-digit SMS code. Checks itself as soon as the last digit is typed
/// (or filled from the SMS), and offers a new code after the wait.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({
    super.key,
    required this.phone,
    required this.purpose,
    required this.ticket,
    required this.onVerified,
  });

  final PhoneNumber phone;
  final OtpPurpose purpose;
  final OtpTicket ticket;

  /// Receives the server's proof that this number got the code and uses
  /// it (e.g. creates the account). May throw [AuthFailure], shown here.
  final Future<void> Function(String proof) onVerified;

  static const length = 6;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _tick = Duration(seconds: 1);

  final _code = TextEditingController();
  final _focus = FocusNode();
  late Duration _wait = widget.ticket.resendAfter;
  Timer? _timer;
  String? _failure;
  bool _checking = false;
  bool _resending = false;

  /// A new code must be asked for before trying again.
  bool _dead = false;

  @override
  void initState() {
    super.initState();
    _startWait(widget.ticket.resendAfter);
  }

  void _startWait(Duration wait) {
    _timer?.cancel();
    _wait = wait;
    _timer = Timer.periodic(_tick, (timer) {
      setState(() => _wait -= _tick);
      if (_wait <= Duration.zero) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _failure = null);
    if (value.length == OtpScreen.length && !_dead) unawaited(_check(value));
  }

  Future<void> _check(String code) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _checking = true);
    try {
      final proof = await ref
          .read(authRepositoryProvider)
          .verifyCode(widget.phone, widget.purpose, _ascii(code));
      if (mounted) await widget.onVerified(proof);
    } on AuthFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _failure = authFailureText(l10n, f);
        _dead = f is CodeExpired || f is TooManyAttempts;
        _code.clear();
      });
      if (!_dead) _focus.requestFocus();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _resending = true;
      _failure = null;
    });
    try {
      final ticket = await ref
          .read(authRepositoryProvider)
          .requestCode(widget.phone, widget.purpose);
      if (!mounted) return;
      setState(() {
        _dead = false;
        _code.clear();
      });
      _startWait(ticket.resendAfter);
      _focus.requestFocus();
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.authOtpResent)));
    } on AuthFailure catch (f) {
      if (!mounted) return;
      setState(() => _failure = authFailureText(l10n, f));
      if (f case RateLimited(:final retryAfter)) _startWait(retryAfter);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final waiting = _wait > Duration.zero;
    return AuthPage(
      title: l10n.authOtpTitle,
      body: l10n.authOtpBody(widget.phone.isolated),
      children: [
        _CodeBoxes(
          controller: _code,
          focus: _focus,
          enabled: !_checking && !_dead,
          error: _failure != null,
          onChanged: _onChanged,
        ),
        FailureNote(message: _failure),
        if (_checking)
          const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Center(
          child: waiting
              ? Text(
                  l10n.authOtpResendIn(_clock(_wait)),
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                )
              : TextButton.icon(
                  onPressed: _resending ? null : _resend,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.authOtpResend),
                ),
        ),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.authOtpChangeNumber),
          ),
        ),
      ],
    );
  }
}

/// "0:42", kept left-to-right.
String _clock(Duration d) {
  final s = d.inSeconds.clamp(0, 3600);
  return '\u2066${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}\u2069';
}

String _ascii(String code) => String.fromCharCodes(
  code.runes.map((r) => r >= 0x0660 && r <= 0x0669 ? r - 0x0660 + 0x30 : r),
);

/// Six boxes over one real text field, so paste, SMS autofill and screen
/// readers all work on a normal input.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.error,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final bool error;
  final ValueChanged<String> onChanged;

  static const _boxHeight = 60.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: _boxHeight,
        child: Stack(
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([controller, focus]),
              builder: (context, _) {
                final value = controller.text;
                return Row(
                  spacing: AppSpace.sm,
                  children: [
                    for (var i = 0; i < OtpScreen.length; i++)
                      Expanded(
                        child: _Box(
                          digit: i < value.length ? value[i] : null,
                          active:
                              focus.hasFocus &&
                              (i == value.length ||
                                  (i == OtpScreen.length - 1 &&
                                      value.length == OtpScreen.length)),
                          error: error,
                          style: text.headlineMedium,
                        ),
                      ),
                  ],
                );
              },
            ),
            Positioned.fill(
              child: Semantics(
                label: l10n.authOtpSemantics,
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  enabled: enabled,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩]')),
                    LengthLimitingTextInputFormatter(OtpScreen.length),
                  ],
                  onChanged: onChanged,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  style: const TextStyle(color: Colors.transparent),
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.digit,
    required this.active,
    required this.error,
    required this.style,
  });

  final String? digit;
  final bool active;
  final bool error;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final border = error
        ? AppColors.danger
        : active
        ? AppColors.teal500
        : digit != null
        ? AppColors.teal200
        : AppColors.border;
    return AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.fast),
      curve: AppMotion.curve,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: digit != null ? AppColors.teal50 : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: border, width: active || error ? 2 : 1),
      ),
      child: AnimatedSwitcher(
        duration: AppMotion.of(context, AppMotion.fast),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: AppMotion.pop),
          child: child,
        ),
        child: Text(
          digit ?? '',
          key: ValueKey(digit),
          style: style?.copyWith(
            color: AppColors.textStrong,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
