import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/staggered_reveal.dart';
import 'booking_format.dart';
import 'booking_models.dart';
import 'booking_repository.dart';
import 'booking_widgets.dart';

/// The patient's upcoming and past appointments. An upcoming appointment can
/// be cancelled until the notice period (24 h) starts. Under the upcoming
/// ones sits the suggested follow-up, 30 days after the latest visit.
class MyAppointmentsScreen extends ConsumerStatefulWidget {
  const MyAppointmentsScreen({
    super.key,
    required this.onBookNew,
    this.banner,
    this.showBack,
  });

  final VoidCallback onBookNew;

  /// Shown under the title, e.g. the "Complete your profile" card.
  final Widget? banner;

  /// Whether the title row has a back button. By default, when there is a
  /// screen to go back to; false as a tab of the home shell.
  final bool? showBack;

  @override
  ConsumerState<MyAppointmentsScreen> createState() =>
      _MyAppointmentsScreenState();
}

typedef _Data = ({List<Appointment> all, FollowUp? followUp});

class _MyAppointmentsScreenState extends ConsumerState<MyAppointmentsScreen> {
  late Future<_Data> _list = _load();
  bool _past = false;

  Future<_Data> _load() async {
    final repo = ref.read(bookingRepositoryProvider);
    final (all, followUp) = await (repo.appointments(), repo.followUp()).wait;
    return (all: all, followUp: followUp);
  }

  Future<void> _cancel(Appointment appointment) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(bookingRepositoryProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.apptCancelAsk),
        content: Text(l10n.apptCancelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.apptKeep),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.apptCancel),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.cancel(appointment);
      messenger.showSnackBar(SnackBar(content: Text(l10n.apptCancelled)));
    } on TooLateToCancel {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.apptLocked(repo.notice.inHours))),
      );
    } on SlotUnavailable {
      // Already gone on the server: say so, then show the fresh list.
      messenger.showSnackBar(SnackBar(content: Text(l10n.apptGone)));
    } on BookingUnavailable catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.bookingError(e))));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _list = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final repo = ref.read(bookingRepositoryProvider);
    final now = repo.now();

    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<_Data>(
          future: _list,
          builder: (context, snapshot) {
            final all = snapshot.data?.all ?? const <Appointment>[];
            final followUp = snapshot.data?.followUp;
            final overdue = followUp?.overdueOn(now) ?? false;
            // Shown when it can be booked now: due already, or inside the
            // booking window.
            final showFollowUp =
                followUp != null &&
                (overdue ||
                    followUp.day.isBefore(
                      DateTime(
                        now.year,
                        now.month,
                        now.day + repo.horizon.inDays,
                      ),
                    ));
            final upcoming = all.where((a) => a.isUpcoming(now)).toList();
            final past = all
                .where((a) => !a.isUpcoming(now))
                .toList()
                .reversed
                .toList();

            final Widget body;
            if (snapshot.hasError) {
              body = LoadError(
                onRetry: () => setState(() {
                  _list = _load();
                }),
              );
            } else if (!snapshot.hasData) {
              body = const Center(child: CircularProgressIndicator());
            } else {
              final items = _past ? past : upcoming;
              final empty = items.isEmpty && (_past || !showFollowUp);
              body = AnimatedSwitcher(
                duration: AppMotion.of(context, AppMotion.medium),
                child: empty
                    ? Center(
                        key: ValueKey('empty$_past'),
                        child: Text(
                          _past ? l10n.apptNoPast : l10n.apptNoUpcoming,
                          style: text.bodyLarge?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      )
                    : ListView(
                        key: ValueKey(_past),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.screenHorizontal,
                          AppSpace.lg,
                          AppSpace.screenHorizontal,
                          AppSpace.xl,
                        ),
                        children: [
                          if (_past)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpace.lg,
                                ),
                                child: Column(
                                  children: [
                                    for (var i = 0; i < items.length; i++) ...[
                                      if (i > 0) const Divider(),
                                      _PastRow(appointment: items[i]),
                                    ],
                                  ],
                                ),
                              ),
                            )
                          else
                            StaggeredReveal(
                              children: [
                                for (final a in items)
                                  _UpcomingCard(
                                    appointment: a,
                                    canCancel:
                                        a.start.difference(now) >= repo.notice,
                                    noticeHours: repo.notice.inHours,
                                    onCancel: () => _cancel(a),
                                  ),
                                if (followUp != null && showFollowUp)
                                  _FollowUpCard(
                                    followUp: followUp,
                                    overdue: overdue,
                                    onBook: widget.onBookNew,
                                  ),
                              ],
                            ),
                          if (_past) ...[
                            const SizedBox(height: AppSpace.md),
                            InfoLine(
                              text: l10n.apptPrivateNotes,
                              icon: Icons.lock_outline_rounded,
                              center: true,
                            ),
                          ],
                        ],
                      ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpace.xs,
                    AppSpace.sm,
                    AppSpace.screenHorizontal,
                    0,
                  ),
                  child: Row(
                    children: [
                      if (widget.showBack ?? Navigator.of(context).canPop())
                        const BackButton()
                      else
                        const SizedBox(width: AppSpace.lg),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            l10n.bookMyAppointments,
                            style: text.headlineLarge,
                          ),
                        ),
                      ),
                      IconButton.filled(
                        tooltip: l10n.apptNew,
                        onPressed: widget.onBookNew,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
                if (widget.banner case final banner?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.screenHorizontal,
                      AppSpace.lg,
                      AppSpace.screenHorizontal,
                      0,
                    ),
                    child: banner,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.screenHorizontal,
                    AppSpace.lg,
                    AppSpace.screenHorizontal,
                    0,
                  ),
                  child: _Tabs(
                    past: _past,
                    upcomingCount: upcoming.length,
                    onChanged: (past) => setState(() => _past = past),
                  ),
                ),
                Expanded(child: body),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.screenHorizontal,
                    0,
                    AppSpace.screenHorizontal,
                    AppSpace.lg,
                  ),
                  child: OutlinedButton.icon(
                    onPressed: widget.onBookNew,
                    icon: const Icon(Icons.event_available_rounded),
                    label: Text(l10n.apptNew),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Upcoming / past switch; the white thumb slides to the chosen side.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.past,
    required this.upcomingCount,
    required this.onChanged,
  });

  final bool past;
  final int upcomingCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget segment(String label, bool value) => Expanded(
      child: Semantics(
        button: true,
        selected: past == value,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(value),
          child: Center(
            child: Text(
              label,
              style: text.labelMedium?.copyWith(
                color: past == value ? AppColors.teal700 : AppColors.textMuted,
                fontWeight: past == value ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );

    return Container(
      height: 44,
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(
        color: AppColors.sand100,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: AppMotion.of(context, AppMotion.medium),
            curve: AppMotion.curve,
            alignment: AlignmentDirectional(past ? 1 : -1, 0),
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: AppShadows.sm,
                ),
              ),
            ),
          ),
          Row(
            children: [
              segment(l10n.apptUpcoming(upcomingCount), false),
              segment(l10n.apptPast, true),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.date, this.highlight = false});

  final DateTime date;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final fg = highlight ? AppColors.teal700 : AppColors.textStrong;
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: highlight ? AppColors.teal50 : AppColors.sand100,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Column(
        children: [
          Text('${date.day}', style: text.headlineMedium?.copyWith(color: fg)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              l10n.month(date),
              maxLines: 1,
              softWrap: false,
              style: text.bodySmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({
    required this.appointment,
    required this.canCancel,
    required this.noticeHours,
    required this.onCancel,
  });

  final Appointment appointment;
  final bool canCancel;
  final int noticeHours;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final a = appointment;
    // An unpaid hold is given back, not cancelled: the server cancels only
    // confirmed appointments.
    final confirmed = a.status == AppointmentStatus.confirmed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpace.md,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DateTile(
                  date: a.start,
                  highlight: a.status == AppointmentStatus.confirmed,
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.doctor.name(lang),
                        style: text.titleLarge?.copyWith(
                          fontSize: AppType.body.size,
                        ),
                      ),
                      Text(l10n.longDate(a.start), style: text.bodySmall),
                      LtrText(timeRange(a.start, a.end), style: text.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                StatusBadge(status: a.status),
              ],
            ),
            if (!a.method.online)
              InfoLine(
                text: l10n.bookToPay(a.priceDzd),
                icon: Icons.payments_outlined,
              ),
            if (a.checkinCode case final code? when confirmed)
              _BookingCode(code: code),
            if (confirmed && canCancel)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.border, width: 1.5),
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: onCancel,
                child: Text(l10n.apptCancel),
              )
            else if (confirmed)
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.sand100,
                  borderRadius: BorderRadius.circular(AppRadius.field),
                ),
                child: InfoLine(
                  text: l10n.apptLocked(noticeHours),
                  icon: Icons.lock_outline_rounded,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The booking code, as text: the patient gives it at the front desk, which
/// marks them arrived (PRD 4.3). The QR card is not built yet.
class _BookingCode extends StatelessWidget {
  const _BookingCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('appt-code'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.teal50,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.confirmation_number_outlined,
            color: AppColors.teal700,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(l10n.apptCode, style: text.bodySmall)),
          const SizedBox(width: AppSpace.sm),
          LtrText(
            code,
            style: text.titleLarge?.copyWith(color: AppColors.teal700),
          ),
        ],
      ),
    );
  }
}

