import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_mark.dart';
import '../../widgets/staggered_reveal.dart';
import '../booking/booking_models.dart';
import '../booking/booking_repository.dart';
import '../booking/booking_widgets.dart';
import '../home/home_scope.dart';
import 'addiction_form_screen.dart';
import 'recovery_models.dart';
import 'recovery_repository.dart';
import 'recovery_widgets.dart';

/// The recovery home (PRD 5, 12.3): one day counter per addiction, this
/// week's daily check, today's doses, the next appointment, the quote of the
/// day and the practice.
class RecoveryScreen extends ConsumerStatefulWidget {
  const RecoveryScreen({super.key});

  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  List<Addiction> _addictions = const [];
  Set<DateTime> _checkIns = const {};
  DayTime? _reminder;
  Quote? _quote;
  List<Dose> _doses = const [];
  ClinicInfo? _clinic;
  Appointment? _next;
  bool _loading = true;
  bool _failed = false;

  RecoveryRepository get _repo => ref.read(recoveryRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final (addictions, checkIns, reminder, quote, doses, clinic) = await (
        _repo.addictions(),
        _repo.checkIns(),
        _repo.reminder(),
        _repo.quoteOfDay(),
        _repo.todaysDoses(),
        _repo.clinic(),
      ).wait;
      final next = await _nextAppointment();
      if (!mounted) return;
      setState(() {
        _addictions = addictions;
        _checkIns = checkIns;
        _reminder = reminder;
        _quote = quote;
        _doses = doses;
        _clinic = clinic;
        _next = next;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
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

  Future<void> _mark(Dose dose, DoseStatus status) async {
    final updated = await _repo.markDose(dose, status);
    if (!mounted) return;
    setState(() {
      _doses = [for (final d in _doses) d.id == dose.id ? updated : d];
    });
  }

  Future<void> _relapse(Addiction addiction) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final report = await showRelapseSheet(context, now: _repo.now());
    if (report == null) return;
    final updated = await _repo.logRelapse(
      addiction,
      note: report.note.isEmpty ? null : report.note,
      at: report.at,
    );
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
    await _repo.checkIn(today);
    if (!mounted) return;
    setState(() => _checkIns = {..._checkIns, today});
  }

  Future<void> _pickReminder() async {
    final picked = await pickTime(context, _reminder ?? (hour: 21, minute: 0));
    if (picked == null) return;
    await _repo.setReminder(picked);
    if (!mounted) return;
    setState(() => _reminder = picked);
  }

  Future<void> _stopReminder() async {
    await _repo.setReminder(null);
    if (!mounted) return;
    setState(() => _reminder = null);
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
            onSave: (entry) async {
              final added = await _repo.addAddiction(
                type: entry.type,
                substance: entry.substance,
                cleanSince: entry.cleanSince,
              );
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
                    now: now,
                    onRelapse: () => _relapse(a),
                  ),
                TextButton.icon(
                  onPressed: _addAddiction,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.addictionAddAnother),
                ),
              ],
              WeekCheckCard(
                checkIns: _checkIns,
                now: now,
                reminder: _reminder,
                onCheckIn: _checkIn,
                onPickReminder: _pickReminder,
                onStopReminder: _stopReminder,
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
