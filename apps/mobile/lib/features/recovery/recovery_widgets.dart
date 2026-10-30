import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/sobriety_ring.dart';
import '../booking/booking_format.dart';
import '../booking/booking_models.dart';
import '../booking/booking_widgets.dart';
import '../booking/payment_launcher.dart';
import 'recovery_models.dart';
import 'tracking_widgets.dart';

String _lang(BuildContext context) =>
    Localizations.localeOf(context).languageCode;

String _two(int n) => n.toString().padLeft(2, '0');

/// "08:00" from a time of day.
String clockTime(int hour, int minute) => '${_two(hour)}:${_two(minute)}';

/// "07:00–12:30 · 13:30–14:30".
String openHoursText(List<OpenHours> hours) => hours
    .map(
      (h) =>
          '${clockTime(h.from ~/ 60, h.from % 60)}–'
          '${clockTime(h.to ~/ 60, h.to % 60)}',
    )
    .join(' · ');

/// One addiction's counter: the ring toward the current small goal (PRD
/// 5.6), the clinic's note for this early stage, the longest streak and
/// total days (never erased), and a calm way to log a relapse.
class CounterCard extends StatelessWidget {
  const CounterCard({
    super.key,
    required this.addiction,
    required this.name,
    required this.now,
    required this.onRelapse,
    this.note,
    this.onChangeGoal,
  });

  final Addiction addiction;

  /// The substance profile's name, or the type for generic tracking.
  final String name;
  final DateTime now;
  final VoidCallback onRelapse;
  final EarlyNote? note;
  final VoidCallback? onChangeGoal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final days = addiction.days(now);
    final goal = addiction.goal(now);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.lg,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: text.titleLarge),
                if (addiction.substance case final substance?)
                  Text(substance, style: text.bodyMedium),
                Text(
                  l10n.recoveryCleanSince(l10n.longDate(addiction.start)),
                  style: text.bodySmall?.copyWith(color: AppColors.textBody),
                ),
                if (!addiction.reviewed) ...[
                  const SizedBox(height: AppSpace.sm),
                  Pill(
                    text: l10n.addictionPending,
                    color: AppColors.warning,
                    icon: Icons.hourglass_top_rounded,
                  ),
                ],
              ],
            ),
            Center(
              child: SobrietyRing(
                days: days,
                goal: goal,
                label: l10n.ringDaysLabel(days),
                semanticLabel: l10n.ringOfGoal(days, goal),
              ),
            ),
            Column(
              spacing: AppSpace.xs,
              children: [
                Pill(
                  text: l10n.recoveryNextGoal(l10n.bookDays(goal)),
                  color: AppColors.sand500,
                  dot: AppColors.sand400,
                ),
                Text(
                  l10n.recoveryToGo(l10n.bookDays(goal - days)),
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
                if (onChangeGoal != null)
                  TextButton(
                    onPressed: onChangeGoal,
                    child: Text(l10n.goalChange),
                  ),
              ],
            ),
            if (note case final note?) EarlyNoteBox(note: note),
            Row(
              spacing: AppSpace.md,
              children: [
                Expanded(
                  child: _Stat(
                    value: l10n.bookDays(addiction.longest(now)),
                    label: l10n.recoveryLongest,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    value: l10n.bookDays(addiction.total(now)),
                    label: l10n.recoveryTotal,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.textBody),
              onPressed: onRelapse,
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(l10n.recoveryRelapse),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.sand50,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: text.titleLarge?.copyWith(color: AppColors.teal700),
          ),
          Text(
            label,
            style: text.bodySmall?.copyWith(color: AppColors.textBody),
          ),
        ],
      ),
    );
  }
}

/// A small rounded label: a dot or icon plus a few words.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.text,
    required this.color,
    this.dot,
    this.icon,
  });

  final String text;

  /// Tint of the fill (at 12%) and of the icon.
  final Color color;
  final Color? dot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpace.xs + 2,
        children: [
          if (dot case final dot?)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          if (icon case final icon?) Icon(icon, size: 14, color: color),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.textStrong,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the time picker in 24-hour format, in the app's language and
/// direction. Returns null when dismissed.
Future<DayTime?> pickTime(BuildContext context, DayTime initial) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  return picked == null ? null : (hour: picked.hour, minute: picked.minute);
}

