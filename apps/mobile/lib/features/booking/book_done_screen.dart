import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/entrance.dart';
import 'booking_format.dart';
import 'booking_models.dart';
import 'booking_repository.dart';
import 'booking_widgets.dart';

/// Shown once the appointment is booked: a check pops in, then the ticket,
/// the reminders (24 h and 1 h before) and the way to cancel.
class BookDoneScreen extends StatelessWidget {
  const BookDoneScreen({
    super.key,
    required this.appointment,
    required this.onAppointments,
    required this.onHome,
  });

  final Appointment appointment;
  final VoidCallback onAppointments;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final paid = appointment.method.online;

    // Going back would land on an expired payment step; go home instead.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onHome();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.screenHorizontal,
                    AppSpace.xxl,
                    AppSpace.screenHorizontal,
                    AppSpace.xl,
                  ),
                  children: [
                    const Center(child: _SuccessMark()),
                    const SizedBox(height: AppSpace.lg),
                    Entrance(
                      offset: AppSpace.lg,
                      child: Column(
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              paid
                                  ? l10n.bookDoneTitle
                                  : l10n.bookDoneTitleClinic,
                              textAlign: TextAlign.center,
                              style: text.headlineLarge,
                            ),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            paid
                                ? l10n.bookDoneBodyPaid
                                : l10n.bookDoneBodyClinic,
                            textAlign: TextAlign.center,
                            style: text.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    Entrance(child: _Ticket(appointment: appointment)),
                    const SizedBox(height: AppSpace.lg),
                    const Entrance(child: _Reminders()),
                    const SizedBox(height: AppSpace.lg),
                    Consumer(
                      builder: (context, ref, _) => InfoLine(
                        text: l10n.bookChangeHint(
                          ref.read(bookingRepositoryProvider).notice.inHours,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.screenHorizontal,
                  0,
                  AppSpace.screenHorizontal,
                  AppSpace.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpace.xs,
                  children: [
                    FilledButton(
                      onPressed: onAppointments,
                      child: Text(l10n.bookMyAppointments),
                    ),
                    TextButton(onPressed: onHome, child: Text(l10n.bookHome)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessMark extends StatelessWidget {
  const _SuccessMark();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.of(context, AppMotion.slow),
        curve: AppMotion.pop,
        builder: (context, value, child) =>
            Transform.scale(scale: value, child: child),
        child: Container(
          width: 112,
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.tint(AppColors.success),
            shape: BoxShape.circle,
          ),
          child: Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                boxShadow: AppShadows.lg,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: AppSpace.xxl,
                color: AppColors.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ticket extends StatelessWidget {
  const _Ticket({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final a = appointment;
    final onTeal = text.bodySmall?.copyWith(color: AppColors.onPrimary);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.lg,
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 92,
                  color: AppColors.teal500,
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(l10n.shortWeekday(a.start), style: onTeal),
                      Text(
                        '${a.start.day}',
                        style: text.displayLarge?.copyWith(
                          color: AppColors.onPrimary,
                        ),
                      ),
                      Text(l10n.month(a.start), style: onTeal),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: AppSpace.xs,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: LtrText(
                                timeRange(a.start, a.end),
                                style: text.titleLarge,
                              ),
                            ),
                            StatusBadge(status: a.status),
                          ],
                        ),
                        Text(
                          a.doctor.name(lang),
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.textStrong,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(l10n.bookClinic, style: text.bodySmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.md,
            ),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Text(
              a.method.online
                  ? l10n.bookPaid(a.priceDzd)
                  : l10n.bookToPay(a.priceDzd),
              style: text.bodySmall?.copyWith(color: AppColors.textStrong),
            ),
          ),
        ],
      ),
    );
  }
}

class _Reminders extends StatelessWidget {
  const _Reminders();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget chip(String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Text(
          label,
          style: text.bodySmall?.copyWith(color: AppColors.textStrong),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.teal50,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpace.md,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                size: 20,
                color: AppColors.teal600,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(l10n.bookRemind, style: text.labelMedium)),
            ],
          ),
          Row(
            spacing: AppSpace.sm,
            children: [chip(l10n.bookRemind24), chip(l10n.bookRemind1)],
          ),
        ],
      ),
    );
  }
}
