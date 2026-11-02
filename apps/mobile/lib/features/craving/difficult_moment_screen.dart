import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/local_store.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/sharing_label.dart';
import '../booking/payment_launcher.dart';
import '../companion/companion_screen.dart';
import '../home/home_scope.dart';
import '../recovery/recovery_models.dart';
import '../recovery/recovery_repository.dart';
import 'breathing_circle.dart';
import 'craving_models.dart';
import 'craving_repository.dart';

/// "I am having a difficult moment" (habit-tracking design, step 1): the
/// patient says how strong the craving is and what is behind it (HALT),
/// breathes through it with one tip to try, their own if-then plan and a way
/// to reach the clinic or the companion, then marks it passed and sees the
/// intensity before and after. Urgent help stays within reach throughout.
///
/// The craving log is saved on the server, so the doctor sees it (PRD 3);
/// the if-then plan stays on the phone. Nothing the patient types is sent.
class DifficultMomentScreen extends ConsumerStatefulWidget {
  const DifficultMomentScreen({super.key});

  @override
  ConsumerState<DifficultMomentScreen> createState() =>
      _DifficultMomentScreenState();
}

/// How far the patient is through the moment.
enum _Stage { start, surfing, closing, passed }

class _DifficultMomentScreenState extends ConsumerState<DifficultMomentScreen> {
  _Stage _stage = _Stage.start;
  int? _before;
  int? _after;
  final _triggers = <CravingTrigger>{};
  CravingLog? _log;
  bool _saving = false;

  /// Which of the four tips is on screen; the patient can ask for another.
  int _tip = 0;

  IfThenPlan _plan = const IfThenPlan.empty();
  final _when = TextEditingController();
  final _then = TextEditingController();
  bool _editingPlan = false;

  /// Loaded once: a failure here only hides the clinic line.
  late final Future<ClinicInfo?> _clinic = _loadClinic();

