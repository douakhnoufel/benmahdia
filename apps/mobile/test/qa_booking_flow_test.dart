// QA booking run 2026-10-25 (ux-clients). Widget tests of what the patient
// sees in the booking flow: Arabic RTL + French, narrow phones, large text,
// tap targets, loading / empty / error states, the ID gate wording, the hold
// countdown and double taps. Sample data only, no real patients.
//
// A test that shows a real bug is kept with `skip: 'QA UX-NN: ...'` (see
// qa/booking/2026-10-25/ux-clients.md); remove the skip once it is fixed.

import 'dart:async';

import 'package:benmahdia_mobile/core/locale_provider.dart';
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
import 'package:benmahdia_mobile/features/profile/fake_identity_repository.dart';
import 'package:benmahdia_mobile/features/profile/identity_models.dart';
import 'package:benmahdia_mobile/features/profile/identity_repository.dart';
import 'package:benmahdia_mobile/features/profile/profile_flow.dart';
import 'package:benmahdia_mobile/features/profile/profile_prompt_screen.dart';
import 'package:benmahdia_mobile/l10n/app_localizations.dart';
import 'package:benmahdia_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// Saturday 17 October 2026, 17:10 clinic time (same "now" as booking_test).
final _now = DateTime(2026, 10, 17, 17, 10);
// Monday 19 October 09:00: first free slot after the 24 h notice.
final _monday9 = DateTime(2026, 10, 19, 9);
const _second = Duration(seconds: 1);

final _ar = lookupAppLocalizations(const Locale('ar'));
final _fr = lookupAppLocalizations(const Locale('fr'));

class _French extends LocaleNotifier {
  @override
  Locale build() => const Locale('fr');
}

/// Pumps [home] in the real app shell at [size] (logical px), in Arabic or
/// French, with an optional system text scale.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required BookingRepository repo,
  bool french = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookingRepositoryProvider.overrideWithValue(repo),
        if (french) localeProvider.overrideWith(_French.new),
        ...extra,
      ],
      child: BenMahdiaApp(home: home),
    ),
  );
  await pumpFor(tester, _second);
}

