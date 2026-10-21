import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_mark.dart';
import '../booking/booking_widgets.dart';
import '../booking/payment_launcher.dart';
import '../home/home_scope.dart';
import '../recovery/recovery_repository.dart';
import 'companion_repository.dart';

/// The companion tab (PRD 6): terms at first use, then a chat with quick
/// replies, a way to the doctor, and urgent help always one tap away.
class CompanionScreen extends ConsumerWidget {
  const CompanionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agreed = ref.watch(companionConsentProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: AppMotion.of(context, AppMotion.medium),
          child: agreed
              ? const _Chat(key: ValueKey('chat'))
              : _Intro(
                  key: const ValueKey('intro'),
                  onAgree: () =>
                      ref.read(companionConsentProvider.notifier).accept(),
                ),
        ),
      ),
    );
  }
}

/// What the companion is and isn't, before the first message.
class _Intro extends StatelessWidget {
  const _Intro({super.key, required this.onAgree});

  final VoidCallback onAgree;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    Widget point(IconData icon, String line) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpace.md,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.teal50,
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: Icon(icon, color: AppColors.teal600, size: 22),
        ),
        Expanded(child: Text(line, style: text.bodyLarge)),
      ],
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screenHorizontal,
        AppSpace.xl,
        AppSpace.screenHorizontal,
        AppSpace.xl,
      ),
      children: [
        const Center(child: AppMark(size: 64)),
        const SizedBox(height: AppSpace.lg),
        Semantics(
          header: true,
          child: Text(
            l10n.companionIntroTitle,
            textAlign: TextAlign.center,
            style: text.headlineLarge,
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              spacing: AppSpace.lg,
              children: [
                point(Icons.chat_bubble_outline_rounded, l10n.companionIntroAi),
                point(
                  Icons.medical_services_outlined,
                  l10n.companionIntroNoDiagnosis,
                ),
                point(Icons.lock_outline_rounded, l10n.companionIntroPrivacy),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        FilledButton(onPressed: onAgree, child: Text(l10n.companionIntroAgree)),
      ],
    );
  }
}

class _Message {
  const _Message({
    required this.fromPatient,
    this.text,
    this.suggestBooking = false,
  });

  final bool fromPatient;

  /// Null for the greeting, which follows the app language.
  final String? text;
  final bool suggestBooking;
}

class _Chat extends ConsumerStatefulWidget {
  const _Chat({super.key});

  @override
  ConsumerState<_Chat> createState() => _ChatState();
}

class _ChatState extends ConsumerState<_Chat> {
  final _input = TextEditingController();
  final _messages = <_Message>[const _Message(fromPatient: false)];
  bool _waiting = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send(String text, {QuickReply? quick}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _waiting) return;
    final lang = Localizations.localeOf(context).languageCode;
    setState(() {
      _messages.add(_Message(fromPatient: true, text: trimmed));
      _waiting = true;
      _input.clear();
    });
    final reply = await ref
        .read(companionRepositoryProvider)
        .send(trimmed, languageCode: lang, quick: quick);
    if (!mounted) return;
    setState(() {
      _waiting = false;
      _messages.add(
        _Message(
          fromPatient: false,
          text: reply.text,
          suggestBooking: reply.suggestBooking,
        ),
      );
    });
    if (reply.crisis) unawaited(showCrisisSheet(context));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final quick = {
      QuickReply.craving: l10n.companionQuickCraving,
      QuickReply.breathing: l10n.companionQuickBreath,
      QuickReply.doctor: l10n.companionQuickDoctor,
    };
    final items = [if (_waiting) null, ..._messages.reversed];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenHorizontal,
            AppSpace.sm,
            AppSpace.md,
            AppSpace.sm,
          ),
          child: Row(
            spacing: AppSpace.md,
            children: [
              const AppMark(size: 40),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(l10n.companionTitle, style: text.titleLarge),
                    ),
                    Text(
                      l10n.companionSubtitle,
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textBody,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textStrong,
                ),
                onPressed: () => showCrisisSheet(context),
                icon: const Icon(
                  Icons.support_rounded,
                  color: AppColors.danger,
                ),
                label: Text(l10n.companionUrgent),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.screenHorizontal,
              vertical: AppSpace.lg,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final m = items[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: m == null
                    ? _Typing(label: l10n.companionTyping)
                    : _Bubble(
                        message: m,
                        greeting: l10n.companionGreeting,
                        onBook: () => HomeShellScope.maybeOf(
                          context,
                        )?.select(HomeTab.appointments),
                      ),
              );
            },
          ),
        ),
        if (!_waiting)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.screenHorizontal,
            ),
            child: Row(
              spacing: AppSpace.sm,
              children: [
                for (final e in quick.entries)
                  ActionChip(
                    label: Text(e.value),
                    side: const BorderSide(color: AppColors.teal500),
                    labelStyle: text.labelMedium?.copyWith(
                      color: AppColors.teal700,
                      fontWeight: FontWeight.w600,
                    ),
                    onPressed: () => _send(e.value, quick: e.key),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenHorizontal,
            AppSpace.sm,
            AppSpace.screenHorizontal,
            AppSpace.sm,
          ),
          child: Row(
            spacing: AppSpace.sm,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: l10n.companionHint,
                    contentPadding: const EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.md,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: const BorderSide(
                        color: AppColors.teal500,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton.filled(
                tooltip: l10n.companionSend,
                onPressed: _waiting ? null : () => _send(_input.text),
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenHorizontal,
            0,
            AppSpace.screenHorizontal,
            AppSpace.md,
          ),
          child: InfoLine(text: l10n.companionDisclaimer),
        ),
      ],
    );
  }
}