/// What the patient said in the relapse sheet.
typedef RelapseReport = ({String note, DateTime at});

/// Asks before restarting a counter, and when it happened (today or
/// yesterday, at a time). Returns null when the patient changed their mind.
Future<RelapseReport?> showRelapseSheet(
  BuildContext context, {
  required DateTime now,
}) {
  return showModalBottomSheet<RelapseReport>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _RelapseSheet(now: now),
  );
}

class _RelapseSheet extends StatefulWidget {
  const _RelapseSheet({required this.now});

  final DateTime now;

  @override
  State<_RelapseSheet> createState() => _RelapseSheetState();
}

class _RelapseSheetState extends State<_RelapseSheet> {
  final _note = TextEditingController();
  bool _yesterday = false;
  late DayTime _time = (hour: widget.now.hour, minute: widget.now.minute);

  /// The moment chosen, never later than now.
  DateTime get _at {
    final day = dayOf(widget.now).subtract(Duration(days: _yesterday ? 1 : 0));
    final at = day.add(Duration(hours: _time.hour, minutes: _time.minute));
    return at.isAfter(widget.now) ? widget.now : at;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final at = _at;
    return SingleChildScrollView(
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
          Text(l10n.recoveryRelapseTitle, style: text.headlineMedium),
          Text(l10n.recoveryRelapseBody, style: text.bodyLarge),
          Text(l10n.relapseWhen, style: text.labelMedium),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: Text(l10n.relapseToday),
                selected: !_yesterday,
                onSelected: (_) => setState(() => _yesterday = false),
              ),
              ChoiceChip(
                label: Text(l10n.relapseYesterday),
                selected: _yesterday,
                onSelected: (_) => setState(() => _yesterday = true),
              ),
              Semantics(
                button: true,
                label: '${l10n.relapseTime} ${clockTime(at.hour, at.minute)}',
                excludeSemantics: true,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                    ),
                  ),
                  onPressed: () async {
                    final t = await pickTime(context, _time);
                    if (t != null) setState(() => _time = t);
                  },
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: LtrText(clockTime(at.hour, at.minute)),
                ),
              ),
            ],
          ),
          TextField(
            controller: _note,
            maxLines: 2,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: l10n.recoveryRelapseNote),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop((note: _note.text.trim(), at: _at)),
            child: Text(l10n.recoveryRelapseConfirm),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.recoveryRelapseCancel),
          ),
        ],
      ),
    );
  }
}

/// This week's daily check (PRD 5.4, simple form): the last seven days, a
/// button to tick today, and the time of the daily reminder.
class WeekCheckCard extends StatelessWidget {
  const WeekCheckCard({
    super.key,
    required this.checkIns,
    required this.now,
    required this.reminder,
    required this.onCheckIn,
    required this.onPickReminder,
    required this.onStopReminder,
    this.actionLabel,
  });

