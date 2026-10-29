import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../core/notifications/local_notifications.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_mark.dart';
import '../../widgets/staggered_reveal.dart';
import '../articles/articles_screen.dart';
import '../booking/booking_models.dart';
import '../booking/booking_repository.dart';
import '../booking/booking_widgets.dart';
import '../home/home_scope.dart';
import 'addiction_form_screen.dart';
import 'daily_check_screen.dart';
import 'milestone_screen.dart';
import 'recovery_models.dart';
import 'recovery_reminders.dart';
import 'recovery_repository.dart';
import 'recovery_widgets.dart';
import 'tracking_widgets.dart';

/// The recovery home (PRD 5, 12.3): one day counter per addiction toward
/// its small goal, this week's daily check (per substance once there is an
/// addiction, PRD 5.6), good habits, today's doses, the next appointment,
/// the quote of the day and the practice. Locked until the first confirmed
/// appointment.
class RecoveryScreen extends ConsumerStatefulWidget {
  const RecoveryScreen({super.key});

  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  List<Addiction> _addictions = const [];
  List<ProfileSpec> _profiles = const [];
  List<AddictionCheck> _checks = const [];
  Set<DateTime> _doneDays = const {};
  List<Habit> _habits = const [];
  Map<HabitKind, LocalizedText> _catalog = const {};
  Set<DateTime> _checkIns = const {};
  DayTime? _reminder;
  Quote? _quote;
  List<Dose> _doses = const [];
  ClinicInfo? _clinic;
  Appointment? _next;
  bool _loading = true;
  bool _failed = false;
  bool _locked = false;