/// Companion messages sit on the start side on white; the patient's on the
/// end side in teal (DESIGN.md "Chat bubble").
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.greeting,
    required this.onBook,
  });

  final _Message message;
  final String greeting;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final me = message.fromPatient;
    const r = Radius.circular(AppRadius.card);
    const tail = Radius.circular(AppSpace.xs);

    return Align(
      alignment: me
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Column(
          crossAxisAlignment: me
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          spacing: AppSpace.sm,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.md,
              ),
              decoration: BoxDecoration(
                color: me ? AppColors.teal500 : AppColors.surface,
                border: me ? null : Border.all(color: AppColors.border),
                borderRadius: BorderRadiusDirectional.only(
                  topStart: me ? r : tail,
                  topEnd: me ? tail : r,
                  bottomStart: r,
                  bottomEnd: r,
                ),
              ),
              child: Text(
                message.text ?? greeting,
                style: text.bodyMedium?.copyWith(
                  color: me ? AppColors.onPrimary : AppColors.textStrong,
                ),
              ),
            ),
            if (message.suggestBooking)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                ),
                onPressed: onBook,
                icon: const Icon(Icons.event_available_rounded),
                label: Text(l10n.companionBook),
              ),
          ],
        ),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textBody),
      ),
    );
  }
}

/// Urgent help (PRD 6.3): call the clinic in one tap; emergency numbers to
/// confirm with the clinic before launch.
Future<void> showCrisisSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const _CrisisSheet(),
  );
}

class _CrisisSheet extends ConsumerWidget {
  const _CrisisSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final open = ref.read(openUrlProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screenHorizontal,
        0,
        AppSpace.screenHorizontal,
        AppSpace.xl,
      ),
      child: FutureBuilder(
        future: ref.read(recoveryRepositoryProvider).clinic(),
        builder: (context, snapshot) {
          final phone = snapshot.data?.phones.firstOrNull;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpace.md,
            children: [
              Text(l10n.crisisTitle, style: text.headlineMedium),
              Text(l10n.crisisBody, style: text.bodyLarge),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                onPressed: phone == null
                    ? null
                    : () => unawaited(
                        open(
                          Uri(scheme: 'tel', path: phone.replaceAll(' ', '')),
                        ),
                      ),
                icon: const Icon(Icons.call_rounded),
                label: Text(l10n.clinicCall),
              ),
              if (phone != null)
                Center(child: LtrText(phone, style: text.bodyMedium)),
              Text(l10n.crisisEmergency, style: text.bodyMedium),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.crisisClose),
              ),
            ],
          );
        },
      ),
    );
  }
}
