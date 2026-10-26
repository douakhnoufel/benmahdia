import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/local_notifications.dart';
import '../../l10n/app_localizations.dart';
import 'booking_format.dart';
import 'booking_models.dart';
import 'booking_repository.dart';

/// The 24 h and 1 h reminders before each confirmed appointment (PRD 4.3),
/// scheduled on the phone. [sync] rebuilds them from the appointment list,
/// so a visit cancelled anywhere loses its reminders and a new phone gets
/// them back. The text says only the time: no doctor, no clinic.
class AppointmentReminders {
  AppointmentReminders(this._notifications);

  final LocalNotifications _notifications;

  /// Appointment reminders use ids from [base] up; other reminders (medicines,
  /// daily check) must stay outside [base, base + _span).
  static const base = 100000000;
  static const _span = 2 * _buckets;
  static const _buckets = 10000000;

  static const _dayBefore = Duration(hours: 24);
  static const _hourBefore = Duration(hours: 1);

  /// A stable id for one reminder of one appointment.
  static int idFor(String appointmentId, {required bool dayBefore}) {
    // FNV-1a: the same appointment always maps to the same ids.
    var h = 0x811c9dc5;
    for (final unit in appointmentId.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return base + (h % _buckets) * 2 + (dayBefore ? 0 : 1);
  }

  static bool _ours(int id) => id >= base && id < base + _span;

  /// Schedules the reminders [appointments] need from [now] (clinic time) and
  /// cancels any other appointment reminder still pending.
  Future<void> sync(
    List<Appointment> appointments, {
    required DateTime now,
    required AppLocalizations l10n,
  }) async {
    final wanted = <int, ({DateTime at, String body})>{};
    for (final a in appointments) {
      if (a.status != AppointmentStatus.confirmed || !a.start.isAfter(now)) {
        continue;
      }
      final time = hhmm(a.start);
      final dayBefore = a.start.subtract(_dayBefore);
      if (dayBefore.isAfter(now)) {
        wanted[idFor(a.id, dayBefore: true)] = (
          at: dayBefore,
          body: l10n.reminderTomorrow(time),
        );
      }
      final hourBefore = a.start.subtract(_hourBefore);
      if (hourBefore.isAfter(now)) {
        wanted[idFor(a.id, dayBefore: false)] = (
          at: hourBefore,
          body: l10n.reminderSoon(time),
        );
      }
    }
    for (final id in await _notifications.pending()) {
      if (_ours(id) && !wanted.containsKey(id)) {
        await _notifications.cancel(id);
      }
    }
    for (final MapEntry(key: id, value: r) in wanted.entries) {
      await _notifications.schedule(
        id: id,
        at: r.at,
        title: l10n.reminderTitle,
        body: r.body,
      );
    }
  }
}

final appointmentRemindersProvider = Provider<AppointmentReminders>(
  (ref) => AppointmentReminders(ref.read(localNotificationsProvider)),
);

/// Re-reads the patient's appointments and rebuilds their reminders. With
/// [ask], first asks for notification permission (after a booking, not at
/// app start). Never throws: a reminder problem must not break booking.
Future<void> refreshReminders(
  WidgetRef ref,
  AppLocalizations l10n, {
  bool ask = false,
}) async {
  try {
    if (ask) await ref.read(localNotificationsProvider).requestPermission();
    final repo = ref.read(bookingRepositoryProvider);
    await ref
        .read(appointmentRemindersProvider)
        .sync(await repo.appointments(), now: repo.now(), l10n: l10n);
  } catch (_) {
    // Reminders are rebuilt on the next refresh.
  }
}
