import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/locale_provider.dart';
import '../../theme/app_tokens.dart';
import 'auth_models.dart';
import 'auth_repository.dart';
import 'login_screen.dart';
import 'otp_screen.dart';
import 'password_screen.dart';
import 'phone_entry_screen.dart';
import 'phone_number.dart';
import 'sign_up_screen.dart';

/// Opens sign-up (PRD 12.1). Phone: number → SMS code → password.
/// Google / Apple: sign in, then confirm a phone number if the account has
/// none. [onSignedIn] runs once the account screens are closed.
void openSignUp(
  BuildContext context, {
  required ValueChanged<AuthSession> onSignedIn,
}) => _AuthFlow(context, onSignedIn).start(signUp: true);

/// Opens login: phone + password (with a reset by SMS code), or Google /
/// Apple.
void openLogin(
  BuildContext context, {
  required ValueChanged<AuthSession> onSignedIn,
}) => _AuthFlow(context, onSignedIn).start(signUp: false);

class _AuthFlow {
  _AuthFlow(BuildContext context, this.onSignedIn)
    : _navigator = Navigator.of(context),
      _base = ModalRoute.of(context),
      _reduced = AppMotion.reduced(context),
      _container = ProviderScope.containerOf(context, listen: false);

  final ValueChanged<AuthSession> onSignedIn;
  final NavigatorState _navigator;
  final Route<dynamic>? _base;
  final bool _reduced;
  final ProviderContainer _container;

  AuthRepository get _repo => _container.read(authRepositoryProvider);
  String get _language => _container.read(localeProvider).languageCode;

  void start({required bool signUp}) =>
      _push(signUp ? _signUpPage() : _loginPage());

  void _push(Widget page) =>
      unawaited(_navigator.push<void>(appRoute(page, reduced: _reduced)));

  void _replace(Widget page) => unawaited(
    _navigator.pushReplacement<void, void>(appRoute(page, reduced: _reduced)),
  );

  /// Closes every account screen, then hands over.
  void _done(AuthSession session) {
    _container.read(sessionProvider.notifier).set(session);
    _navigator.popUntil(
      (route) => _base == null ? route.isFirst : route == _base,
    );
    onSignedIn(session);
  }

  /// After Google / Apple: a number is still needed so the clinic can reach
  /// the patient, confirmed by SMS like any other.
  void _afterSignIn(AuthSession session) {
    if (session.user.phone != null) return _done(session);
    _push(
      PhoneEntryScreen(
        purpose: OtpPurpose.attachPhone,
        onCodeSent: (phone, ticket) => _code(
          phone,
          OtpPurpose.attachPhone,
          ticket,
          (proof) async => _done(await _repo.attachPhone(session, proof)),
        ),
      ),
    );
  }

  void _code(
    PhoneNumber phone,
    OtpPurpose purpose,
    OtpTicket ticket,
    Future<void> Function(String proof) onVerified,
  ) => _push(
    OtpScreen(
      phone: phone,
      purpose: purpose,
      ticket: ticket,
      onVerified: onVerified,
    ),
  );

  Widget _signUpPage() => SignUpScreen(
    onCodeSent: (phone, ticket) => _code(
      phone,
      OtpPurpose.signUp,
      ticket,
      (proof) async => _push(
        PasswordScreen(
          mode: PasswordMode.create,
          onSubmit: (password) async => _done(
            await _repo.register(
              phoneProof: proof,
              password: password,
              language: _language,
            ),
          ),
        ),
      ),
    ),
    onSignedIn: _afterSignIn,
    onLogin: () => _replace(_loginPage()),
  );

  Widget _loginPage() => LoginScreen(
    onSignedIn: _afterSignIn,
    onCreateAccount: () => _replace(_signUpPage()),
    onForgot: (typed) => _push(
      PhoneEntryScreen(
        purpose: OtpPurpose.resetPassword,
        initial: typed,
        onCodeSent: (phone, ticket) => _code(
          phone,
          OtpPurpose.resetPassword,
          ticket,
          (proof) async => _push(
            PasswordScreen(
              mode: PasswordMode.reset,
              onSubmit: (password) async => _done(
                await _repo.resetPassword(
                  phoneProof: proof,
                  password: password,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