/// Every piece of text on screen (icons excluded).
List<String> _texts(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((w) => w.text.toPlainText().trim())
    .where((s) => s.isNotEmpty && !s.runes.every(_isIconGlyph))
    .toList();

/// Icon fonts use the private-use areas of Unicode.
bool _isIconGlyph(int r) =>
    (r >= 0xE000 && r <= 0xF8FF) || r >= 0xF0000 || r == 0x20;

/// Run the known-bug tests too: --dart-define=QA_RUN_BUGS=true.
const _runBugs = bool.fromEnvironment('QA_RUN_BUGS');

/// A test that shows a real bug: skipped with its QA id until it is fixed.
void _bug(String id, String why, String name, WidgetTesterCallback body) =>
    group(
      id,
      () => testWidgets(name, body),
      skip: _runBugs ? false : 'QA $id: $why',
    );

final _rawCode = RegExp(r'\b[a-z]+_[a-z_]+\b');
// Brand names that stay in Latin letters inside Arabic text.
const _latinAllowedInArabic = {'CIB', 'Chargily', 'Pay'};

/// No raw API code and, in Arabic, no French/English words left untranslated.
void _expectTranslated(WidgetTester tester, {required bool french}) {
  final texts = _texts(tester);
  for (final t in texts) {
    expect(_rawCode.hasMatch(t), isFalse, reason: 'raw code on screen: "$t"');
    if (!french) {
      final latin = RegExp(r'[A-Za-z]{2,}')
          .allMatches(t)
          .map((m) => m.group(0)!)
          .where((w) => !_latinAllowedInArabic.contains(w));
      expect(latin, isEmpty, reason: 'untranslated words in Arabic: "$t"');
    }
  }
}

Hold _hold(BookingRepository repo) => Hold(
  id: 'h-qa',
  doctor: FakeBookingRepository.sampleDoctor,
  start: _monday9,
  end: _monday9.add(const Duration(minutes: 15)),
  expiresAt: repo.now().add(const Duration(minutes: 15)),
);

Appointment _appt(PaymentMethod method) => Appointment(
  id: 'a-qa',
  doctor: FakeBookingRepository.sampleDoctor,
  start: _monday9,
  end: _monday9.add(const Duration(minutes: 15)),
  status: AppointmentStatus.confirmed,
  priceDzd: 2000,
  method: method,
);

FakeBookingRepository _repo() => FakeBookingRepository(clock: () => _now);

/// One booking screen, how to build it, and the title that proves it shows.
class _Screen {
  const _Screen(this.name, this.build, this.title);
  final String name;
  final Widget Function(BookingRepository repo) build;
  final String Function(AppLocalizations l10n) title;
}

final _screens = <_Screen>[
  _Screen(
    'doctor',
    (_) => BookDoctorScreen(onNext: (_) {}),
    (l) => l.bookDoctorTitle,
  ),
  _Screen(
    'slot',
    (_) => BookSlotScreen(
      doctor: FakeBookingRepository.sampleDoctor,
      onNext: (_) {},
    ),
    (l) => l.bookSlotTitle,
  ),
  _Screen(
    'confirm',
    (repo) =>
        BookConfirmScreen(hold: _hold(repo), onDone: (_) {}, onExpired: () {}),
    (l) => l.bookConfirmTitle,
  ),
  _Screen(
    'done (card)',
    (_) => BookDoneScreen(
      appointment: _appt(PaymentMethod.edahabia),
      onAppointments: () {},
      onHome: () {},
    ),
    (l) => l.bookDoneTitle,
  ),
  _Screen(
    'done (clinic)',
    (_) => BookDoneScreen(
      appointment: _appt(PaymentMethod.clinic),
      onAppointments: () {},
      onHome: () {},
    ),
    (l) => l.bookDoneTitleClinic,
  ),
  _Screen(
    'my appointments',
    (_) => MyAppointmentsScreen(onBookNew: () {}),
    (l) => l.bookMyAppointments,
  ),
];

/// A repository whose answers wait until [gate] completes, or fail.
class _GatedRepo extends FakeBookingRepository {
  _GatedRepo({this.fail = false}) : super(clock: () => _now);

  bool fail;
  final gate = Completer<void>();
  var doctorCalls = 0;

  Future<T> _wait<T>(Future<T> Function() answer) async {
    await gate.future;
    if (fail) throw const BookingUnavailable();
    return answer();
  }

  @override
  Future<List<Doctor>> doctors() {
    doctorCalls++;
    return _wait(super.doctors);
  }

  @override
  Future<List<DaySlots>> calendar(Doctor doctor) =>
      _wait(() => super.calendar(doctor));

  @override
  Future<List<Appointment>> appointments() => _wait(super.appointments);
}

class _NoDoctors extends FakeBookingRepository {
  _NoDoctors() : super(clock: () => _now, history: const []);

  @override
  Future<List<Doctor>> doctors() async => const [];
}

/// Every day of the window is closed or full.
class _NoSlots extends FakeBookingRepository {
  _NoSlots() : super(clock: () => _now, history: const []);

  @override
  Future<List<DaySlots>> calendar(Doctor doctor) async => [
    for (var i = 0; i < 60; i++)
      DaySlots(
        day: DateTime(2026, 10, 17 + i),
        slots: [Slot(start: DateTime(2026, 10, 17 + i, 9), free: false)],
      ),
  ];
}

/// Counts confirm / checkout calls; [confirm] answers only when released.
class _CountingRepo extends FakeBookingRepository {
  _CountingRepo({this.checkoutCards = false}) : super(clock: () => _now);

  final bool checkoutCards;
  var confirms = 0;
  var checkouts = 0;
  final answer = Completer<void>();

  @override
  bool get cardsUseCheckout => checkoutCards;

  @override
  Future<Appointment> confirm(Hold hold, PaymentMethod method) async {
    confirms++;
    await answer.future;
    return super.confirm(hold, method);
  }

  @override
  Future<Uri> checkout(Hold hold, PaymentMethod method) async {
    checkouts++;
    await answer.future;
    return super.checkout(hold, method);
  }

  @override
  Future<Appointment?> paid(Hold hold) async => null;
}

/// The server says the hold already ran out when the patient confirms.
class _ExpiredOnConfirm extends FakeBookingRepository {
  _ExpiredOnConfirm() : super(clock: () => _now);

  @override
  Future<Appointment> confirm(Hold hold, PaymentMethod method) async =>
      throw const SlotUnavailable();
}

/// A clock the test moves by hand (e.g. the phone was asleep).
class _MovingClockRepo extends FakeBookingRepository {
  _MovingClockRepo(this.clock) : super(clock: clock);
  final DateTime Function() clock;
}

Widget _launcher(void Function(BuildContext) open) => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => open(context),
        child: const Text('go'),
      ),
    ),
  ),
);

