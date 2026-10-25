import 'package:benmahdia_mobile/features/booking/book_confirm_screen.dart';
import 'package:benmahdia_mobile/features/booking/book_doctor_screen.dart';
import 'package:benmahdia_mobile/features/booking/book_done_screen.dart';
import 'package:benmahdia_mobile/features/booking/book_slot_screen.dart';
import 'package:benmahdia_mobile/features/booking/booking_flow.dart';
import 'package:benmahdia_mobile/features/booking/booking_models.dart';
import 'package:benmahdia_mobile/features/booking/booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/fake_booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/my_appointments_screen.dart';
import 'package:benmahdia_mobile/features/booking/payment_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// Saturday 17 October 2026, 17:10 clinic time.
final _now = DateTime(2026, 10, 17, 17, 10);
// Monday 19 October 09:00: the first free slot after the 24 h notice.
final _monday9 = DateTime(2026, 10, 19, 9);

const _doctorAr = 'د. بن مهدية حسين';
const _second = Duration(seconds: 1);

// Sample history: the latest visit is Sunday 18 October 09:30, so the
// follow-up is suggested for Tuesday 17 November.
FakeBookingRepository _repo() => FakeBookingRepository(clock: () => _now);

// A patient with no visit yet: no follow-up to suggest.
FakeBookingRepository _newPatient({List<Appointment> history = const []}) =>
    FakeBookingRepository(clock: () => _now, history: history);

Appointment _visit(DateTime start, AppointmentStatus status) => Appointment(
  id: 'v${start.month}-${start.day}',
  doctor: FakeBookingRepository.sampleDoctor,
  start: start,
  end: start.add(const Duration(minutes: 15)),
  status: status,
  priceDzd: 2000,
  method: PaymentMethod.edahabia,
);

List<Override> _with(BookingRepository repo) => [
  bookingRepositoryProvider.overrideWithValue(repo),
];

Future<Doctor> _doctor(BookingRepository repo) async =>
    (await repo.doctors()).single;

/// The sample agenda, but card payments go through a checkout the server
/// confirms, like the real API.
class _CheckoutRepo extends FakeBookingRepository {
  _CheckoutRepo() : super(clock: () => _now);

  /// What [paid] answers next: null = still waiting.
  Appointment? confirmed;
  bool lost = false;
  final checkouts = <PaymentMethod>[];
  var released = 0;

  @override
  bool get cardsUseCheckout => true;

  @override
  Future<Uri> checkout(Hold hold, PaymentMethod method) async {
    checkouts.add(method);
    return Uri.parse('https://pay.example.invalid/${hold.id}');
  }

  @override
  Future<Appointment?> paid(Hold hold) async {
    if (lost) throw const SlotUnavailable();
    return confirmed;
  }

  @override
  Future<void> release(Hold hold) async {
    released++;
    await super.release(hold);
  }
}