  RecoveryRepository get _repo => ref.read(recoveryRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      // Alone first: a locked tab answers here, before the calls below.
      final addictions = await _repo.addictions();
      final (checkIns, reminder, quote, doses, clinic) = await (
        _repo.checkIns(),
        _repo.reminder(),
        _repo.quoteOfDay(),
        _repo.todaysDoses(),
        _repo.clinic(),
      ).wait;
      final (profiles, history, habits, catalog) = await (
        _repo.profiles(),
        _repo.addictionChecks(),
        _repo.habits(),
        _repo.habitCatalog(),
      ).wait;
      final next = await _nextAppointment();
      if (!mounted) return;
      setState(() {
        _addictions = addictions;
        _profiles = profiles;
        _checks = history.checks;
        _doneDays = history.doneDays;
        _habits = habits;
        _catalog = catalog;
        _checkIns = checkIns;
        _reminder = reminder;
        _quote = quote;
        _doses = doses;
        _clinic = clinic;
        _next = next;
        _loading = false;
        _failed = false;
        _locked = false;
      });
      unawaited(_syncReminders());
      unawaited(_celebrate());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = e is! RecoveryLocked;
        _locked = e is RecoveryLocked;
      });
    }
  }

  /// Shows the celebration of each milestone reached since the last one
  /// shown (PRD 5.1), one addiction after the other. Never throws: a "seen"
  /// the server did not get shows the celebration again next time.
  Future<void> _celebrate() async {
    for (final a in List.of(_addictions)) {
      final days = a.pendingMilestone(_repo.now());
      if (days == null) continue;
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        appRoute(
          MilestoneScreen(
            days: days,
            name: addictionName(context, a, _profiles),
          ),
          reduced: AppMotion.reduced(context),
        ),
      );
      try {
        final updated = await _repo.markMilestoneSeen(a);
        if (!mounted) return;
        setState(() {
          _addictions = [
            for (final x in _addictions) x.id == a.id ? updated : x,
          ];
        });
      } catch (_) {
        // Shown again on a later load.
      }
    }
  }

  /// Rebuilds the daily-check and habit reminders on the phone from what is
  /// on screen. With [ask], first asks for notification permission (when the
  /// patient sets a reminder). Never throws: reminders are rebuilt on the
  /// next load.
  Future<void> _syncReminders({bool ask = false}) async {
    final l10n = AppLocalizations.of(context);
    final now = _repo.now();
    try {
      if (ask) await ref.read(localNotificationsProvider).requestPermission();
      await ref
          .read(recoveryRemindersProvider)
          .sync(
            checkReminder: _reminder,
            habits: _habits,
            catalog: _catalog,
            now: now,
            l10n: l10n,
          );
    } catch (_) {
      // Rebuilt on the next load.
    }
  }

  void _retry() {
    setState(() => _loading = true);
    unawaited(_load());
  }

  /// The soonest upcoming appointment; none when booking can't be reached.
  Future<Appointment?> _nextAppointment() async {
    final booking = ref.read(bookingRepositoryProvider);
    try {
      final now = booking.now();
      final upcoming =
          (await booking.appointments())
              .where((a) => a.isUpcoming(now))
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));
      return upcoming.isEmpty ? null : upcoming.first;
    } catch (_) {
      return null;
    }
  }

  /// Runs a save; on failure tells the patient and keeps what the screen had.
  Future<T?> _saving<T>(Future<T> Function() save) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = AppLocalizations.of(context).recoverySaveError;
    try {
      return await save();
    } on RecoveryUnavailable {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(message)));
      return null;
    }
  }

  Future<void> _mark(Dose dose, DoseStatus status) async {
    final updated = await _saving(() => _repo.markDose(dose, status));
    if (updated == null || !mounted) return;
    setState(() {
      _doses = [for (final d in _doses) d.id == dose.id ? updated : d];
    });
  }

  Future<void> _relapse(Addiction addiction) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final report = await showRelapseSheet(context, now: _repo.now());
    if (report == null) return;
    final Addiction updated;
    try {
      updated = await _repo.logRelapse(
        addiction,
        note: report.note.isEmpty ? null : report.note,
        at: report.at,
      );
    } on RecoveryUnavailable {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.recoverySaveError)));
      return;
    }
    if (!mounted) return;
    setState(() {
      _addictions = [
        for (final a in _addictions) a.id == addiction.id ? updated : a,
      ];
    });
    messenger.showSnackBar(SnackBar(content: Text(l10n.recoveryRelapseDone)));
  }

  Future<void> _checkIn() async {
    final today = dayOf(_repo.now());
    final saved = await _saving(() async {
      await _repo.checkIn(today);
      return true;
    });
    if (saved == null || !mounted) return;
    setState(() => _checkIns = {..._checkIns, today});
  }

  /// Today's per-substance check (PRD 5.6); an addiction answered "used"
  /// then opens relapse logging, one after the other.
  Future<void> _openDailyCheck() async {
    final today = dayOf(_repo.now());
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final used = await Navigator.of(context).push<List<Addiction>>(
      appRoute(
        DailyCheckScreen(
          today: today,
          addictions: _addictions,
          profiles: _profiles,
          previous: _checks,
          habits: _habits,
          catalog: _catalog,
          onSave: (checks, habitsDone) async {
            try {
              for (final c in checks) {
                await _repo.saveCheck(c);
              }
              for (final MapEntry(key: habit, value: done)
                  in habitsDone.entries) {
                if (habit.days.contains(today) != done) {
                  await _repo.markHabit(habit, today, done: done);
                }
              }
              final (history, habits) = await (
                _repo.addictionChecks(),
                _repo.habits(),
              ).wait;
              if (!mounted) return;
              setState(() {
                _checks = history.checks;
                _doneDays = history.doneDays;
                _habits = habits;
              });
            } catch (_) {
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.recoverySaveError)),
              );
              rethrow;
            }
          },
        ),
        reduced: AppMotion.reduced(context),
      ),
    );
    if (used == null || !mounted) return;
    if (used.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.checkInDone)));
      return;
    }
    for (final a in used) {
      final current = _addictions.firstWhere((x) => x.id == a.id);
      await _relapse(current);
      if (!mounted) return;
    }
  }

  Future<void> _changeGoal(Addiction addiction) async {
    final now = _repo.now();
    final picked = await showGoalSheet(
      context,
      days: addiction.days(now),
      chosen: addiction.goalDays,
    );
    if (picked == null) return;
    final updated = await _saving(
      () => _repo.setGoal(addiction, picked == 0 ? null : picked),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _addictions = [
        for (final a in _addictions) a.id == addiction.id ? updated : a,
      ];
    });
  }

  void _replaceHabit(Habit updated) => setState(() {
    _habits = [for (final h in _habits) h.id == updated.id ? updated : h];
  });

  Future<void> _toggleHabit(Habit habit, bool done) async {
    final today = dayOf(_repo.now());
    final saved = await _saving(() async {
      await _repo.markHabit(habit, today, done: done);
      return true;
    });
    if (saved == null || !mounted) return;
    _replaceHabit(
      habit.copyWith(
        days: done ? {...habit.days, today} : ({...habit.days}..remove(today)),
      ),
    );
  }

  Future<void> _habitReminder(Habit habit) async {
    final picked = await pickTime(
      context,
      habit.reminder ?? (hour: 18, minute: 0),
    );
    if (picked == null) return;
    final updated = await _saving(() => _repo.setHabitReminder(habit, picked));
    if (updated == null || !mounted) return;
    _replaceHabit(updated);
    unawaited(_syncReminders(ask: true));
  }

  Future<void> _removeHabit(Habit habit) async {
    final saved = await _saving(() async {
      await _repo.removeHabit(habit);
      return true;
    });
    if (saved == null || !mounted) return;
    setState(
      () => _habits = [
        for (final h in _habits)
          if (h.id != habit.id) h,
      ],
    );
    unawaited(_syncReminders());
  }

  Future<void> _addHabit() async {
    final picked = await showAddHabitSheet(
      context,
      catalog: _catalog,
      kept: {for (final h in _habits) h.kind},
    );
    if (picked == null) return;
    final added = await _saving(
      () => _repo.addHabit(
        picked.kind,
        text: picked.text,
        reminder: picked.reminder,
      ),
    );
    if (added == null || !mounted) return;
    setState(() => _habits = [..._habits, added]);
    unawaited(_syncReminders(ask: added.reminder != null));
  }

  Future<void> _pickReminder() async {
    final picked = await pickTime(context, _reminder ?? (hour: 21, minute: 0));
    if (picked == null) return;
    final saved = await _saving(() async {
      await _repo.setReminder(picked);
      return true;
    });
    if (saved == null || !mounted) return;
    setState(() => _reminder = picked);
    unawaited(_syncReminders(ask: true));
  }

  Future<void> _stopReminder() async {
    final saved = await _saving(() async {
      await _repo.setReminder(null);
      return true;
    });
    if (saved == null || !mounted) return;
    setState(() => _reminder = null);
    unawaited(_syncReminders());
  }

  void _addAddiction() {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    unawaited(
      navigator.push<void>(
        appRoute(
          AddictionFormScreen(
            today: _repo.now(),
            profiles: _profiles,
            onSave: (entry) async {
              final Addiction added;
              try {
                added = await _repo.addAddiction(
                  type: entry.type,
                  profile: entry.profile,
                  substance: entry.substance,
                  cleanSince: entry.cleanSince,
                );
              } on RecoveryUnavailable {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.recoverySaveError)),
                );
                return;
              }
              if (!mounted) return;
              setState(() => _addictions = [..._addictions, added]);
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.addictionSaved)),
              );
            },
          ),
          reduced: AppMotion.reduced(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final now = _repo.now();

    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_locked) {
      body = RecoveryLockedView(
        onBook: () =>
            HomeShellScope.maybeOf(context)?.select(HomeTab.appointments),
      );
    } else if (_failed) {
      body = LoadError(onRetry: _retry);
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screenHorizontal,
          AppSpace.lg,
          AppSpace.screenHorizontal,
          AppSpace.xl,
        ),
        children: [
          StaggeredReveal(
            children: [
              if (_addictions.isEmpty)
                _EmptyCounters(onAdd: _addAddiction)
              else ...[
                for (final a in _addictions)
                  CounterCard(
                    addiction: a,
                    name: addictionName(context, a, _profiles),
                    note: profileOf(a, _profiles)?.noteFor(a.days(now)),
                    now: now,
                    onRelapse: () => _relapse(a),
                    onChangeGoal: () => _changeGoal(a),
                  ),
                TextButton.icon(
                  onPressed: _addAddiction,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.addictionAddAnother),
                ),
              ],
              // With an addiction, the day is done once each one was checked
              // (PRD 5.6); without, the simple "day without use" tick.
              WeekCheckCard(
                checkIns: _addictions.isEmpty ? _checkIns : _doneDays,
                now: now,
                reminder: _reminder,
                actionLabel: _addictions.isEmpty ? null : l10n.dailyCheckAction,
                onCheckIn: _addictions.isEmpty ? _checkIn : _openDailyCheck,
                onPickReminder: _pickReminder,
                onStopReminder: _stopReminder,
              ),
              HabitsCard(
                habits: _habits,
                catalog: _catalog,
                now: now,
                onToggle: _toggleHabit,
                onPickReminder: _habitReminder,
                onRemove: _removeHabit,
                onAdd: _addHabit,
              ),
              if (_next case final next?)
                NextAppointmentCard(
                  appointment: next,
                  onOpen: () => HomeShellScope.maybeOf(
                    context,
                  )?.select(HomeTab.appointments),
                ),
              DosesCard(doses: _doses, onMark: _mark),
              if (_quote case final quote?) QuoteCard(quote: quote),
              if (_clinic case final clinic?)
                ClinicCard(clinic: clinic, now: now),
            ],
          ),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screenHorizontal,
                AppSpace.sm,
                AppSpace.screenHorizontal,
                0,
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
                          child: Text(
                            l10n.recoveryTitle,
                            style: text.headlineLarge,
                          ),
                        ),
                        Text(
                          l10n.recoveryTagline,
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.textBody,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Articles can be read at any time (PRD 5.5), so the
                  // way in stays here even while tracking is locked.
                  IconButton(
                    onPressed: () => openArticles(context),
                    tooltip: l10n.articlesTitle,
                    icon: const Icon(
                      Icons.menu_book_rounded,
                      color: AppColors.teal700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// No addiction entered yet: invites the patient to add one.
class _EmptyCounters extends StatelessWidget {
  const _EmptyCounters({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          spacing: AppSpace.md,
          children: [
            const Icon(
              Icons.wb_twilight_rounded,
              size: 40,
              color: AppColors.sand500,
            ),
            Text(
              l10n.addictionEmpty,
              textAlign: TextAlign.center,
              style: text.bodyLarge,
            ),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.addictionAdd),
            ),
          ],
        ),
      ),
    );
  }
}