void main() {
  group('every booking screen in Arabic (RTL) and French', () {
    for (final s in _screens) {
      for (final french in [false, true]) {
        final lang = french ? 'fr' : 'ar';
        void check(String name, WidgetTesterCallback body) =>
            testWidgets(name, body);
        check('${s.name} · $lang · 390 wide', (tester) async {
          final repo = _repo();
          await _pump(tester, s.build(repo), repo: repo, french: french);
          final l10n = french ? _fr : _ar;
          expect(find.text(s.title(l10n)), findsWidgets);
          expect(
            Directionality.of(tester.element(find.byType(Scaffold).first)),
            french ? TextDirection.ltr : TextDirection.rtl,
          );
          _expectTranslated(tester, french: french);
        });

        check('${s.name} · $lang · 320 wide: nothing overflows', (
          tester,
        ) async {
          final repo = _repo();
          await _pump(
            tester,
            s.build(repo),
            repo: repo,
            french: french,
            size: const Size(320, 1400),
          );
          expect(tester.takeException(), isNull);
          expect(find.text(s.title(french ? _fr : _ar)), findsWidgets);
        });

        check('${s.name} · $lang · large text (1.3×, 360 wide)', (
          tester,
        ) async {
          final repo = _repo();
          await _pump(
            tester,
            s.build(repo),
            repo: repo,
            french: french,
            size: const Size(360, 1600),
            textScale: 1.3,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('tap targets and screen-reader labels (PRD 8.6)', () {
    for (final s in _screens) {
      testWidgets('${s.name}: labelled tap targets', (tester) async {
        final handle = tester.ensureSemantics();
        final repo = _repo();
        await _pump(tester, s.build(repo), repo: repo);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('${s.name}: tap targets at least 48×48', (tester) async {
        final handle = tester.ensureSemantics();
        final repo = _repo();
        await _pump(tester, s.build(repo), repo: repo);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      });
    }
  });

  group('loading, error and empty states', () {
    for (final french in [false, true]) {
      final lang = french ? 'fr' : 'ar';
      final l10n = french ? _fr : _ar;

      testWidgets('doctor list loading then failing, then retry · $lang', (
        tester,
      ) async {
        final repo = _GatedRepo(fail: true);
        await _pump(
          tester,
          BookDoctorScreen(onNext: (_) {}),
          repo: repo,
          french: french,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        repo.gate.complete();
        await pumpFor(tester, _second);
        expect(find.text(l10n.bookLoadError), findsOneWidget);
        _expectTranslated(tester, french: french);
        // The network is back: retry loads the doctor.
        repo.fail = false;
        await tester.tap(find.text(l10n.bookRetry));
        await pumpFor(tester, _second);
        expect(repo.doctorCalls, 2);
        expect(find.text(l10n.bookDoctorTitle), findsOneWidget);
      });

      testWidgets('calendar failing shows a retry · $lang', (tester) async {
        final repo = _GatedRepo(fail: true)..gate.complete();
        await _pump(
          tester,
          BookSlotScreen(
            doctor: FakeBookingRepository.sampleDoctor,
            onNext: (_) {},
          ),
          repo: repo,
          french: french,
        );
        expect(find.text(l10n.bookLoadError), findsOneWidget);
        expect(find.text(l10n.bookRetry), findsOneWidget);
      });

      testWidgets('my appointments loading then failing · $lang', (
        tester,
      ) async {
        final repo = _GatedRepo(fail: true);
        await _pump(
          tester,
          MyAppointmentsScreen(onBookNew: () {}),
          repo: repo,
          french: french,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        repo.gate.complete();
        await pumpFor(tester, _second);
        expect(find.text(l10n.bookLoadError), findsOneWidget);
      });

      testWidgets('no appointments: upcoming and past say so · $lang', (
        tester,
      ) async {
        final repo = FakeBookingRepository(
          clock: () => _now,
          history: const [],
        );
        await _pump(
          tester,
          MyAppointmentsScreen(onBookNew: () {}),
          repo: repo,
          french: french,
        );
        expect(find.text(l10n.apptNoUpcoming), findsOneWidget);
        await tester.tap(find.text(l10n.apptPast));
        await pumpFor(tester, _second);
        expect(find.text(l10n.apptNoPast), findsOneWidget);
      });

      testWidgets('no free slot in the window: the doctor card says so · '
          '$lang', (tester) async {
        await _pump(
          tester,
          BookDoctorScreen(onNext: (_) {}),
          repo: _NoSlots(),
          french: french,
        );
        expect(find.text(l10n.bookNoFree(60)), findsOneWidget);
      });
    }

    _bug(
      'UX-07',
      'no empty state when the clinic lists no doctor',
      'no doctor to book: the screen explains it instead of a blank list',
      (tester) async {
        await _pump(
          tester,
          BookDoctorScreen(onNext: (_) {}),
          repo: _NoDoctors(),
        );
        final known = {
          _ar.bookTitle,
          _ar.bookDoctorTitle,
          _ar.bookDoctorBody,
          _ar.bookNotice(24),
          _ar.bookChooseTime,
          _ar.verifyStep(1, 3),
        };
        final extra = _texts(tester).where((t) => !known.contains(t));
        expect(extra, isNotEmpty, reason: 'only the title and a dead button');
      },
    );
  });

  group('ID gate wording (PRD 4.2)', () {
    final forbidden = RegExp(r'verified|vérifié|موثق', caseSensitive: false);

    Future<void> openGate(
      WidgetTester tester,
      IdStatus status, {
      bool french = false,
    }) async {
      await _pump(
        tester,
        _launcher(openAppointments),
        repo: _repo(),
        french: french,
        extra: [
          identityRepositoryProvider.overrideWithValue(
            FakeIdentityRepository(initial: IdentityState(status: status)),
          ),
        ],
      );
      await tester.tap(find.text('go'));
      await pumpFor(tester, _second);
    }

    for (final french in [false, true]) {
      final lang = french ? 'fr' : 'ar';
      final l10n = french ? _fr : _ar;

      testWidgets('declared: says it is being reviewed, never "verified" · '
          '$lang', (tester) async {
        await openGate(tester, IdStatus.declared, french: french);
        expect(find.text(l10n.profileCardDeclaredBody), findsOneWidget);
        for (final t in _texts(tester)) {
          expect(forbidden.hasMatch(t), isFalse, reason: t);
        }
        // Booking stays closed: "book" only repeats the message.
        await tester.tap(find.byIcon(Icons.add_rounded));
        await pumpFor(tester, _second);
        expect(find.byType(BookDoctorScreen), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
      });

      testWidgets('declared: the status label is "ID declared" · $lang', (
        tester,
      ) async {
        await openGate(tester, IdStatus.declared, french: french);
        expect(
          find.textContaining(french ? 'Identité déclarée' : 'هوية مصرّح بها'),
          findsWidgets,
        );
      });
    }

    testWidgets('no wording anywhere in the app says "verified"', (
      tester,
    ) async {
      // Static check over both languages' strings used for ID status.
      for (final l10n in [_ar, _fr]) {
        for (final s in [
          l10n.profileCardDeclaredTitle,
          l10n.profileCardDeclaredBody,
          l10n.profileCardRejectedTitle,
          l10n.profileCardRejectedBody,
          l10n.profileCardNoneBody,
          l10n.profileTitle,
        ]) {
          expect(forbidden.hasMatch(s), isFalse, reason: s);
        }
      }
    });

    testWidgets('Complete your profile has no Skip (PRD 4.1, 4.2; rule R-08)', (
      tester,
    ) async {
      await _pump(
        tester,
        _launcher(openProfile),
        repo: _repo(),
        extra: [
          identityRepositoryProvider.overrideWithValue(
            FakeIdentityRepository(),
          ),
        ],
      );
      await tester.tap(find.text('go'));
      await pumpFor(tester, _second);
      expect(find.byType(ProfilePromptScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-skip')), findsNothing);
      expect(find.text('تخطَّ الآن'), findsNothing);
    });
  });

  group('hold on the confirm screen', () {
    for (final french in [false, true]) {
      final lang = french ? 'fr' : 'ar';
      final l10n = french ? _fr : _ar;

      testWidgets('server says the hold ran out on confirm → time-up view · '
          '$lang', (tester) async {
        var expired = 0;
        final repo = _ExpiredOnConfirm();
        await _pump(
          tester,
          BookConfirmScreen(
            hold: _hold(repo),
            onDone: (_) {},
            onExpired: () => expired++,
          ),
          repo: repo,
          french: french,
        );
        await tester.tap(find.text(l10n.bookClinicPay));
        await pumpFor(tester, _second);
        await tester.tap(find.text(l10n.bookConfirmClinic));
        await pumpFor(tester, _second);
        expect(find.text(l10n.bookExpiredTitle), findsOneWidget);
        expect(find.text(l10n.bookExpiredBody), findsOneWidget);
        await tester.tap(find.text(l10n.bookPickAnother));
        expect(expired, 1);
      });

      testWidgets('countdown runs out on screen → time-up view · $lang', (
        tester,
      ) async {
        final repo = _repo();
        await _pump(
          tester,
          BookConfirmScreen(
            hold: _hold(repo),
            onDone: (_) {},
            onExpired: () {},
          ),
          repo: repo,
          french: french,
        );
        await tester.pump(const Duration(minutes: 15));
        await pumpFor(tester, _second);
        expect(find.text(l10n.bookExpiredTitle), findsOneWidget);
        expect(find.text(l10n.bookPay(2000)), findsNothing);
      });
    }

    _bug(
      'UX-08',
      'hold countdown counts timer ticks, drifts from the real expiry',
      'the countdown follows the clock, not the number of ticks '
          '(phone asleep for 10 min)',
      (tester) async {
        var now = _now;
        final repo = _MovingClockRepo(() => now);
        await _pump(
          tester,
          BookConfirmScreen(
            hold: _hold(repo),
            onDone: (_) {},
            onExpired: () {},
          ),
          repo: repo,
        );
        // The phone slept: 10 minutes passed but almost no timer ticks ran.
        now = now.add(const Duration(minutes: 10));
        await tester.pump(_second);
        expect(find.textContaining('04:5'), findsOneWidget);
      },
    );

    testWidgets('double tap on "confirm" (clinic) sends one request', (
      tester,
    ) async {
      final booked = <Appointment>[];
      final repo = _CountingRepo();
      await _pump(
        tester,
        BookConfirmScreen(
          hold: _hold(repo),
          onDone: booked.add,
          onExpired: () {},
        ),
        repo: repo,
      );
      await tester.tap(find.text(_ar.bookClinicPay));
      await pumpFor(tester, _second);
      final button = find.widgetWithText(FilledButton, _ar.bookConfirmClinic);
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 80));
      expect(repo.confirms, 1);
      repo.answer.complete();
      await pumpFor(tester, _second);
      expect(booked, hasLength(1));
    });

    testWidgets('double tap on "pay" (card) opens one checkout', (
      tester,
    ) async {
      final repo = _CountingRepo(checkoutCards: true);
      await _pump(
        tester,
        BookConfirmScreen(hold: _hold(repo), onDone: (_) {}, onExpired: () {}),
        repo: repo,
        extra: [openUrlProvider.overrideWithValue((_) async => true)],
      );
      await tester.tap(find.text(_ar.bookPay(2000)));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 80));
      expect(repo.checkouts, 1);
      repo.answer.complete();
      await pumpFor(tester, _second);
    });

    testWidgets('done screen: back goes home, never to the paid step', (
      tester,
    ) async {
      await _pump(tester, _launcher(openBooking), repo: _repo());
      await tester.tap(find.text('go'));
      await pumpFor(tester, _second);
      await tester.tap(find.text(_ar.bookChooseTime));
      await pumpFor(tester, _second);
      await tester.tap(find.text('09:00'));
      await pumpFor(tester, _second);
      await tester.tap(find.text(_ar.bookContinue));
      await pumpFor(tester, _second);
      await tester.tap(find.text(_ar.bookClinicPay));
      await pumpFor(tester, _second);
      await tester.tap(find.text(_ar.bookConfirmClinic));
      await pumpFor(tester, _second);
      expect(find.byType(BookDoneScreen), findsOneWidget);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      await nav.maybePop();
      await pumpFor(tester, _second);
      expect(find.byType(BookDoneScreen), findsNothing);
      expect(find.byType(BookConfirmScreen), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });
  });
}