/// The suggested next visit, with a shortcut to book it. Booking opens on
/// that day; the patient may still choose another one.
class _FollowUpCard extends StatelessWidget {
  const _FollowUpCard({
    required this.followUp,
    required this.overdue,
    required this.onBook,
  });

  final FollowUp followUp;
  final bool overdue;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final span = l10n.bookDays(followUp.days);
    final since = l10n.longDate(followUp.after.start);
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.teal50,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.teal100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpace.md,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FollowUpMark(),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.apptFollowUp,
                      style: text.labelMedium?.copyWith(
                        color: AppColors.teal700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      overdue
                          ? l10n.bookFollowUpOverdueTitle
                          : l10n.apptFollowUpWhen(l10n.longDate(followUp.day)),
                      style: text.titleLarge?.copyWith(
                        fontSize: AppType.body.size,
                      ),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      overdue
                          ? l10n.bookFollowUpOverdueBody(span, since)
                          : l10n.bookFollowUpBody(span, since),
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textBody,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: onBook,
            icon: const Icon(Icons.event_available_rounded, size: 20),
            label: Text(l10n.apptFollowUpBook),
          ),
        ],
      ),
    );
  }
}

class _PastRow extends StatelessWidget {
  const _PastRow({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final l10n = AppLocalizations.of(context);
    final a = appointment;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${a.start.day}', style: text.titleLarge),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    l10n.month(a.start),
                    maxLines: 1,
                    softWrap: false,
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.doctor.name(lang),
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textStrong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                LtrText(timeRange(a.start, a.end), style: text.bodySmall),
              ],
            ),
          ),
          StatusBadge(status: a.status),
        ],
      ),
    );
  }
}