  /// The button's text; the simple "day without use" tick by default.
  final String? actionLabel;
  final Set<DateTime> checkIns;
  final DateTime now;
  final DayTime? reminder;
  final VoidCallback onCheckIn;
  final VoidCallback onPickReminder;
  final VoidCallback onStopReminder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final today = dayOf(now);
    final week = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    final done = week.where(checkIns.contains).length;
    final todayDone = checkIns.contains(today);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.md,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.checkInTitle, style: text.titleLarge),
                ),
                Text(
                  l10n.checkInCount(done),
                  style: text.bodySmall?.copyWith(color: AppColors.textBody),
                ),
              ],
            ),
            Row(
              children: [
                for (final d in week)
                  Expanded(
                    child: _DayDot(
                      day: l10n.shortWeekday(d),
                      done: checkIns.contains(d),
                      today: d == today,
                    ),
                  ),
              ],
            ),
            if (todayDone)
              Row(
                spacing: AppSpace.sm,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                  ),
                  Expanded(
                    child: Text(
                      l10n.checkInDone,
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )
            else
              FilledButton.icon(
                onPressed: onCheckIn,
                icon: const Icon(Icons.check_rounded),
                label: Text(actionLabel ?? l10n.checkInAction),
              ),
            const Divider(),
            Row(
              children: [
                const Icon(Icons.alarm_rounded, color: AppColors.teal600),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(l10n.checkInReminder, style: text.bodyMedium),
                ),
                Semantics(
                  button: true,
                  label: l10n.checkInReminderPick,
                  child: TextButton(
                    onPressed: onPickReminder,
                    child: reminder == null
                        ? Text(l10n.checkInReminderOff)
                        : LtrText(clockTime(reminder!.hour, reminder!.minute)),
                  ),
                ),
                if (reminder != null)
                  IconButton(
                    tooltip: l10n.checkInReminderStop,
                    onPressed: onStopReminder,
                    icon: const Icon(
                      Icons.notifications_off_outlined,
                      color: AppColors.textBody,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.day, required this.done, required this.today});

  final String day;
  final bool done;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: done ? l10n.checkInDayDone(day) : l10n.checkInDayOpen(day),
      excludeSemantics: true,
      child: Column(
        spacing: AppSpace.xs,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? AppColors.teal500 : AppColors.sand100,
              border: today && !done
                  ? Border.all(color: AppColors.teal500, width: 2)
                  : null,
            ),
            child: done
                ? const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: AppColors.onPrimary,
                  )
                : null,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              day,
              maxLines: 1,
              style: text.bodySmall?.copyWith(
                color: today ? AppColors.teal700 : AppColors.textBody,
                fontWeight: today ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The soonest upcoming appointment; tapping opens the appointments tab.
class NextAppointmentCard extends StatelessWidget {
  const NextAppointmentCard({
    super.key,
    required this.appointment,
    required this.onOpen,
  });

  final Appointment appointment;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final a = appointment;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            spacing: AppSpace.md,
            children: [
              Container(
                width: 52,
                constraints: const BoxConstraints(minHeight: 56),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                decoration: BoxDecoration(
                  color: AppColors.teal50,
                  borderRadius: BorderRadius.circular(AppRadius.field),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LtrText(
                      '${a.start.day}',
                      style: text.titleLarge?.copyWith(
                        color: AppColors.teal700,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      l10n.month(a.start),
                      style: text.bodySmall?.copyWith(color: AppColors.teal700),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.recoveryNextAppt,
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textBody,
                      ),
                    ),
                    Text(
                      a.doctor.name(_lang(context)),
                      style: text.titleLarge?.copyWith(
                        fontSize: AppType.body.size,
                      ),
                    ),
                    Wrap(
                      spacing: AppSpace.xs,
                      children: [
                        Text(l10n.longDate(a.start), style: text.bodySmall),
                        LtrText(
                          timeRange(a.start, a.end),
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.teal600),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's doses with Taken / Not taken (PRD 5.3). Colour never carries the
/// state alone: each answer is a word with an icon.
class DosesCard extends StatelessWidget {
  const DosesCard({super.key, required this.doses, required this.onMark});

  final List<Dose> doses;
  final void Function(Dose dose, DoseStatus status) onMark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final taken = doses.where((d) => d.status == DoseStatus.taken).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.md,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.recoveryMedsTitle, style: text.titleLarge),
                ),
                if (doses.isNotEmpty)
                  Text(
                    l10n.recoveryMedsCount(taken, doses.length),
                    style: text.bodySmall?.copyWith(color: AppColors.textBody),
                  ),
              ],
            ),
            if (doses.isEmpty)
              Text(l10n.recoveryNoMeds, style: text.bodyMedium)
            else
              for (var i = 0; i < doses.length; i++) ...[
                if (i > 0) const Divider(),
                _DoseRow(dose: doses[i], onMark: onMark),
              ],
          ],
        ),
      ),
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose, required this.onMark});

  final Dose dose;
  final void Function(Dose dose, DoseStatus status) onMark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = _lang(context);
    const small = Size(0, 44);
    const pad = EdgeInsets.symmetric(horizontal: AppSpace.lg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.sm,
      children: [
        Row(
          spacing: AppSpace.md,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.teal50,
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              child: const Icon(
                Icons.medication_outlined,
                color: AppColors.teal600,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${dose.name.of(lang)} · ${dose.amount.of(lang)}',
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Wrap(
                    spacing: AppSpace.xs,
                    children: [
                      LtrText(
                        clockTime(dose.hour, dose.minute),
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textBody,
                        ),
                      ),
                      if (dose.instruction case final i?)
                        Text(
                          '· ${i.of(lang)}',
                          style: text.bodySmall?.copyWith(
                            color: AppColors.textBody,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            switch (dose.status) {
              DoseStatus.taken => Pill(
                text: l10n.recoveryDoseTaken,
                color: AppColors.success,
                icon: Icons.check_rounded,
              ),
              DoseStatus.skipped => Pill(
                text: l10n.recoveryDoseSkipped,
                color: AppColors.sand500,
                icon: Icons.remove_rounded,
              ),
              DoseStatus.due => const SizedBox.shrink(),
            },
          ],
        ),
        if (dose.status == DoseStatus.due)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: small,
                  padding: pad,
                ),
                onPressed: () => onMark(dose, DoseStatus.skipped),
                child: Text(l10n.recoveryDoseSkip),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: small, padding: pad),
                onPressed: () => onMark(dose, DoseStatus.taken),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(l10n.recoveryDoseTake),
              ),
            ],
          ),
      ],
    );
  }
}