  CravingRepository get _repo => ref.read(cravingRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlan());
  }

  @override
  void dispose() {
    _when.dispose();
    _then.dispose();
    super.dispose();
  }

  Future<ClinicInfo?> _loadClinic() async {
    try {
      return await ref.read(recoveryRepositoryProvider).clinic();
    } on Object {
      return null;
    }
  }

  Future<void> _loadPlan() async {
    final saved = await LocalStore.readIfThenPlan();
    if (!mounted || saved == null) return;
    setState(() {
      _plan = saved;
      _when.text = saved.when;
      _then.text = saved.then;
    });
  }

  void _savePlan() {
    final plan = IfThenPlan(when: _when.text.trim(), then: _then.text.trim());
    final l10n = AppLocalizations.of(context);
    setState(() {
      _plan = plan;
      _editingPlan = false;
    });
    // The store swallows storage errors itself, as everywhere else the app
    // saves to the phone (locale, session), so the plan goes out without
    // holding up the screen.
    unawaited(LocalStore.writeIfThenPlan(plan).catchError((Object _) {}));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.momentPlanSaved)));
  }

  /// Logs the craving, then moves on to breathing. A failure keeps the
  /// patient where they are with a retry, never an empty screen.
  Future<void> _start() async {
    final intensity = _before;
    if (intensity == null || _saving) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final log = await _repo.start(
        intensity: intensity,
        triggers: _triggers.toList(),
      );
      if (!mounted) return;
      setState(() {
        _log = log;
        _stage = _Stage.surfing;
        _saving = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.recoverySaveError)));
    }
  }

  /// Records how strong the craving is now. A log the server already closed
  /// is not an error for the patient: the moment is over either way.
  Future<void> _markPassed() async {
    final log = _log;
    final intensity = _after;
    if (log == null || intensity == null || _saving) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final closed = await _repo.markPassed(log, intensity: intensity);
      if (!mounted) return;
      setState(() {
        _log = closed;
        _stage = _Stage.passed;
        _saving = false;
      });
    } on CravingAlreadyPassed {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.passed;
        _saving = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.recoverySaveError)));
    }
  }

  void _openCompanion() {
    final shell = HomeShellScope.maybeOf(context);
    Navigator.of(context).pop();
    shell?.select(HomeTab.companion);
  }

  /// True while the clinic is inside today's opening hours.
  static bool _openNow(ClinicInfo clinic, DateTime now) {
    final minutes = now.hour * 60 + now.minute;
    return clinic.hoursOn(now).any((h) => minutes >= h.from && minutes < h.to);
  }

  List<String> _tips(AppLocalizations l10n) => [
    l10n.momentTipSpicy,
    l10n.momentTipGum,
    l10n.momentTipWater,
    l10n.momentTipWalk,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(l10n.momentTitle, style: text.titleLarge),
        actions: [
          // Urgent help stays reachable at every stage (PRD 6.3).
          TextButton(
            onPressed: () => unawaited(showCrisisSheet(context)),
            child: Text(l10n.momentUrgent),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screenHorizontal,
          0,
          AppSpace.screenHorizontal,
          AppSpace.xl,
        ),
        children: switch (_stage) {
          _Stage.start => _startStage(l10n, text),
          _Stage.surfing => _surfingStage(l10n, text),
          _Stage.closing => _closingStage(l10n, text),
          _Stage.passed => _passedStage(l10n, text),
        },
      ),
    );
  }

  // --- stages ---------------------------------------------------------------

  List<Widget> _startStage(AppLocalizations l10n, TextTheme text) => [
    Semantics(
      header: true,
      child: Text(l10n.momentStartTitle, style: text.headlineMedium),
    ),
    const SizedBox(height: AppSpace.xs),
    const SharingLabel(sharing: Sharing.doctorSees),
    const SizedBox(height: AppSpace.lg),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.lg,
          children: [
            IntensityScale(
              label: l10n.momentIntensityBefore,
              value: _before,
              onChanged: (v) => setState(() => _before = v),
            ),
            _Triggers(
              selected: _triggers,
              onToggle: (t) => setState(() {
                if (!_triggers.remove(t)) _triggers.add(t);
              }),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: AppSpace.lg),
    if (_before == null)
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Text(
          l10n.momentNeedIntensity,
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ),
    FilledButton(
      onPressed: _before == null || _saving ? null : () => unawaited(_start()),
      child: Text(l10n.momentStart),
    ),
  ];

  List<Widget> _surfingStage(AppLocalizations l10n, TextTheme text) => [
    const SizedBox(height: AppSpace.lg),
    const Center(child: BreathingCircle()),
    const SizedBox(height: AppSpace.lg),
    Text(
      l10n.momentSurfBody,
      textAlign: TextAlign.center,
      style: text.bodyLarge?.copyWith(color: AppColors.textBody),
    ),
    const SizedBox(height: AppSpace.lg),
    _TipCard(
      tip: _tips(l10n)[_tip % 4],
      onAnother: () => setState(() => _tip = (_tip + 1) % 4),
    ),
    const SizedBox(height: AppSpace.cardGap),
    _PlanCard(
      plan: _plan,
      editing: _editingPlan,
      when: _when,
      then: _then,
      onEdit: () => setState(() => _editingPlan = true),
      onSave: _savePlan,
    ),
    const SizedBox(height: AppSpace.cardGap),
    FutureBuilder<ClinicInfo?>(
      future: _clinic,
      builder: (context, snapshot) {
        final clinic = snapshot.data;
        if (clinic == null) return const SizedBox.shrink();
        return _ClinicReach(
          clinic: clinic,
          open: _openNow(clinic, _repo.now()),
        );
      },
    ),
    const SizedBox(height: AppSpace.cardGap),
    OutlinedButton.icon(
      onPressed: _openCompanion,
      icon: const Icon(Icons.forum_outlined),
      label: Text(l10n.momentCompanion),
    ),
    const SizedBox(height: AppSpace.xl),
    FilledButton(
      onPressed: () => setState(() => _stage = _Stage.closing),
      child: Text(l10n.momentPassedAction),
    ),
  ];

  List<Widget> _closingStage(AppLocalizations l10n, TextTheme text) => [
    Semantics(
      header: true,
      child: Text(l10n.momentClosingTitle, style: text.headlineMedium),
    ),
    const SizedBox(height: AppSpace.xs),
    const SharingLabel(sharing: Sharing.doctorSees),
    const SizedBox(height: AppSpace.lg),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: IntensityScale(
          label: l10n.momentIntensityAfter,
          value: _after,
          onChanged: (v) => setState(() => _after = v),
        ),
      ),
    ),
    const SizedBox(height: AppSpace.lg),
    FilledButton(
      onPressed: _after == null || _saving
          ? null
          : () => unawaited(_markPassed()),
      child: Text(l10n.momentSave),
    ),
    const SizedBox(height: AppSpace.sm),
    TextButton(
      onPressed: () => setState(() => _stage = _Stage.surfing),
      child: Text(l10n.momentBackToBreathing),
    ),
  ];

  List<Widget> _passedStage(AppLocalizations l10n, TextTheme text) {
    final before = _log?.intensityBefore ?? _before ?? 0;
    final after = _log?.intensityAfter ?? _after ?? 0;
    return [
      const SizedBox(height: AppSpace.lg),
      Semantics(
        header: true,
        child: Text(
          l10n.momentPassedTitle,
          textAlign: TextAlign.center,
          style: text.headlineLarge,
        ),
      ),
      const SizedBox(height: AppSpace.sm),
      Text(
        after < before ? l10n.momentPassedLower : l10n.momentPassedSteady,
        textAlign: TextAlign.center,
        style: text.bodyLarge?.copyWith(color: AppColors.textBody),
      ),
      const SizedBox(height: AppSpace.xl),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            children: [
              Expanded(
                child: _BeforeAfter(label: l10n.momentBefore, value: before),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.textMuted,
              ),
              Expanded(
                child: _BeforeAfter(
                  label: l10n.momentAfter,
                  value: after,
                  strong: true,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpace.lg),
      const Center(child: SharingLabel(sharing: Sharing.doctorSees)),
      const SizedBox(height: AppSpace.xl),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.momentDone),
      ),
    ];
  }
}

