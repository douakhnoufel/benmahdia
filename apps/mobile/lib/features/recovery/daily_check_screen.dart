import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import 'recovery_models.dart';
import 'tracking_widgets.dart';

/// Today's check (PRD 5.6), one card per addiction: "today without X?",
/// craving and the profile's two signals, each 1-5. Then the good habits
/// done today. Saving returns the addictions answered "used", so the home
/// can open relapse logging for each (PRD 5.1).
class DailyCheckScreen extends StatefulWidget {
  const DailyCheckScreen({
    super.key,
    required this.today,
    required this.addictions,
    required this.profiles,
    required this.previous,
    required this.habits,
    required this.catalog,
    required this.onSave,
  });

  /// A [dayOf] date.
  final DateTime today;
  final List<Addiction> addictions;
  final List<ProfileSpec> profiles;

  /// Today's checks already saved, to change them.
  final List<AddictionCheck> previous;
  final List<Habit> habits;
  final Map<HabitKind, LocalizedText> catalog;

  /// Saves the checks and which habits are done; throws on failure.
  final Future<void> Function(
    List<AddictionCheck> checks,
    Map<Habit, bool> habitsDone,
  )
  onSave;

  @override
  State<DailyCheckScreen> createState() => _DailyCheckScreenState();
}

class _Answer {
  bool? used;
  int? craving;
  final signals = <String, int>{};
}

class _DailyCheckScreenState extends State<DailyCheckScreen> {
  late final Map<String, _Answer> _answers = {
    for (final a in widget.addictions) a.id: _answerFor(a),
  };
  late final Map<Habit, bool> _habits = {
    for (final h in widget.habits) h: h.days.contains(widget.today),
  };
  bool _saving = false;

  _Answer _answerFor(Addiction a) {
    final answer = _Answer();
    for (final c in widget.previous) {
      if (c.addictionId == a.id && c.day == widget.today) {
        answer
          ..used = c.used
          ..craving = c.craving
          ..signals.addAll(c.signals);
      }
    }
    return answer;
  }

  List<SignalSpec> _signals(Addiction a) =>
      profileOf(a, widget.profiles)?.signals ?? const [];

  bool get _complete => widget.addictions.every((a) {
    final answer = _answers[a.id]!;
    return answer.used != null &&
        answer.craving != null &&
        _signals(a).every((s) => answer.signals.containsKey(s.key));
  });

  Future<void> _save() async {
    setState(() => _saving = true);
    final checks = [
      for (final a in widget.addictions)
        AddictionCheck(
          addictionId: a.id,
          day: widget.today,
          used: _answers[a.id]!.used!,
          craving: _answers[a.id]!.craving!,
          signals: {
            for (final s in _signals(a)) s.key: _answers[a.id]!.signals[s.key]!,
          },
        ),
    ];
    try {
      await widget.onSave(checks, _habits);
      if (!mounted) return;
      Navigator.of(context).pop([
        for (final a in widget.addictions)
          if (_answers[a.id]!.used!) a,
      ]);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screenHorizontal,
          0,
          AppSpace.screenHorizontal,
          AppSpace.xl,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(l10n.dailyCheckTitle, style: text.headlineLarge),
          ),
          const SizedBox(height: AppSpace.lg),
          for (final a in widget.addictions) ...[
            _AddictionCheckCard(
              name: addictionName(context, a, widget.profiles),
              signals: [
                for (final s in _signals(a))
                  (key: s.key, label: s.label.of(lang)),
              ],
              answer: _answers[a.id]!,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          if (widget.habits.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.habitsTitle, style: text.titleLarge),
                    for (final h in widget.habits)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _habits[h],
                        title: Text(habitName(context, h, widget.catalog)),
                        onChanged: (v) =>
                            setState(() => _habits[h] = v ?? false),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpace.xl),
          if (!_complete)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(
                l10n.dailyCheckNeedAnswers,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
          FilledButton(
            onPressed: _complete && !_saving ? _save : null,
            child: Text(l10n.addictionSave),
          ),
        ],
      ),
    );
  }
}

class _AddictionCheckCard extends StatelessWidget {
  const _AddictionCheckCard({
    required this.name,
    required this.signals,
    required this.answer,
    required this.onChanged,
  });

  final String name;
  final List<({String key, String label})> signals;
  final _Answer answer;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.md,
          children: [
            Text(name, style: text.titleLarge),
            Text(l10n.dailyCheckWithout(name), style: text.bodyLarge),
            Row(
              spacing: AppSpace.sm,
              children: [
                ChoiceChip(
                  label: Text(l10n.dailyCheckYes),
                  selected: answer.used == false,
                  onSelected: (_) {
                    answer.used = false;
                    onChanged();
                  },
                ),
                ChoiceChip(
                  label: Text(l10n.dailyCheckNo),
                  selected: answer.used == true,
                  onSelected: (_) {
                    answer.used = true;
                    onChanged();
                  },
                ),
              ],
            ),
            RatingRow(
              label: l10n.dailyCheckCraving,
              value: answer.craving,
              onChanged: (v) {
                answer.craving = v;
                onChanged();
              },
            ),
            for (final s in signals)
              RatingRow(
                label: s.label,
                value: answer.signals[s.key],
                onChanged: (v) {
                  answer.signals[s.key] = v;
                  onChanged();
                },
              ),
          ],
        ),
      ),
    );
  }
}
