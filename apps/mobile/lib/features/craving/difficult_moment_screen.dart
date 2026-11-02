import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/local_store.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/sharing_label.dart';
import '../booking/booking_widgets.dart';
import '../booking/payment_launcher.dart';
import '../companion/companion_screen.dart';
import '../recovery/recovery_models.dart';
import '../recovery/recovery_repository.dart';
import 'breathing_circle.dart';
import 'craving_models.dart';
import 'craving_repository.dart';

enum _Step { start, breathe, rate, done }

/// "I'm having a difficult moment" (habit-tracking design, step 1): rate the
/// craving, name what is behind it, breathe, try a tip, then say it passed.
/// The log is saved on the server and the doctor sees it.
class DifficultMomentScreen extends ConsumerStatefulWidget {
  const DifficultMomentScreen({super.key, this.now});

  /// Current time; injected so tests control the opening-hours check.
  final DateTime Function()? now;

  @override
  ConsumerState<DifficultMomentScreen> createState() =>
      _DifficultMomentScreenState();
}

class _DifficultMomentScreenState extends ConsumerState<DifficultMomentScreen> {
  static const _tipCount = 4;

  _Step _step = _Step.start;
  double _before = 5;
  double _after = 3;
  final _triggers = <HaltTrigger>{};
  CravingLog? _log;
  bool _busy = false;
  late int _tip = (widget.now ?? DateTime.now)().day % _tipCount;
  String? _plan;
  ClinicInfo? _clinic;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAround());
  }

  Future<void> _loadAround() async {
    unawaited(_loadClinic());
    final plan = await LocalStore.readIfThenPlan();
    if (!mounted) return;
    setState(() => _plan = plan);
  }

  Future<void> _loadClinic() async {
    try {
      final clinic = await ref.read(recoveryRepositoryProvider).clinic();
      if (!mounted) return;
      setState(() => _clinic = clinic);
    } catch (_) {
      // The card is left out; urgent help still has the number.
    }
  }

  void _error() {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.recoverySaveError)));
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final log = await ref
          .read(cravingRepositoryProvider)
          .start(_before.round(), _triggers.toList());
      if (!mounted) return;
      setState(() {
        _log = log;
        _step = _Step.breathe;
      });
    } on CravingUnavailable {
      // Not saved, but the help must still open.
      if (!mounted) return;
      _error();
      setState(() => _step = _Step.breathe);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final log = _log;
    if (log == null) {
      setState(() => _step = _Step.done);
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(cravingRepositoryProvider)
          .passed(log.id, _after.round());
      if (!mounted) return;
      setState(() {
        _log = saved;
        _step = _Step.done;
      });
    } on CravingUnavailable {
      if (mounted) _error();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editPlan() async {
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlanSheet(initial: _plan ?? ''),
    );
    if (saved == null) return;
    await LocalStore.writeIfThenPlan(saved);
    if (!mounted) return;
    setState(() => _plan = saved.trim().isEmpty ? null : saved.trim());
  }

  bool _isOpen(ClinicInfo clinic) {
    final now = (widget.now ?? DateTime.now)();
    final minutes = now.hour * 60 + now.minute;
    return clinic.hoursOn(now).any((h) => minutes >= h.from && minutes < h.to);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text(l10n.momentTitle)),
        actions: [
          TextButton.icon(
            onPressed: () => unawaited(showCrisisSheet(context)),
            icon: const Icon(Icons.emergency_outlined, color: AppColors.danger),
            label: Text(
              l10n.momentUrgent,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenHorizontal,
            AppSpace.lg,
            AppSpace.screenHorizontal,
            AppSpace.xl,
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpace.sectionGap,
              children: [
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SharingLabel(SharingKind.doctor),
                ),
                ...switch (_step) {
                  _Step.start => _startView(l10n, text),
                  _Step.breathe => _breatheView(l10n, text),
                  _Step.rate => _rateView(l10n, text),
                  _Step.done => _doneView(l10n, text),
                },
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(double value, ValueChanged<double> onChanged, String label) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: text.titleMedium),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value,
                min: 1,
                max: 10,
                divisions: 9,
                label: value.round().toString(),
                semanticFormatterCallback: (v) => v.round().toString(),
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 32,
              child: LtrText(
                value.round().toString(),
                style: text.headlineSmall,
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _startView(AppLocalizations l10n, TextTheme text) {
    final names = {
      HaltTrigger.hungry: l10n.momentTriggerHungry,
      HaltTrigger.angry: l10n.momentTriggerAngry,
      HaltTrigger.lonely: l10n.momentTriggerLonely,
      HaltTrigger.tired: l10n.momentTriggerTired,
      HaltTrigger.other: l10n.momentTriggerOther,
    };
    return [
      _slider(
        _before,
        (v) => setState(() => _before = v),
        l10n.momentHowStrong,
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpace.sm,
        children: [
          Text(l10n.momentTriggersTitle, style: text.titleMedium),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final t in HaltTrigger.values)
                FilterChip(
                  label: Text(names[t]!),
                  selected: _triggers.contains(t),
                  onSelected: (on) => setState(() {
                    on ? _triggers.add(t) : _triggers.remove(t);
                  }),
                ),
            ],
          ),
        ],
      ),
      FilledButton(
        onPressed: _busy ? null : _start,
        child: Text(l10n.momentStart),
      ),
    ];
  }

  List<Widget> _breatheView(AppLocalizations l10n, TextTheme text) {
    final tips = [
      l10n.momentTip1,
      l10n.momentTip2,
      l10n.momentTip3,
      l10n.momentTip4,
    ];
    final clinic = _clinic;
    final phone = clinic?.phones.firstOrNull;
    final open = ref.read(openUrlProvider);
    return [
      Text(
        l10n.momentBreathe,
        textAlign: TextAlign.center,
        style: text.titleMedium,
      ),
      const BreathingCircle(),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpace.sm,
            children: [
              Text(l10n.momentTipTitle, style: text.titleMedium),
              Text(tips[_tip % _tipCount], style: text.bodyLarge),
              TextButton(
                onPressed: () => setState(() => _tip = (_tip + 1) % _tipCount),
                child: Text(l10n.momentTipAnother),
              ),
            ],
          ),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpace.sm,
            children: [
              Row(
                spacing: AppSpace.sm,
                children: [
                  Expanded(
                    child: Text(l10n.momentPlanTitle, style: text.titleMedium),
                  ),
                  const SharingLabel(SharingKind.onlyYou),
                ],
              ),
              Text(
                _plan ?? l10n.momentPlanEmpty,
                style: text.bodyLarge?.copyWith(
                  color: _plan == null ? AppColors.textMuted : null,
                ),
              ),
              TextButton(
                onPressed: _editPlan,
                child: Text(l10n.momentPlanEdit),
              ),
            ],
          ),
        ),
      ),
      if (clinic != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpace.sm,
              children: [
                Text(
                  _isOpen(clinic)
                      ? l10n.momentClinicOpen
                      : l10n.momentClinicClosed,
                  style: text.bodyMedium,
                ),
                OutlinedButton.icon(
                  onPressed: phone == null
                      ? null
                      : () => unawaited(
                          open(
                            Uri(scheme: 'tel', path: phone.replaceAll(' ', '')),
                          ),
                        ),
                  icon: const Icon(Icons.call_rounded),
                  label: Text(l10n.momentCallClinic),
                ),
              ],
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => unawaited(
          Navigator.of(context).push<void>(
            appRoute(
              const CompanionScreen(),
              reduced: AppMotion.reduced(context),
            ),
          ),
        ),
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        label: Text(l10n.momentCompanion),
      ),
      FilledButton(
        onPressed: () => setState(() => _step = _Step.rate),
        child: Text(l10n.momentPassed),
      ),
    ];
  }

  List<Widget> _rateView(AppLocalizations l10n, TextTheme text) => [
    _slider(_after, (v) => setState(() => _after = v), l10n.momentHowNow),
    FilledButton(onPressed: _busy ? null : _save, child: Text(l10n.momentSave)),
  ];

  List<Widget> _doneView(AppLocalizations l10n, TextTheme text) {
    final log = _log;
    return [
      Semantics(
        header: true,
        child: Text(l10n.momentDoneTitle, style: text.headlineMedium),
      ),
      Text(l10n.momentDoneBody, style: text.bodyLarge),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Score(l10n.momentBefore, log?.before ?? _before.round()),
              const Icon(Icons.arrow_forward_rounded),
              _Score(l10n.momentAfter, log?.after ?? _after.round()),
            ],
          ),
        ),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.momentClose),
      ),
    ];
  }
}

class _Score extends StatelessWidget {
  const _Score(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(label, style: text.bodyMedium),
        LtrText(
          '$value',
          style: text.displaySmall?.copyWith(color: AppColors.teal700),
        ),
      ],
    );
  }
}

class _PlanSheet extends StatefulWidget {
  const _PlanSheet({required this.initial});

  final String initial;

  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screenHorizontal,
        0,
        AppSpace.screenHorizontal,
        MediaQuery.viewInsetsOf(context).bottom + AppSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpace.md,
        children: [
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: SharingLabel(SharingKind.onlyYou),
          ),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: 200,
            decoration: InputDecoration(hintText: l10n.momentPlanHint),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: Text(l10n.momentPlanSave),
          ),
        ],
      ),
    );
  }
}
