import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../booking/booking_widgets.dart';
import 'recovery_models.dart';
import 'recovery_widgets.dart';

String _lang(BuildContext context) =>
    Localizations.localeOf(context).languageCode;

/// What the patient calls an addiction: its substance profile's name, or
/// its type for generic tracking.
String addictionName(
  BuildContext context,
  Addiction addiction,
  List<ProfileSpec> profiles,
) {
  final spec = profileOf(addiction, profiles);
  return spec != null
      ? spec.name.of(_lang(context))
      : AppLocalizations.of(context).addictionType(addiction.type.name);
}

ProfileSpec? profileOf(Addiction addiction, List<ProfileSpec> profiles) {
  for (final p in profiles) {
    if (p.profile == addiction.profile) return p;
  }
  return null;
}

/// A habit's name: from the clinic's list, or the patient's own words.
String habitName(
  BuildContext context,
  Habit habit,
  Map<HabitKind, LocalizedText> catalog,
) => habit.text ?? catalog[habit.kind]?.of(_lang(context)) ?? '';

/// Recovery before the first confirmed appointment (PRD 5): what opens it,
/// and a way to book.
class RecoveryLockedView extends StatelessWidget {
  const RecoveryLockedView({super.key, required this.onBook});

  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.screenHorizontal),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpace.md,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 40,
                  color: AppColors.sand500,
                ),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.recoveryLockedTitle,
                    textAlign: TextAlign.center,
                    style: text.titleLarge,
                  ),
                ),
                Text(
                  l10n.recoveryLockedBody,
                  textAlign: TextAlign.center,
                  style: text.bodyLarge,
                ),
                FilledButton.icon(
                  onPressed: onBook,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(l10n.recoveryLockedBook),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 1-5 rating (higher = harder) as five round choices between "low" and
/// "high" ends. [value] is null until the patient answers.
class RatingRow extends StatelessWidget {
  const RatingRow({
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
      spacing: AppSpace.xs,
      children: [
        Text(label, style: text.labelMedium),
        Row(
          children: [
            for (var v = 1; v <= 5; v++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: value == v,
                  label: l10n.ratingValue(label, v),
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.xs,
                    ),
                    child: InkResponse(
                      key: ValueKey('rating-$label-$v'),
                      onTap: () => onChanged(v),
                      radius: 28,
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: value == v
                              ? AppColors.teal500
                              : AppColors.sand100,
                        ),
                        child: Text(
                          '$v',
                          style: text.labelLarge?.copyWith(
                            color: value == v
                                ? AppColors.onPrimary
                                : AppColors.textStrong,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Row(
          children: [
            Expanded(child: Text(l10n.ratingLow, style: muted)),
            Text(l10n.ratingHigh, style: muted),
          ],
        ),
      ],
    );
  }
}

/// The clinic's short "what to expect" note for the patient's early days.
class EarlyNoteBox extends StatelessWidget {
  const EarlyNoteBox({super.key, required this.note});

  final EarlyNote note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.teal50,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpace.sm,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            size: 20,
            color: AppColors.teal700,
          ),
          Expanded(
            child: Text(note.text.of(_lang(context)), style: text.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Lets the patient choose their next small goal (PRD 5.6): a step not
/// reached yet, or automatic. Returns the chosen days, 0 for automatic, or
/// null when dismissed.
Future<int?> showGoalSheet(
  BuildContext context, {
  required int days,
  required int? chosen,
}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final text = Theme.of(context).textTheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screenHorizontal,
          0,
          AppSpace.screenHorizontal,
          AppSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.md,
          children: [
            Text(l10n.goalTitle, style: text.headlineMedium),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                ChoiceChip(
                  label: Text(
                    '${l10n.goalAuto} · ${l10n.bookDays(nextGoal(days))}',
                  ),
                  selected: chosen == null,
                  onSelected: (_) => Navigator.of(context).pop(0),
                ),
                for (final step in goalSteps)
                  if (step > days)
                    ChoiceChip(
                      label: Text(l10n.bookDays(step)),
                      selected: chosen == step,
                      onSelected: (_) => Navigator.of(context).pop(step),
                    ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// What the patient chose in the add-habit sheet.
typedef NewHabit = ({HabitKind kind, String? text, DayTime? reminder});

/// Picks a habit from the clinic's list (those not kept yet) or in the
/// patient's own words, with an optional daily reminder.
Future<NewHabit?> showAddHabitSheet(
  BuildContext context, {
  required Map<HabitKind, LocalizedText> catalog,
  required Set<HabitKind> kept,
}) {
  return showModalBottomSheet<NewHabit>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _AddHabitSheet(catalog: catalog, kept: kept),
  );
}

class _AddHabitSheet extends StatefulWidget {
  const _AddHabitSheet({required this.catalog, required this.kept});

  final Map<HabitKind, LocalizedText> catalog;
  final Set<HabitKind> kept;

  @override
  State<_AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends State<_AddHabitSheet> {
  final _own = TextEditingController();
  HabitKind? _kind;
  DayTime? _reminder;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  bool get _ready =>
      _kind != null &&
      (_kind != HabitKind.custom || _own.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = _lang(context);
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
          Text(l10n.habitsAdd, style: text.headlineMedium),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final MapEntry(key: kind, value: label)
                  in widget.catalog.entries)
                if (!widget.kept.contains(kind))
                  ChoiceChip(
                    label: Text(label.of(lang)),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ChoiceChip(
                label: Text(l10n.habitsOwn),
                selected: _kind == HabitKind.custom,
                onSelected: (_) => setState(() => _kind = HabitKind.custom),
              ),
            ],
          ),
          if (_kind == HabitKind.custom)
            TextField(
              controller: _own,
              maxLength: 60,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.habitsOwn,
                hintText: l10n.habitsOwnHint,
              ),
            ),
          Row(
            children: [
              const Icon(Icons.alarm_rounded, color: AppColors.teal600),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(l10n.habitsReminder, style: text.bodyMedium),
              ),
              TextButton(
                onPressed: () async {
                  final t = await pickTime(
                    context,
                    _reminder ?? (hour: 18, minute: 0),
                  );
                  if (t != null) setState(() => _reminder = t);
                },
                child: _reminder == null
                    ? Text(l10n.checkInReminderOff)
                    : LtrText(clockTime(_reminder!.hour, _reminder!.minute)),
              ),
            ],
          ),
          FilledButton(
            onPressed: _ready
                ? () => Navigator.of(context).pop((
                    kind: _kind!,
                    text: _kind == HabitKind.custom ? _own.text.trim() : null,
                    reminder: _reminder,
                  ))
                : null,
            child: Text(l10n.addictionSave),
          ),
        ],
      ),
    );
  }
}

/// The patient's good habits (PRD 5.6): tick each one done today, set its
/// reminder, remove it, or add another (up to five).
class HabitsCard extends StatelessWidget {
  const HabitsCard({
    super.key,
    required this.habits,
    required this.catalog,
    required this.now,
    required this.onToggle,
    required this.onPickReminder,
    required this.onRemove,
    required this.onAdd,
  });

  static const max = 5;

  final List<Habit> habits;
  final Map<HabitKind, LocalizedText> catalog;
  final DateTime now;
  final void Function(Habit habit, bool done) onToggle;
  final ValueChanged<Habit> onPickReminder;
  final ValueChanged<Habit> onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final today = dayOf(now);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.sm,
          children: [
            Text(l10n.habitsTitle, style: text.titleLarge),
            if (habits.isEmpty) Text(l10n.habitsEmpty, style: text.bodyMedium),
            for (final h in habits)
              _HabitRow(
                name: habitName(context, h, catalog),
                done: h.days.contains(today),
                reminder: h.reminder,
                onToggle: (done) => onToggle(h, done),
                onPickReminder: () => onPickReminder(h),
                onRemove: () => onRemove(h),
              ),
            if (habits.length < max)
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.habitsAdd),
              )
            else
              Text(
                l10n.habitsMax,
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({
    required this.name,
    required this.done,
    required this.reminder,
    required this.onToggle,
    required this.onPickReminder,
    required this.onRemove,
  });

  final String name;
  final bool done;
  final DayTime? reminder;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickReminder;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Semantics(
          label: done ? l10n.habitsDone(name) : l10n.habitsOpen(name),
          excludeSemantics: true,
          child: Checkbox(value: done, onChanged: (v) => onToggle(v ?? false)),
        ),
        Expanded(child: Text(name, style: text.bodyLarge)),
        Semantics(
          button: true,
          label: '${l10n.habitsReminder} $name',
          excludeSemantics: true,
          child: TextButton(
            onPressed: onPickReminder,
            child: reminder == null
                ? const Icon(Icons.alarm_add_rounded, color: AppColors.textBody)
                : LtrText(clockTime(reminder!.hour, reminder!.minute)),
          ),
        ),
        IconButton(
          tooltip: l10n.habitsRemove(name),
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, color: AppColors.textBody),
        ),
      ],
    );
  }
}
