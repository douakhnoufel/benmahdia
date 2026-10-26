import 'package:benmahdia_mobile/core/notifications/local_notifications.dart';
import 'package:benmahdia_mobile/features/booking/appointment_reminders.dart';
import 'package:benmahdia_mobile/features/booking/booking_models.dart';
import 'package:benmahdia_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNotifications implements LocalNotifications {
  final scheduled = <int, ({DateTime at, String title, String body})>{};

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async => scheduled[id] = (at: at, title: title, body: body);

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<Set<int>> pending() async => scheduled.keys.toSet();
}

const _doctor = Doctor(
  id: 'd1',
  nameAr: 'د. عينة',
  nameFr: 'Dr Exemple',
  initialsAr: 'ع',
  initialsFr: 'DE',
  slotMinutes: 15,
  priceDzd: 2000,
);

Appointment _appt(String id, DateTime start, {AppointmentStatus? status}) =>
    Appointment(
      id: id,
      doctor: _doctor,
      start: start,
      end: start.add(const Duration(minutes: 15)),
      status: status ?? AppointmentStatus.confirmed,
      priceDzd: 2000,
      method: PaymentMethod.clinic,
    );

void main() {
  final now = DateTime(2026, 10, 26, 10);
  late FakeNotifications phone;
  late AppointmentReminders reminders;
  late AppLocalizations fr;
  late AppLocalizations ar;

  setUpAll(() async {
    fr = await AppLocalizations.delegate.load(const Locale('fr'));
    ar = await AppLocalizations.delegate.load(const Locale('ar'));
  });

  setUp(() {
    phone = FakeNotifications();
    reminders = AppointmentReminders(phone);
  });

  int day(String id) => AppointmentReminders.idFor(id, dayBefore: true);
  int hour(String id) => AppointmentReminders.idFor(id, dayBefore: false);

  test('a confirmed visit gets a 24 h and a 1 h reminder', () async {
    final start = DateTime(2026, 10, 28, 9, 30);
    await reminders.sync([_appt('a', start)], now: now, l10n: fr);
    expect(phone.scheduled.keys, unorderedEquals([day('a'), hour('a')]));
    expect(phone.scheduled[day('a')]!.at, DateTime(2026, 10, 27, 9, 30));
    expect(phone.scheduled[hour('a')]!.at, DateTime(2026, 10, 28, 8, 30));
  });

  test('the text says only the time, in the patient language', () async {
    final start = DateTime(2026, 10, 28, 9, 30);
    await reminders.sync([_appt('a', start)], now: now, l10n: fr);
    final r = phone.scheduled[day('a')]!;
    expect(r.title, 'Rappel');
    expect(r.body, 'Votre rendez-vous est demain à 09:30.');
    expect(r.body, isNot(contains('Dr')));
    await reminders.sync([_appt('a', start)], now: now, l10n: ar);
    expect(
      phone.scheduled[hour('a')]!.body,
      'موعدك بعد ساعة، على الساعة 09:30.',
    );
  });

  test('reminders already in the past are skipped', () async {
    // Tomorrow 09:30: its 24 h reminder (today 09:30) is past, the 1 h one
    // is not. Today 10:40: both are past.
    await reminders.sync(
      [
        _appt('soon', DateTime(2026, 10, 27, 9, 30)),
        _appt('now', DateTime(2026, 10, 26, 10, 40)),
      ],
      now: now,
      l10n: fr,
    );
    expect(phone.scheduled.keys, unorderedEquals([hour('soon')]));
  });

  test('holds, cancelled and past visits get none', () async {
    await reminders.sync(
      [
        _appt(
          'h',
          DateTime(2026, 10, 29, 9),
          status: AppointmentStatus.awaitingPayment,
        ),
        _appt(
          'c',
          DateTime(2026, 10, 29, 10),
          status: AppointmentStatus.cancelled,
        ),
        _appt(
          'p',
          DateTime(2026, 10, 20, 9),
          status: AppointmentStatus.completed,
        ),
      ],
      now: now,
      l10n: fr,
    );
    expect(phone.scheduled, isEmpty);
  });

  test(
    'a visit cancelled elsewhere loses its reminders, others stay',
    () async {
      await phone.schedule(id: 7, at: now, title: 'medicine', body: '');
      final a = _appt('a', DateTime(2026, 10, 28, 9));
      final b = _appt('b', DateTime(2026, 10, 29, 9));
      await reminders.sync([a, b], now: now, l10n: fr);
      await reminders.sync(
        [a, b.withStatus(AppointmentStatus.cancelled)],
        now: now,
        l10n: fr,
      );
      expect(phone.scheduled.keys, unorderedEquals([7, day('a'), hour('a')]));
    },
  );

  test('ids are stable and stay in the appointment range', () {
    expect(day('x'), AppointmentReminders.idFor('x', dayBefore: true));
    expect(hour('x'), day('x') + 1);
    expect(day('x'), greaterThanOrEqualTo(AppointmentReminders.base));
  });
}
