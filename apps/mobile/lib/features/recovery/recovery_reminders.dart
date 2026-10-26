import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/local_notifications.dart';
import '../../l10n/app_localizations.dart';
import 'recovery_models.dart';

/// The daily-check reminder (PRD 5.4) and each good habit's reminder (PRD
/// 5.6), scheduled on the phone for the next [days] days. [sync] rebuilds
/// them from what the patient set, so a reminder turned off or a habit
/// removed loses its notifications; the home calls it on every load, which
/// keeps the week ahead filled. The text stays neutral: a habit from the
/// clinic's list is named, one in the patient's own words is not, and the
/// daily check never names a substance.
class RecoveryReminders {
  RecoveryReminders(this._notifications);

  final LocalNotifications _notifications;

  /// Recovery reminders use ids from [base] up, after the appointment ones
  /// (AppointmentReminders.base).
  static const base = 200000000;
  static const days = 7;
  static const _buckets = 10000000;
  static const _span = (_buckets + 1) * days;

  static int _checkId(int day) => base + day;

  /// A stable id for one habit's reminder on one of the next [days] days.
  static int habitId(String habitId, int day) {
    // FNV-1a: the same habit always maps to the same ids.
    var h = 0x811c9dc5;
    for (final unit in habitId.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return base + days + (h % _buckets) * days + day;
  }

  static bool _ours(int id) => id >= base && id < base + _span;

  /// The next [days] times of day [time] from [now], soonest first.
  static List<DateTime> _next(DateTime now, DayTime time) {
    var at = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return [for (var i = 0; i < days; i++) at.add(Duration(days: i))];
  }

  Future<void> sync({
    required DayTime? checkReminder,
    required List<Habit> habits,
    required Map<HabitKind, LocalizedText> catalog,
    required DateTime now,
    required AppLocalizations l10n,
  }) async {
    final wanted = <int, ({DateTime at, String body})>{};
    if (checkReminder != null) {
      final times = _next(now, checkReminder);
      for (var i = 0; i < times.length; i++) {
        wanted[_checkId(i)] = (at: times[i], body: l10n.reminderDailyCheck);
      }
    }
    for (final h in habits) {
      final time = h.reminder;
      if (time == null) continue;
      final label = h.kind == HabitKind.custom
          ? null
          : catalog[h.kind]?.of(l10n.localeName);
      final body = label == null
          ? l10n.reminderHabitOwn
          : l10n.reminderHabit(label);
      final times = _next(now, time);
      for (var i = 0; i < times.length; i++) {
        wanted[habitId(h.id, i)] = (at: times[i], body: body);
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

final recoveryRemindersProvider = Provider<RecoveryReminders>(
  (ref) => RecoveryReminders(ref.read(localNotificationsProvider)),
);