void main() {
  group('BookDoctorScreen', () {
    testWidgets('shows the doctor, price and next free time', (tester) async {
      Doctor? next;
      final repo = _repo();
      await pumpApp(
        tester,
        BookDoctorScreen(onNext: (d) => next = d),
        overrides: _with(repo),
      );
      await pumpFor(tester, _second);

      expect(find.text(_doctorAr), findsOneWidget);
      expect(find.textContaining('2000 دج'), findsOneWidget);
      expect(find.text('أقرب موعد: الاثنين 19 أكتوبر · 09:00'), findsOneWidget);

      // A single doctor is picked already.
      await tester.tap(find.text('اختيار اليوم والوقت'));
      expect(next?.id, 'benmahdia');
    });

    testWidgets('French', (tester) async {
      await pumpApp(
        tester,
        BookDoctorScreen(onNext: (_) {}),
        overrides: _with(_repo()),
      );
      await useFrench(tester);
      await pumpFor(tester, _second);
      expect(find.text('Dr Benmahdia Hocine'), findsOneWidget);
      expect(find.textContaining('2000 DA'), findsOneWidget);
      expect(
        find.text('Prochain créneau : lundi 19 octobre · 09:00'),
        findsOneWidget,
      );
    });
  });

  group('BookSlotScreen', () {
    testWidgets('opens on the first day with a free slot', (tester) async {
      final repo = _newPatient();
      await pumpApp(
        tester,
        BookSlotScreen(doctor: await _doctor(repo), onNext: (_) {}),
        overrides: _with(repo),
      );
      await pumpFor(tester, _second);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('اختر وقتاً للمتابعة'), findsOneWidget);
    });

    testWidgets('today is too soon and Friday is closed', (tester) async {
      final repo = _newPatient();
      await pumpApp(
        tester,
        BookSlotScreen(doctor: await _doctor(repo), onNext: (_) {}),
        overrides: _with(repo),
      );
      await pumpFor(tester, _second);

      await tester.tap(find.text('17').first);
      await pumpFor(tester, _second);
      expect(find.text('لا مواعيد في هذا اليوم'), findsOneWidget);
      expect(
        find.text('يكون الحجز قبل 24 ساعة على الأقل من الموعد.'),
        findsOneWidget,
      );

      await tester.tap(find.text('23').first);
      await pumpFor(tester, _second);
      expect(
        find.text('لا يستقبل الطبيب المرضى في هذا اليوم.'),
        findsOneWidget,
      );
    });

    testWidgets('a taken time cannot be picked', (tester) async {
      final repo = _newPatient();
      await pumpApp(
        tester,
        BookSlotScreen(doctor: await _doctor(repo), onNext: (_) {}),
        overrides: _with(repo),
      );
      await pumpFor(tester, _second);
      // 10:00 on Monday is taken in the sample agenda.
      await tester.tap(find.text('10:00'));
      await pumpFor(tester, _second);
      expect(find.text('اختر وقتاً للمتابعة'), findsOneWidget);
    });

    testWidgets('picking a time and continuing holds it', (tester) async {
      Hold? hold;
      final repo = _newPatient();
      await pumpApp(
        tester,
        BookSlotScreen(doctor: await _doctor(repo), onNext: (h) => hold = h),
        overrides: _with(repo),
      );
      await pumpFor(tester, _second);
      await tester.tap(find.text('09:00'));
      await pumpFor(tester, _second);
      expect(find.text('الاثنين 19 أكتوبر · 09:00'), findsOneWidget);

      await tester.tap(find.text('متابعة'));
      await pumpFor(tester, _second);
      expect(hold?.start, _monday9);
      expect(hold?.expiresAt, _now.add(const Duration(minutes: 15)));
    });
  });

  group('Follow-up', () {
    test('booking window is 60 days', () async {
      final repo = _repo();
      final days = await repo.calendar(await _doctor(repo));
      expect(days, hasLength(60));
      expect(days.first.day, DateTime(2026, 10, 17));
      expect(days.last.day, DateTime(2026, 12, 15));
    });

    test('suggested 30 days after the latest visit', () async {
      final f = await _repo().followUp();
      expect(f?.after.start, DateTime(2026, 10, 18, 9, 30));
      expect(f?.day, DateTime(2026, 11, 17));
      expect(f?.days, 30);
      expect(await _newPatient().followUp(), isNull);
    });

    test('cancelled and missed appointments do not count', () async {
      final f = await _newPatient(
        history: [
          _visit(DateTime(2026, 9, 1, 10), AppointmentStatus.completed),
          _visit(DateTime(2026, 9, 20, 10), AppointmentStatus.noShow),
          _visit(DateTime(2026, 10, 1, 10), AppointmentStatus.cancelled),
        ],
      ).followUp();
      expect(f?.day, DateTime(2026, 10, 1));
      expect(f?.overdueOn(_now), isTrue);
    });

    testWidgets('opens on the suggested day; earlier days stay open', (
      tester,
    ) async {
      final repo = _repo();
      await pumpApp(
        tester,
        BookSlotScreen(doctor: await _doctor(repo), onNext: (_) {}),
        overrides: _with(repo),
      );
      await pumpFor(tester, _second);
      expect(
        find.text('المتابعة المقترحة: حوالي الثلاثاء 17 نوفمبر'),
        findsOneWidget,
      );
      expect(
        find.text(
          'بعد 30 يوماً من موعدك يوم الأحد 18 أكتوبر. '
          'يمكنك اختيار يوم قبله أو بعده.',
        ),
        findsOneWidget,
      );
      expect(find.text('نوفمبر 2026'), findsOneWidget);
      expect(find.text('عرض اليوم المقترح'), findsNothing);

      await tester.tap(find.text('09:00'));
      await pumpFor(tester, _second);
      expect(find.text('الثلاثاء 17 نوفمبر · 09:00'), findsOneWidget);

      // A day earlier is fine too, and the banner offers the way back.
      await tester.tap(find.text('16'));
      await pumpFor(tester, _second);
      await tester.tap(find.text('09:00'));
      await pumpFor(tester, _second);
      expect(find.text('الاثنين 16 نوفمبر · 09:00'), findsOneWidget);

      await tester.tap(find.text('عرض اليوم المقترح'));
      await pumpFor(tester, _second);
      expect(find.text('اختر وقتاً للمتابعة'), findsOneWidget);
      await tester.tap(find.text('09:00'));
      await pumpFor(tester, _second);
      expect(find.text('الثلاثاء 17 نوفمبر · 09:00'), findsOneWidget);
    });

    testWidgets('a follow-up on a Friday opens the nearest open day', (
      tester,
    ) async {
      final repo = _newPatient(
        history: [
          _visit(DateTime(2026, 10, 21, 9), AppointmentStatus.confirmed),
        ],
      );
      await pumpApp(
        tester,
        BookSlotScreen(doctor: await _doctor(repo), onNext: (_) {}),
        overrides: _with(repo),
      );
      await pumpFor(tester, _second);
      expect(
        find.text('المتابعة المقترحة: حوالي الجمعة 20 نوفمبر'),
        findsOneWidget,
      );
      await tester.tap(find.text('09:00'));
      await pumpFor(tester, _second);
      expect(find.text('الخميس 19 نوفمبر · 09:00'), findsOneWidget);
    });

    testWidgets('overdue: opens on the first free day', (tester) async {
      final repo = _newPatient(
        history: [
          _visit(DateTime(2026, 9, 1, 10), AppointmentStatus.completed),
        ],
      );
      await pumpApp(
        tester,
        BookSlotScreen(doctor: await _doctor(repo), onNext: (_) {}),
        overrides: _with(repo),
      );
      await pumpFor(tester, _second);
      expect(find.text('حان وقت موعد المتابعة'), findsOneWidget);
      expect(
        find.text(
          'مرّ أكثر من 30 يوماً على موعدك يوم الثلاثاء 1 سبتمبر. '
          'اختر الوقت الذي يناسبك.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('09:00'));
      await pumpFor(tester, _second);
      expect(find.text('الاثنين 19 أكتوبر · 09:00'), findsOneWidget);
    });

    testWidgets('French', (tester) async {
      final repo = _repo();
      await pumpApp(
        tester,
        BookSlotScreen(doctor: await _doctor(repo), onNext: (_) {}),
        overrides: _with(repo),
      );
      await useFrench(tester);
      await pumpFor(tester, _second);
      expect(
        find.text('Suivi conseillé : vers le mardi 17 novembre'),
        findsOneWidget,
      );
      expect(
        find.text(
          '30 jours après votre rendez-vous du dimanche 18 octobre. '
          'Vous pouvez choisir un jour avant ou après.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('my appointments suggests booking it', (tester) async {
      var booked = 0;
      await pumpApp(
        tester,
        MyAppointmentsScreen(onBookNew: () => booked++),
        overrides: _with(_repo()),
      );
      await pumpFor(tester, _second);
      expect(find.text('المتابعة القادمة'), findsOneWidget);
      expect(find.text('حوالي الثلاثاء 17 نوفمبر'), findsOneWidget);
      await tester.tap(find.text('احجز موعد المتابعة'));
      expect(booked, 1);
    });

    testWidgets('a new patient gets no suggestion', (tester) async {
      await pumpApp(
        tester,
        MyAppointmentsScreen(onBookNew: () {}),
        overrides: _with(_newPatient()),
      );
      await pumpFor(tester, _second);
      expect(find.text('المتابعة القادمة'), findsNothing);
      expect(find.text('لا مواعيد قادمة'), findsOneWidget);
    });
  });

  group('BookConfirmScreen', () {
    Future<Hold> held(FakeBookingRepository repo) async =>
        repo.hold(await _doctor(repo), _monday9);

    testWidgets('counts down the hold', (tester) async {
      final repo = _repo();
      await pumpApp(
        tester,
        BookConfirmScreen(
          hold: await held(repo),
          onDone: (_) {},
          onExpired: () {},
        ),
        overrides: _with(repo),
      );
      await tester.pump();
      expect(find.text('محجوز لك لمدة 15:00'), findsOneWidget);
      await tester.pump(_second);
      expect(find.text('محجوز لك لمدة 14:59'), findsOneWidget);
    });

    testWidgets('card payment by default; clinic changes the button', (
      tester,
    ) async {
      Appointment? booked;
      final repo = _repo();
      await pumpApp(
        tester,
        BookConfirmScreen(
          hold: await held(repo),
          onDone: (a) => booked = a,
          onExpired: () {},
        ),
        overrides: _with(repo),
      );
      await pumpFor(tester, _second);
      expect(find.text('ادفع 2000 دج'), findsOneWidget);

      await tester.tap(find.text('الدفع في العيادة'));
      await pumpFor(tester, _second);
      expect(find.text('تأكيد الحجز'), findsOneWidget);

      await tester.tap(find.text('تأكيد الحجز'));
      await pumpFor(tester, _second);
      expect(booked?.method, PaymentMethod.clinic);
      expect(booked?.status, AppointmentStatus.confirmed);
      expect(booked?.priceDzd, 2000);
    });

    testWidgets('card payment opens Chargily and waits for the server', (
      tester,
    ) async {
      Appointment? booked;
      final opened = <Uri>[];
      final repo = _CheckoutRepo();
      final hold = await held(repo);
      await pumpApp(
        tester,
        BookConfirmScreen(
          hold: hold,
          onDone: (a) => booked = a,
          onExpired: () {},
        ),
        overrides: [
          ..._with(repo),
          openUrlProvider.overrideWithValue((url) async {
            opened.add(url);
            return true;
          }),
        ],
      );
      await pumpFor(tester, _second);
      await tester.tap(find.text('ادفع 2000 دج'));
      await pumpFor(tester, const Duration(seconds: 4));
      expect(repo.checkouts, [PaymentMethod.edahabia]);
      expect(opened.single.host, 'pay.example.invalid');
      expect(booked, isNull);

      repo.confirmed = _visit(_monday9, AppointmentStatus.confirmed);
      await pumpFor(tester, const Duration(seconds: 4));
      expect(booked?.status, AppointmentStatus.confirmed);
      expect(repo.released, 0);
    });

    testWidgets('a failed card payment shows the time-up view', (tester) async {
      var expired = 0;
      final repo = _CheckoutRepo();
      await pumpApp(
        tester,
        BookConfirmScreen(
          hold: await held(repo),
          onDone: (_) {},
          onExpired: () => expired++,
        ),
        overrides: [
          ..._with(repo),
          openUrlProvider.overrideWithValue((_) async => true),
        ],
      );
      await pumpFor(tester, _second);
      await tester.tap(find.text('ادفع 2000 دج'));
      await pumpFor(tester, _second);
      repo.lost = true;
      await pumpFor(tester, const Duration(seconds: 4));
      expect(find.text('ادفع 2000 دج'), findsNothing);
      // The server already gave the slot back; the app does not release it.
      expect(repo.released, 0);
    });

    testWidgets('when time runs out the slot is released', (tester) async {
      var expired = 0;
      final repo = _repo();
      final doctor = await _doctor(repo);
      await pumpApp(
        tester,
        BookConfirmScreen(
          hold: await held(repo),
          onDone: (_) {},
          onExpired: () => expired++,
        ),
        overrides: _with(repo),
      );
      await tester.pump();
      await tester.pump(const Duration(minutes: 15));
      await pumpFor(tester, _second);
      expect(find.text('انتهت مدة الحجز'), findsOneWidget);

      await tester.tap(find.text('اختر وقتاً آخر'));
      expect(expired, 1);
      // Free again for anyone.
      final again = await repo.hold(doctor, _monday9);
      expect(again.start, _monday9);
    });
  });

  group('BookDoneScreen', () {
    Appointment appt(PaymentMethod method) => Appointment(
      id: 'a1',
      doctor: const Doctor(
        id: 'benmahdia',
        nameAr: _doctorAr,
        nameFr: 'Dr Benmahdia Hocine',
        initialsAr: 'ب ح',
        initialsFr: 'BH',
        slotMinutes: 15,
        priceDzd: 2000,
      ),
      start: _monday9,
      end: _monday9.add(const Duration(minutes: 15)),
      status: AppointmentStatus.confirmed,
      priceDzd: 2000,
      method: method,
    );

    testWidgets('paid by card', (tester) async {
      await pumpApp(
        tester,
        BookDoneScreen(
          appointment: appt(PaymentMethod.cib),
          onAppointments: () {},
          onHome: () {},
        ),
      );
      await pumpFor(tester, _second);
      expect(find.text('تم تأكيد موعدك'), findsOneWidget);
      expect(find.text('المبلغ المدفوع: 2000 دج'), findsOneWidget);
      expect(find.text('09:00 – 09:15'), findsOneWidget);
    });

    testWidgets('pay at the clinic', (tester) async {
      var appointments = 0;
      await pumpApp(
        tester,
        BookDoneScreen(
          appointment: appt(PaymentMethod.clinic),
          onAppointments: () => appointments++,
          onHome: () {},
        ),
      );
      await pumpFor(tester, _second);
      expect(find.text('تم حجز موعدك'), findsOneWidget);
      expect(find.text('يُدفع في العيادة: 2000 دج'), findsOneWidget);
      await tester.tap(find.text('مواعيدي'));
      expect(appointments, 1);
    });
  });

  group('MyAppointmentsScreen', () {
    testWidgets('inside 24 h the appointment cannot be cancelled', (
      tester,
    ) async {
      await pumpApp(
        tester,
        MyAppointmentsScreen(onBookNew: () {}),
        overrides: _with(_repo()),
      );
      await pumpFor(tester, _second);
      expect(find.text('القادمة · 1'), findsOneWidget);
      expect(find.textContaining('بقي أقل من 24 ساعة'), findsOneWidget);
      expect(find.text('إلغاء الموعد'), findsNothing);
    });

    testWidgets('cancels a later appointment after confirming', (tester) async {
      final repo = _repo();
      await repo.confirm(
        await repo.hold(await _doctor(repo), _monday9),
        PaymentMethod.edahabia,
      );
      await pumpApp(
        tester,
        MyAppointmentsScreen(onBookNew: () {}),
        overrides: _with(repo),
      );
      await pumpFor(tester, _second);
      expect(find.text('القادمة · 2'), findsOneWidget);

      await tester.tap(find.text('إلغاء الموعد'));
      await pumpFor(tester, _second);
      expect(find.text('إلغاء هذا الموعد؟'), findsOneWidget);
      await tester.tap(find.text('إلغاء الموعد').last);
      await pumpFor(tester, _second);
      expect(find.text('تم إلغاء الموعد'), findsOneWidget);
      expect(find.text('القادمة · 1'), findsOneWidget);
    });

    testWidgets('past tab lists done, missed and cancelled', (tester) async {
      await pumpApp(
        tester,
        MyAppointmentsScreen(onBookNew: () {}),
        overrides: _with(_repo()),
      );
      await pumpFor(tester, _second);
      await tester.tap(find.text('السابقة'));
      await pumpFor(tester, _second);
      expect(find.text('تمّ'), findsNWidgets(2));
      expect(find.text('فائت'), findsOneWidget);
      expect(find.text('ملغى'), findsOneWidget);
      expect(find.text('ملاحظات الطبيب خاصة ولا تظهر هنا.'), findsOneWidget);
    });
  });

  testWidgets('flow: doctor → time → pay → confirmed → my appointments', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => openBooking(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
      overrides: _with(_repo()),
    );
    await tester.tap(find.text('go'));
    await pumpFor(tester, _second);
    await tester.tap(find.text('اختيار اليوم والوقت'));
    await pumpFor(tester, _second);
    await tester.tap(find.text('09:00'));
    await pumpFor(tester, _second);
    await tester.tap(find.text('متابعة'));
    await pumpFor(tester, _second);
    await tester.tap(find.text('ادفع 2000 دج'));
    await pumpFor(tester, _second);
    expect(find.text('تم تأكيد موعدك'), findsOneWidget);

    await tester.tap(find.text('مواعيدي'));
    await pumpFor(tester, _second);
    expect(find.byType(MyAppointmentsScreen), findsOneWidget);
    expect(find.text('القادمة · 2'), findsOneWidget);
  });
}
