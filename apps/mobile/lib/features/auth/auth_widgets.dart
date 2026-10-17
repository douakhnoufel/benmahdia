import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/lang_toggle.dart';
import '../../widgets/staggered_reveal.dart';
import 'auth_models.dart';
import 'password_rules.dart';

/// Layout shared by the account screens: back (and the language switch on
/// entry screens), a title and a short line, the form, then [footer].
class AuthPage extends StatelessWidget {
  const AuthPage({
    super.key,
    required this.title,
    required this.body,
    required this.children,
    this.footer,
    this.showLanguage = false,
  });

  final String title;
  final String body;
  final List<Widget> children;
  final Widget? footer;
  final bool showLanguage;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screenHorizontal,
                AppSpace.sm,
                AppSpace.screenHorizontal,
                AppSpace.xl,
              ),
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      if (canPop) const BackButton(color: AppColors.textStrong),
                      const Spacer(),
                      if (showLanguage)
                        const SizedBox(width: 150, child: LangToggle()),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Semantics(
                  header: true,
                  child: Text(title, style: text.headlineLarge),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(body, style: text.bodyLarge),
                const SizedBox(height: AppSpace.xl),
                StaggeredReveal(spacing: AppSpace.md, children: children),
                if (footer != null) ...[
                  const SizedBox(height: AppSpace.xl),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Algerian mobile number. Digits stay left-to-right in Arabic too.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    this.errorText,
    this.onSubmitted,
    this.onChanged,
    this.textInputAction = TextInputAction.done,
  });

  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: controller,
      textDirection: TextDirection.ltr,
      keyboardType: TextInputType.phone,
      textInputAction: textInputAction,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩+ ]')),
        LengthLimitingTextInputFormatter(17),
      ],
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: l10n.authPhoneLabel,
        hintText: '0550 12 34 56',
        hintTextDirection: TextDirection.ltr,
        errorText: errorText,
        errorMaxLines: 3,
        prefixIcon: const Icon(Icons.phone_iphone_rounded),
      ),
    );
  }
}

/// Password with a show / hide eye.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
    this.onSubmitted,
    this.newPassword = false,
    this.textInputAction = TextInputAction.done,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Asks the keyboard / password manager for a new password, not a saved
  /// one.
  final bool newPassword;
  final TextInputAction textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: widget.controller,
      obscureText: _hidden,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: widget.textInputAction,
      autofillHints: [
        widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: _hidden ? l10n.authPasswordShow : l10n.authPasswordHide,
          onPressed: () => setState(() => _hidden = !_hidden),
          icon: Icon(
            _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

/// Live checklist under a new password: each rule turns green with a tick,
/// so colour is never the only signal.
class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({
    super.key,
    required this.password,
    required this.confirm,
  });

  final String password;
  final String confirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rules = [
      (l10n.authRuleLength, PasswordRule.length.isMetBy(password)),
      (l10n.authRuleLetter, PasswordRule.letter.isMetBy(password)),
      (l10n.authRuleDigit, PasswordRule.digit.isMetBy(password)),
      (l10n.authRuleMatch, password.isNotEmpty && password == confirm),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.xs,
      children: [
        for (final (label, met) in rules) _Rule(label: label, met: met),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = met ? AppColors.success : AppColors.textMuted;
    return Semantics(
      container: true,
      label: met ? l10n.authRuleOk(label) : l10n.authRuleTodo(label),
      excludeSemantics: true,
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.fast),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: CurvedAnimation(parent: animation, curve: AppMotion.pop),
              child: child,
            ),
            child: Icon(
              met
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              key: ValueKey(met),
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: met ? AppColors.textStrong : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "— or —" between the phone form and Google / Apple.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Text(
              AppLocalizations.of(context).authOr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

enum SocialProvider { google, apple }

/// Google and Apple buttons, styled as their guidelines require (Google:
/// white with a grey outline; Apple: black). Equal size and weight.
class SocialButton extends StatelessWidget {
  const SocialButton({
    super.key,
    required this.provider,
    required this.onPressed,
    this.busy = false,
  });

  final SocialProvider provider;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final google = provider == SocialProvider.google;
    final fg = google ? AppColors.googleText : AppColors.appleText;
    final label = google ? l10n.authGoogle : l10n.authApple;
    return OutlinedButton(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: google
            ? AppColors.googleSurface
            : AppColors.appleSurface,
        disabledBackgroundColor: google
            ? AppColors.googleSurface
            : AppColors.appleSurface,
        foregroundColor: fg,
        disabledForegroundColor: fg,
        side: BorderSide(
          color: google ? AppColors.googleBorder : AppColors.appleSurface,
        ),
      ),
      child: busy
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // TODO(brand): add Google's official "G" mark from its
                // branding kit as an asset here; Apple's mark is below.
                if (!google) ...[
                  const Icon(Icons.apple, size: 22),
                  const SizedBox(width: AppSpace.sm),
                ],
                Flexible(child: Text(label)),
              ],
            ),
    );
  }
}

/// A filled button that shows a spinner while [busy].
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.onPrimary,
              ),
            )
          : Text(label),
    );
  }
}

/// An error under a form, with an icon so it is not colour alone. Read out
/// by screen readers when it appears.
class FailureNote extends StatelessWidget {
  const FailureNote({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    return AnimatedSize(
      duration: AppMotion.of(context, AppMotion.fast),
      curve: AppMotion.curve,
      alignment: AlignmentDirectional.topStart,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.danger),
                  borderRadius: BorderRadius.circular(AppRadius.field),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 20,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textStrong,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// "Question? Action" line at the bottom of a screen.
class SwitchLine extends StatelessWidget {
  const SwitchLine({
    super.key,
    required this.question,
    required this.action,
    required this.onPressed,
  });

  final String question;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: Theme.of(context).textTheme.bodyMedium),
        TextButton(onPressed: onPressed, child: Text(action)),
      ],
    );
  }
}

/// What to tell the patient for [failure]; null when there is nothing to
/// say (they cancelled).
String? authFailureText(AppLocalizations l10n, AuthFailure failure) =>
    switch (failure) {
      PhoneTaken() => l10n.authPhoneTaken,
      WrongCode() => l10n.authOtpWrong,
      CodeExpired() => l10n.authOtpExpired,
      TooManyAttempts() => l10n.authOtpTooMany,
      WrongCredentials() => l10n.authWrongCredentials,
      AccountLocked(:final retryAfter) => l10n.authLocked(_minutes(retryAfter)),
      RateLimited(:final retryAfter) => l10n.authRateLimited(
        retryAfter.inSeconds.clamp(1, 3600),
      ),
      NetworkFailure() => l10n.authNetwork,
      SocialUnavailable() => l10n.authSocialUnavailable,
      SignInCancelled() => null,
    };

int _minutes(Duration d) => (d.inSeconds / 60).ceil().clamp(1, 24 * 60);