/// Quote of the day (PRD 5.2) on the darkest brand teal.
class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key, required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = _lang(context);
    return Container(
      padding: const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        color: AppColors.teal800,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpace.sm,
        children: [
          Text(
            l10n.recoveryQuoteTitle,
            style: text.labelMedium?.copyWith(color: AppColors.teal100),
          ),
          Text(
            quote.text.of(lang),
            style: text.bodyLarge?.copyWith(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (quote.source.of(lang).isNotEmpty)
            Text(
              quote.source.of(lang),
              style: text.bodySmall?.copyWith(color: AppColors.sand300),
            ),
        ],
      ),
    );
  }
}

/// The practice: address, phones (tap to call), today's hours and a link
/// to Google Maps.
class ClinicCard extends ConsumerWidget {
  const ClinicCard({super.key, required this.clinic, required this.now});

  final ClinicInfo clinic;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = _lang(context);
    final open = ref.read(openUrlProvider);
    final today = clinic.hoursOn(now);

    Widget line(IconData icon, Widget child) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpace.md,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: AppColors.teal600),
        ),
        Expanded(child: child),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.md,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.clinicTitle, style: text.titleLarge)),
                const SizedBox(width: AppSpace.sm),
                Flexible(
                  child: Pill(
                    text: today.isEmpty
                        ? l10n.clinicClosedToday
                        : l10n.clinicOpenToday,
                    color: today.isEmpty
                        ? AppColors.sand500
                        : AppColors.success,
                    dot: today.isEmpty
                        ? AppColors.sand400
                        : AppColors.success,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clinic.name.of(lang),
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textStrong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(clinic.specialty.of(lang), style: text.bodySmall),
              ],
            ),
            line(
              Icons.place_outlined,
              Text(clinic.address.of(lang), style: text.bodyMedium),
            ),
            line(
              Icons.call_outlined,
              Wrap(
                spacing: AppSpace.lg,
                children: [
                  for (final phone in clinic.phones)
                    Semantics(
                      button: true,
                      label: l10n.clinicCallNumber(phone),
                      excludeSemantics: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.field),
                        onTap: () => unawaited(
                          open(
                            Uri(scheme: 'tel', path: phone.replaceAll(' ', '')),
                          ),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Align(
                            widthFactor: 1,
                            child: LtrText(
                              phone,
                              style: text.bodyMedium?.copyWith(
                                color: AppColors.teal700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            line(
              Icons.schedule_rounded,
              today.isEmpty
                  ? Text(l10n.clinicClosedToday, style: text.bodyMedium)
                  : Wrap(
                      spacing: AppSpace.xs,
                      children: [
                        Text(
                          '${l10n.clinicHoursToday}:',
                          style: text.bodyMedium,
                        ),
                        LtrText(openHoursText(today), style: text.bodyMedium),
                      ],
                    ),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(open(clinic.maps)),
              icon: const Icon(Icons.map_outlined),
              label: Text(l10n.clinicMaps),
            ),
          ],
        ),
      ),
    );
  }
}
