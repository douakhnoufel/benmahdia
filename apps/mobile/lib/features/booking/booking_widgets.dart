import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import 'booking_models.dart';

/// Round initials for a doctor.
class DoctorAvatar extends StatelessWidget {
  const DoctorAvatar({super.key, required this.initials, this.size = 48});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.teal50,
          shape: BoxShape.circle,
        ),
        child: Text(
          initials,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.teal700,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Appointment status as a pill: icon + word, so colour is never the only
/// signal.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, icon, color) = switch (status) {
      AppointmentStatus.confirmed => (
        l10n.apptConfirmed,
        Icons.check_rounded,
        AppColors.success,
      ),
      AppointmentStatus.awaitingPayment => (
        l10n.apptAwaitingPayment,
        Icons.schedule_rounded,
        AppColors.warning,
      ),
      AppointmentStatus.completed => (
        l10n.apptCompleted,
        Icons.done_all_rounded,
        AppColors.teal500,
      ),
      AppointmentStatus.cancelled => (
        l10n.apptCancelledStatus,
        Icons.block_rounded,
        AppColors.textMuted,
      ),
      AppointmentStatus.noShow => (
        l10n.apptNoShow,
        Icons.event_busy_rounded,
        AppColors.danger,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.tint(color),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpace.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textStrong,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small heading with an icon, e.g. "Morning".
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.sand500),
        const SizedBox(width: AppSpace.sm),
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.textBody),
        ),
      ],
    );
  }
}

/// A short line of helper text with a leading icon.
class InfoLine extends StatelessWidget {
  const InfoLine({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.center = false,
  });

  final String text;
  final IconData icon;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs / 2),
          child: Icon(icon, size: 16, color: AppColors.textMuted),
        ),
        const SizedBox(width: AppSpace.sm),
        Flexible(
          child: Text(
            text,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Shown when loading fails; offers a retry.
class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.bookLoadError,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpace.md),
            OutlinedButton(onPressed: onRetry, child: Text(l10n.bookRetry)),
          ],
        ),
      ),
    );
  }
}

/// Bottom action area: white, with a top hairline.
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenHorizontal,
            AppSpace.md,
            AppSpace.screenHorizontal,
            AppSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpace.sm,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Times like "09:30 – 09:45" stay left-to-right inside Arabic text.
class LtrText extends StatelessWidget {
  const LtrText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) =>
      Text(text, textDirection: TextDirection.ltr, style: style);
}

/// The flag that marks a suggested follow-up: on the day strip ([small]),
/// and on the follow-up banner and card.
class FollowUpMark extends StatelessWidget {
  const FollowUpMark({super.key, this.small = false});

  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 18.0 : 36.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: small ? AppColors.teal700 : AppColors.surface,
        shape: BoxShape.circle,
        border: small ? Border.all(color: AppColors.surface, width: 2) : null,
      ),
      child: Icon(
        Icons.flag_rounded,
        size: small ? 10 : 20,
        color: small ? AppColors.onPrimary : AppColors.teal600,
      ),
    );
  }
}
