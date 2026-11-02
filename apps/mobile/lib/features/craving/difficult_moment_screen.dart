import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/breathing_circle.dart';
import '../../widgets/sharing_label.dart';
import '../companion/companion_screen.dart';
import 'craving_models.dart';
import 'craving_repository.dart';

enum _Stage { setup, breathing, after, result }

/// The difficult-moment screen (urge surfing): rate the craving, name what
/// is behind it if the patient wants, breathe with the circle while it
/// passes, then rate it again and see the before and after.
///
/// The craving log is kept when the server answers; if it does not, the
/// patient is never blocked: the moment is saved when they finish.
class DifficultMomentScreen extends ConsumerStatefulWidget {
  const DifficultMomentScreen({super.key});

  @override
  ConsumerState<DifficultMomentScreen> createState() =>
      _DifficultMomentScreenState();
}

class _DifficultMomentScreenState extends ConsumerState<DifficultMomentScreen> {
  _Stage _stage = _Stage.setup;
  int? _before;
  int? _after;
  final _halt = <Halt>{};
  CravingLog? _log;
  Future<void>? _starting;
  Timer? _ticker;
  int _seconds = 0;
  bool _saving = false;
  bool _failed = false;
  IfThenPlan? _plan;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlan());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadPlan() async {
    final plan = await ref.read(ifThenPlanStoreProvider).read();
    if (mounted) setState(() => _plan = plan);
  }

  void _begin() {
    final before = _before;
    if (before == null) return;
    setState(() => _stage = _Stage.breathing);
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _seconds++),
    );
    _starting = _open(before);
  }

  /// Opens the log in the background; a failure leaves it for [_finish].
  Future<void> _open(int before) async {
    try {
      final log = await ref
          .read(cravingRepositoryProvider)
          .start(intensity: before, halt: Set.of(_halt));
      if (mounted) _log = log;
    } on Object {
      _log = null;
    }
  }

  void _passed() {
    _ticker?.cancel();
    setState(() {
      _stage = _Stage.after;
      _failed = false;
    });
  }

  Future<void> _finish() async {
    final before = _before;
    final after = _after;
    if (before == null || after == null || _saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await _starting;
      final repo = ref.read(cravingRepositoryProvider);
      final open =
          _log ?? await repo.start(intensity: before, halt: Set.of(_halt));
      _log = open;
      await repo.markPassed(open, after);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _stage = _Stage.result;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _editPlan() async {
    final saved = await showModalBottomSheet<IfThenPlan>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PlanSheet(initial: _plan),
    );
    if (saved == null || !mounted) return;
    await ref.read(ifThenPlanStoreProvider).write(saved);
    if (mounted) setState(() => _plan = saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final children = switch (_stage) {
      _Stage.setup => _setup(l10n, text),
      _Stage.breathing => _breathing(l10n, text),
      _Stage.after => _afterStage(l10n, text),
      _Stage.result => _result(l10n, text),
    };
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(l10n.momentTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenHorizontal,
            AppSpace.sm,
            AppSpace.screenHorizontal,
            AppSpace.xl,
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpace.lg,
              children: children,
            ),
          ],
        ),
      ),
    );
  }

  // --- 1. setup -------------------------------------------------------------

  List<Widget> _setup(AppLocalizations l10n, TextTheme text) => [
    Text(l10n.momentIntro, style: text.bodyLarge),
    Semantics(
      header: true,
      child: Text(l10n.momentIntensityTitle, style: text.titleLarge),
    ),
    IntensityPicker(
      value: _before,
      onChanged: (v) => setState(() => _before = v),
    ),
    Semantics(
      header: true,
      child: Text(l10n.momentHaltTitle, style: text.titleMedium),
    ),
    Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final h in Halt.values)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: FilterChip(
              label: Text(_haltLabel(l10n, h)),
              selected: _halt.contains(h),
              onSelected: (on) =>
                  setState(() => on ? _halt.add(h) : _halt.remove(h)),
            ),
          ),
      ],
    ),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: const SharingLabel(Audience.yourDoctor),
    ),
    FilledButton(
      onPressed: _before == null ? null : _begin,
      child: Text(l10n.momentStart),
    ),
    _UrgentButton(label: l10n.companionUrgent),
  ];

  // --- 2. breathing ---------------------------------------------------------

  List<Widget> _breathing(AppLocalizations l10n, TextTheme text) => [
    Center(child: BreathingCircle(size: 220)),
    Center(
      child: Text(
        l10n.momentTimer(_clock(_seconds)),
        textDirection: Directionality.of(context),
        style: text.bodyMedium?.copyWith(color: AppColors.textBody),
      ),
    ),
    _TipCard(
      title: l10n.momentTipTitle,
      body: l10n.momentTipBody,
      caution: l10n.momentTipCaution,
    ),
    _PlanCard(plan: _plan, onEdit: _editPlan),
    FilledButton(onPressed: _passed, child: Text(l10n.momentPassed)),
    _UrgentButton(label: l10n.companionUrgent),
  ];

  // --- 3. after -------------------------------------------------------------

  List<Widget> _afterStage(AppLocalizations l10n, TextTheme text) => [
    Semantics(
      header: true,
      child: Text(l10n.momentAfterTitle, style: text.titleLarge),
    ),
    IntensityPicker(
      value: _after,
      onChanged: (v) => setState(() => _after = v),
    ),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: const SharingLabel(Audience.yourDoctor),
    ),
    if (_failed)
      Semantics(
        liveRegion: true,
        child: Text(
          l10n.momentSaveFailed,
          style: text.bodyMedium?.copyWith(color: AppColors.textBody),
        ),
      ),
    FilledButton(
      onPressed: _after == null || _saving ? null : _finish,
      child: Text(l10n.momentFinish),
    ),
  ];

  // --- 4. result ------------------------------------------------------------

  List<Widget> _result(AppLocalizations l10n, TextTheme text) {
    final before = _before!;
    final after = _after!;
    return [
      Semantics(
        header: true,
        child: Text(l10n.momentResultTitle, style: text.headlineMedium),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Figure(label: l10n.momentBefore, value: before),
              const Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.textMuted,
                size: 28,
                textDirection: TextDirection.ltr,
              ),
              _Figure(label: l10n.momentAfter, value: after),
            ],
          ),
        ),
      ),
      Text(
        after < before ? l10n.momentResultDown : l10n.momentResultSame,
        style: text.bodyLarge,
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: const SharingLabel(Audience.yourDoctor),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.momentClose),
      ),
    ];
  }
}

