import 'package:benmahdia_mobile/features/booking/appointment_reminders.dart';
import 'package:benmahdia_mobile/features/recovery/fake_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_models.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_reminders.dart';
import 'package:benmahdia_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'appointment_reminders_test.dart' show FakeNotifications;

// Saturday 17 October 2026, 19:00, clinic time.
final _now = DateTime(2026, 10, 17, 19);

void main() {
  late FakeNotifications notifications;
  late RecoveryReminders reminders;
  late AppLocalizations fr;

  setUp(() async {
    notifications = FakeNotifications();
    reminders = RecoveryReminders(notifications);
    fr = await AppLocalizations.delegate.load(const Locale('fr'));
  });

  Future<void> sync({DayTime? check, List<Habit> habits = const []}) =>
      reminders.sync(
        checkReminder: check,
        habits: habits,
        catalog: sampleHabits,
        now: _now,
        l10n: fr,
      );

  test(
    'the daily check for the next seven days, from tomorrow if past',
    () async {
      await sync(check: (hour: 18, minute: 30));
      final times = [for (final r in notifications.scheduled.values) r.at]
        ..sort();
      expect(times, hasLength(RecoveryReminders.days));
      expect(times.first, DateTime(2026, 10, 18, 18, 30));
      expect(times.last, DateTime(2026, 10, 24, 18, 30));
      final r = notifications.scheduled.values.first;
      expect(r.title, 'Rappel');
      expect(r.body, "C'est l'heure de votre rappel du jour.");
    },
  );

  test('today still counts when the time is ahead', () async {
    await sync(check: (hour: 21, minute: 0));
    final first = [for (final r in notifications.scheduled.values) r.at]
      ..sort();
    expect(first.first, DateTime(2026, 10, 17, 21));
  });

  test('a habit from the list is named; one in own words is not', () async {
    await sync(
      habits: const [
        Habit(id: 'h1', kind: HabitKind.sport, reminder: (hour: 20, minute: 0)),
        Habit(
          id: 'h2',
          kind: HabitKind.custom,
          text: 'Jardiner',
          reminder: (hour: 8, minute: 0),
        ),
        Habit(id: 'h3', kind: HabitKind.water),
      ],
    );
    final bodies = {for (final r in notifications.scheduled.values) r.body};
    expect(bodies, {
      "C'est l'heure : Sport ou marche",
      "C'est l'heure de votre habitude.",
    });
    expect(notifications.scheduled, hasLength(2 * RecoveryReminders.days));
    expect(
      notifications.scheduled.values.any((r) => r.body.contains('Jardiner')),
      isFalse,
    );
  });

  test('turning reminders off cancels ours only', () async {
    notifications.scheduled[AppointmentReminders.base + 4] = (
      at: DateTime(2026, 10, 18, 9),
      title: 'Rappel',
      body: 'rendez-vous',
    );
    await sync(
      check: (hour: 21, minute: 0),
      habits: const [
        Habit(id: 'h1', kind: HabitKind.sport, reminder: (hour: 20, minute: 0)),
      ],
    );
    expect(notifications.scheduled, hasLength(1 + 2 * RecoveryReminders.days));
    await sync();
    expect(notifications.scheduled.keys, [AppointmentReminders.base + 4]);
  });

  test('ids stay clear of the appointment reminders', () {
    for (final id in ['h1', 'a-long-habit-id', '0']) {
      for (var day = 0; day < RecoveryReminders.days; day++) {
        final n = RecoveryReminders.habitId(id, day);
        expect(n, greaterThanOrEqualTo(RecoveryReminders.base));
        expect(n, lessThan(1 << 31));
      }
    }
    expect(
      RecoveryReminders.base,
      greaterThan(AppointmentReminders.base + 20000000),
    );
  });
}