/// Opens the difficult-moment screen the way the other recovery screens
/// open (plain [Navigator], no go_router).
Future<void> openDifficultMoment(BuildContext context) =>
    Navigator.of(context).push<void>(
      appRoute(
        const DifficultMomentScreen(),
        reduced: AppMotion.reduced(context),
      ),
    );

/// The way in from the recovery home: one calm card, never an alarm.
class DifficultMomentCard extends StatelessWidget {
  const DifficultMomentCard({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: l10n.momentEntryTitle,
      child: Material(
        color: AppColors.teal800,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(
              spacing: AppSpace.md,
              children: [
                const Icon(
                  Icons.spa_outlined,
                  color: AppColors.onPrimary,
                  size: 28,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.momentEntryTitle,
                        style: text.titleLarge?.copyWith(
                          color: AppColors.onPrimary,
                        ),
                      ),
                      Text(
                        l10n.momentEntryBody,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.teal100,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.onPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How strong the craving is, 1 to 10. Ten 44 px targets, so they wrap on a
/// narrow screen rather than shrink.
class IntensityScale extends StatelessWidget {
  const IntensityScale({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.sm,
      children: [
        Text(label, style: text.labelMedium),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (var v = cravingIntensityMin; v <= cravingIntensityMax; v++)
              Semantics(
                button: true,
                selected: value == v,
                label: l10n.momentIntensityValue(label, v),
                excludeSemantics: true,
                child: InkResponse(
                  key: ValueKey('intensity-$v'),
                  onTap: () => onChanged(v),
                  radius: 28,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value == v ? AppColors.teal600 : AppColors.sand100,
                    ),
                    child: Text(
                      '$v',
                      textDirection: TextDirection.ltr,
                      style: text.labelLarge?.copyWith(
                        color: value == v
                            ? AppColors.onPrimary
                            : AppColors.textStrong,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Row(
          children: [
            Expanded(child: Text(l10n.momentIntensityLow, style: muted)),
            Text(l10n.momentIntensityHigh, style: muted),
          ],
        ),
      ],
    );
  }
}

/// The HALT triggers, all optional.
class _Triggers extends StatelessWidget {
  const _Triggers({required this.selected, required this.onToggle});

  final Set<CravingTrigger> selected;
  final ValueChanged<CravingTrigger> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    String label(CravingTrigger t) => switch (t) {
      CravingTrigger.hungry => l10n.momentTriggerHungry,
      CravingTrigger.angry => l10n.momentTriggerAngry,
      CravingTrigger.lonely => l10n.momentTriggerLonely,
      CravingTrigger.tired => l10n.momentTriggerTired,
      CravingTrigger.other => l10n.momentTriggerOther,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpace.sm,
      children: [
        Text(l10n.momentTriggersTitle, style: text.labelMedium),
        Text(
          l10n.momentTriggersHint,
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final t in CravingTrigger.values)
              FilterChip(
                key: ValueKey('trigger-${t.name}'),
                label: Text(label(t)),
                selected: selected.contains(t),
                onSelected: (_) => onToggle(t),
              ),
          ],
        ),
      ],
    );
  }
}

/// One thing to try right now; the patient can ask for another.
class _TipCard extends StatelessWidget {
  const _TipCard({required this.tip, required this.onAnother});

  final String tip;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.sm,
          children: [
            Text(l10n.momentTipTitle, style: text.titleMedium),
            Text(tip, style: text.bodyMedium),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onAnother,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.momentTipAnother),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "When ___, I will ___", written by the patient, kept on the phone.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.editing,
    required this.when,
    required this.then,
    required this.onEdit,
    required this.onSave,
  });

  final IfThenPlan plan;
  final bool editing;
  final TextEditingController when;
  final TextEditingController then;
  final VoidCallback onEdit;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.sm,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.momentPlanTitle, style: text.titleMedium),
                ),
                const SharingLabel(sharing: Sharing.onlyYou),
              ],
            ),
            if (editing) ...[
              TextField(
                controller: when,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: l10n.momentPlanWhen,
                  hintText: l10n.momentPlanWhenHint,
                ),
              ),
              TextField(
                controller: then,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: l10n.momentPlanThen,
                  hintText: l10n.momentPlanThenHint,
                ),
              ),
              FilledButton(onPressed: onSave, child: Text(l10n.momentPlanSave)),
            ] else ...[
              Text(
                plan.isEmpty
                    ? l10n.momentPlanEmpty
                    : l10n.momentPlanLine(plan.when, plan.then),
                style: text.bodyMedium,
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(
                    plan.isEmpty ? l10n.momentPlanWrite : l10n.momentPlanChange,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Whether the clinic is open right now, and its number in one tap.
class _ClinicReach extends ConsumerWidget {
  const _ClinicReach({required this.clinic, required this.open});

  final ClinicInfo clinic;
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final phone = clinic.phones.firstOrNull;
    final openUrl = ref.read(openUrlProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.sm,
          children: [
            Row(
              spacing: AppSpace.sm,
              children: [
                Icon(
                  open ? Icons.schedule_rounded : Icons.schedule_outlined,
                  size: 20,
                  color: open ? AppColors.success : AppColors.textMuted,
                ),
                Expanded(
                  child: Text(
                    open ? l10n.momentClinicOpen : l10n.momentClinicClosed,
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
            if (phone != null)
              OutlinedButton.icon(
                onPressed: () => unawaited(
                  openUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', ''))),
                ),
                icon: const Icon(Icons.call_outlined),
                label: Text(l10n.momentCallClinic),
              ),
          ],
        ),
      ),
    );
  }
}

/// One side of the before/after pair.
class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final int value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          label,
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        Text(
          '$value',
          textDirection: TextDirection.ltr,
          style: text.headlineLarge?.copyWith(
            color: strong ? AppColors.teal700 : AppColors.textStrong,
          ),
        ),
      ],
    );
  }
}
