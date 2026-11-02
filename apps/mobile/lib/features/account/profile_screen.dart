import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locale_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import 'account_models.dart';
import 'account_repository.dart';
import 'sign_out.dart';

/// Profile & Settings: the patient's number, contact email, ID status,
/// language, and sign-out. The server is the authority for every value.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final me = ref.watch(meProvider);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.screenHorizontal,
          vertical: AppSpace.lg,
        ),
        children: [
          Text(l10n.accountTitle, style: text.headlineMedium),
          const SizedBox(height: AppSpace.sectionGap),
          switch (me) {
            AsyncData(:final value) => _AccountCard(me: value),
            AsyncError() => _LoadFailed(
              onRetry: () => ref.invalidate(meProvider),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
          const SizedBox(height: AppSpace.sectionGap),
          const _SettingsCard(),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: AppColors.border),
          children[i],
        ],
      ],
    ),
  );
}

/// A settings row (DESIGN: 56 high, leading icon teal.600, trailing chevron).
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.value,
    this.valueLtr = false,
    this.onTap,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? value;
  final bool valueLtr;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          child: Row(
            children: [
              Icon(icon, color: color ?? AppColors.teal600),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyMedium?.copyWith(
                        color: color ?? AppColors.textStrong,
                      ),
                    ),
                    if (value case final v?)
                      Text(
                        v,
                        textDirection: valueLtr ? TextDirection.ltr : null,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                // Points to the reading end, also in Arabic.
                Transform.flip(
                  flipX: Directionality.of(context) == TextDirection.rtl,
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return _Card(
      children: [
        _Row(
          icon: Icons.phone_rounded,
          title: l10n.profilePhone,
          value: me.phone ?? l10n.profileNone,
          valueLtr: me.phone != null,
        ),
        _Row(
          icon: Icons.mail_outline_rounded,
          title: l10n.profileEmail,
          value: me.email ?? l10n.profileNone,
          valueLtr: me.email != null,
          onTap: () => _editEmail(context, ref, me.email),
        ),
        _Row(
          icon: Icons.badge_outlined,
          title: l10n.profileIdStatus,
          value: switch (me.idStatus) {
            MeIdStatus.none => l10n.profileIdNone,
            MeIdStatus.declared => l10n.accountIdDeclared,
            MeIdStatus.approved => l10n.profileIdApproved,
            MeIdStatus.rejected => l10n.profileIdRejected,
          },
        ),
      ],
    );
  }
}

Future<void> _editEmail(
  BuildContext context,
  WidgetRef ref,
  String? current,
) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _EmailDialog(initial: current ?? ''),
  );
  if (saved == true) ref.invalidate(meProvider);
}

class _EmailDialog extends ConsumerStatefulWidget {
  const _EmailDialog({required this.initial});

  final String initial;

  @override
  ConsumerState<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends ConsumerState<_EmailDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountRepositoryProvider).setEmail(_controller.text);
      if (!mounted) return;
      navigator.pop(true);
    } on InvalidEmail {
      if (!mounted) return;
      setState(() => _error = l10n.profileEmailInvalid);
    } on AccountFailure {
      if (!mounted) return;
      setState(() => _error = l10n.profileSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.profileEmail),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.profileEmailHint),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            autofocus: true,
            decoration: InputDecoration(errorText: _error),
            onSubmitted: (_) => _busy ? null : unawaited(_save()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.profileCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_save()),
          child: Text(l10n.profileSave),
        ),
      ],
    );
  }
}

class _SettingsCard extends ConsumerStatefulWidget {
  const _SettingsCard();

  @override
  ConsumerState<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends ConsumerState<_SettingsCard> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    await signOut(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(localeProvider).languageCode;
    return _Card(
      children: [
        _Row(
          icon: Icons.translate_rounded,
          title: l10n.profileLanguage,
          value: current == 'ar' ? l10n.langArabic : l10n.langFrench,
          onTap: () => ref
              .read(localeProvider.notifier)
              .set(Locale(current == 'ar' ? 'fr' : 'ar')),
        ),
        _Row(
          icon: Icons.logout_rounded,
          title: l10n.logout,
          color: AppColors.danger,
          onTap: _signingOut ? null : () => unawaited(_signOut()),
        ),
      ],
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Card(
      children: [
        _Row(
          icon: Icons.cloud_off_rounded,
          title: l10n.profileLoadFailed,
          value: l10n.profileRetry,
          onTap: onRetry,
        ),
      ],
    );
  }
}