String _haltLabel(AppLocalizations l10n, Halt h) => switch (h) {
  Halt.hungry => l10n.momentHaltHungry,
  Halt.angry => l10n.momentHaltAngry,
  Halt.lonely => l10n.momentHaltLonely,
  Halt.tired => l10n.momentHaltTired,
};

/// "03:07", always with Western digits.
String _clock(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// 1 to 10 in two rows of five circles, each at least 48 px.
class IntensityPicker extends StatelessWidget {
  const IntensityPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.sm,
      children: [
        for (final row in const [
          [1, 2, 3, 4, 5],
          [6, 7, 8, 9, 10],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final n in row)
                Semantics(
                  button: true,
                  selected: value == n,
                  label: l10n.momentIntensityOption(n),
                  excludeSemantics: true,
                  onTap: () => onChanged(n),
                  child: InkResponse(
                    onTap: () => onChanged(n),
                    radius: 28,
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: value == n
                            ? AppColors.teal600
                            : AppColors.surface,
                        border: Border.all(
                          color: value == n
                              ? AppColors.teal600
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        '$n',
                        textDirection: TextDirection.ltr,
                        style: text.titleMedium?.copyWith(
                          color: value == n
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.momentScaleLow,
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            Text(
              l10n.momentScaleHigh,
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        spacing: AppSpace.xs,
        children: [
          Text(
            label,
            style: text.bodyMedium?.copyWith(color: AppColors.textBody),
          ),
          Text(
            '$value',
            textDirection: TextDirection.ltr,
            style: text.displaySmall?.copyWith(color: AppColors.teal700),
          ),
        ],
      ),
    );
  }
}

/// "Urgent help" stays one tap away on every stage (PRD 6.3).
class _UrgentButton extends StatelessWidget {
  const _UrgentButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => unawaited(showCrisisSheet(context)),
      icon: const Icon(Icons.support_rounded, color: AppColors.danger),
      label: Text(label),
    );
  }
}

/// The craving tip: a strong taste keeps the senses busy. It carries its
/// own caution, since it is not for everyone.
class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.title,
    required this.body,
    required this.caution,
  });

  final String title;
  final String body;
  final String caution;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpace.sm,
          children: [
            Text(title, style: text.titleMedium),
            Text(body, style: text.bodyLarge),
            Text(
              caution,
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The patient's if-then plan, kept on the phone, with a way to write it.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onEdit});

  final IfThenPlan? plan;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final saved = plan;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpace.sm,
          children: [
            Text(l10n.momentPlanTitle, style: text.titleMedium),
            Text(
              saved == null || saved.isEmpty
                  ? l10n.momentPlanEmpty
                  : l10n.momentPlanLine(saved.ifText, saved.thenText),
              style: text.bodyLarge,
            ),
            const SharingLabel(Audience.onlyYou),
            TextButton(
              onPressed: onEdit,
              child: Text(
                saved == null || saved.isEmpty
                    ? l10n.momentPlanAdd
                    : l10n.momentPlanEdit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanSheet extends StatefulWidget {
  const _PlanSheet({required this.initial});

  final IfThenPlan? initial;

  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  late final _if = TextEditingController(text: widget.initial?.ifText);
  late final _then = TextEditingController(text: widget.initial?.thenText);

  @override
  void dispose() {
    _if.dispose();
    _then.dispose();
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
        AppSpace.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpace.md,
        children: [
          TextField(
            controller: _if,
            maxLength: IfThenPlan.maxLength,
            decoration: InputDecoration(labelText: l10n.momentPlanIf),
          ),
          TextField(
            controller: _then,
            maxLength: IfThenPlan.maxLength,
            decoration: InputDecoration(labelText: l10n.momentPlanThen),
          ),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: SharingLabel(Audience.onlyYou),
          ),
          FilledButton(
            onPressed: () {
              final plan = IfThenPlan(
                ifText: _if.text.trim(),
                thenText: _then.text.trim(),
              );
              if (!plan.isEmpty) Navigator.of(context).pop(plan);
            },
            child: Text(l10n.momentPlanSave),
          ),
        ],
      ),
    );
  }
}
