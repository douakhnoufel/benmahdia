// QA booking run 2026-10-25 (ux-clients). The real ApiBookingRepository
// behind a fake HTTP client, so every error `code` the booking API can return
// (backend/app/routers/appointments.py, payments.py, deps.py, chargily.py)
// goes through the same path as in the app and lands on a screen. Also:
// clinic time (Africa/Algiers) on screen, the booking code, and what an open
// hold offers in "my appointments". Sample data only.
//
// The known-bug tests found here (QA UX-04/05/06/09,
// qa/booking/2026-10-25/ux-clients.md) are fixed and now run normally.

import 'dart:convert';

import 'package:benmahdia_mobile/core/locale_provider.dart';
import 'package:benmahdia_mobile/features/booking/api_booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/book_confirm_screen.dart';
import 'package:benmahdia_mobile/features/booking/book_slot_screen.dart';
import 'package:benmahdia_mobile/features/booking/booking_models.dart';
import 'package:benmahdia_mobile/features/booking/booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/my_appointments_screen.dart';
import 'package:benmahdia_mobile/features/booking/payment_launcher.dart';
import 'package:benmahdia_mobile/l10n/app_localizations.dart';
import 'package:benmahdia_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

const _second = Duration(seconds: 1);
final _ar = lookupAppLocalizations(const Locale('ar'));
final _fr = lookupAppLocalizations(const Locale('fr'));

class _French extends LocaleNotifier {
  @override
  Locale build() => const Locale('fr');
}

const _doctorJson = {
  'id': 'd-1',
  'name_ar': 'د. بن مهدية حسين',
  'name_fr': 'Dr Benmahdia Hocine',
  'slot_minutes': 15,
  'price_dzd': 2000,
  'notice_hours': 24,
  'hold_minutes': 15,
  'horizon_days': 60,
};

const _doctor = Doctor(
  id: 'd-1',
  nameAr: 'د. بن مهدية حسين',
  nameFr: 'Dr Benmahdia Hocine',
  initialsAr: 'ب ح',
  initialsFr: 'BH',
  slotMinutes: 15,
  priceDzd: 2000,
);

Map<String, Object?> _appointment({
  String id = 'a-1',
  String start = '2026-10-25T08:00:00Z',
  String end = '2026-10-25T08:15:00Z',
  String status = 'confirmed',
  String? method = 'clinic',
  String? holdExpiresAt,
  String? checkinCode,
}) => {
  'id': id,
  'doctor': _doctorJson,
  'start': start,
  'end': end,
  'status': status,
  'price_dzd': 2000,
  'method': method,
  'hold_expires_at': holdExpiresAt,
  'checkin_code': checkinCode,
};

http.Response _json(int status, Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _error(int status, String code) => _json(status, {
  'detail': {'code': code},
});

/// Saturday 17 October 2026, 16:10 UTC = 17:10 in Algiers.
final _utcNow = DateTime.utc(2026, 10, 17, 16, 10);

ApiBookingRepository _api(http.Response Function(http.Request) answer) =>
    ApiBookingRepository(
      baseUrl: Uri.parse('https://api.example.invalid/'),
      token: () => 'access-qa',
      refresh: () async => false,
      client: MockClient((r) async => answer(r)),
      clock: () => _utcNow,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  BookingRepository repo, {
  bool french = false,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
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

List<String> _texts(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((w) => w.text.toPlainText().trim())
    .where((s) => s.isNotEmpty && !s.runes.every(_isIconGlyph))
    .toList();

bool _isIconGlyph(int r) =>
    (r >= 0xE000 && r <= 0xF8FF) || r >= 0xF0000 || r == 0x20;

const _latinAllowedInArabic = {'CIB', 'Chargily', 'Pay'};

/// No raw API code on screen; in Arabic no untranslated words.
void _expectHuman(WidgetTester tester, String code, {required bool french}) {
  for (final t in _texts(tester)) {
    expect(t.contains(code), isFalse, reason: 'raw code shown: "$t"');
    expect(RegExp(r'\b[a-z]+_[a-z_]+\b').hasMatch(t), isFalse, reason: t);
    if (!french) {
      final latin = RegExp(r'[A-Za-z]{2,}')
          .allMatches(t)
          .map((m) => m.group(0)!)
          .where((w) => !_latinAllowedInArabic.contains(w));
      expect(latin, isEmpty, reason: 'untranslated in Arabic: "$t"');
    }
  }
}

// --- the four actions that can be refused ----------------------------------

/// Slot screen → tap 09:00 → "continue" → POST /holds answers [reply].
Future<void> _holdRefused(
  WidgetTester tester,
  http.Response reply, {
  bool french = false,
}) async {
  final repo = _api((r) {
    final p = r.url.path;
    if (p == '/v1/doctors/d-1/calendar') {
      return _json(200, {
        'days': [
          {
            'day': '2026-10-19',
            'closure': null,
            'slots': [
              {'start': '2026-10-19T08:00:00Z', 'free': true},
            ],
          },
        ],
      });
    }
    if (p == '/v1/appointments/follow-up') return _json(200, null);
    if (p == '/v1/appointments/holds') return reply;
    return _error(404, 'not_found');
  });
  await _pump(
    tester,
    BookSlotScreen(doctor: _doctor, onNext: (_) {}),
    repo,
    french: french,
  );
  await tester.tap(find.text('09:00'));
  await pumpFor(tester, _second);
  await tester.tap(find.text((french ? _fr : _ar).bookContinue));
  await pumpFor(tester, _second);
}

Hold _hold(BookingRepository repo) => Hold(
  id: 'h-1',
  doctor: _doctor,
  start: DateTime(2026, 10, 19, 9),
  end: DateTime(2026, 10, 19, 9, 15),
  expiresAt: repo.now().add(const Duration(minutes: 15)),
);

/// Confirm screen → "pay at the clinic" → confirm → POST /confirm answers.
Future<void> _confirmRefused(
  WidgetTester tester,
  http.Response reply, {
  bool french = false,
}) async {
  final l10n = french ? _fr : _ar;
  final repo = _api(
    (r) =>
        r.url.path == '/v1/appointments/h-1/confirm' ? reply : _json(204, null),
  );
  await _pump(
    tester,
    BookConfirmScreen(hold: _hold(repo), onDone: (_) {}, onExpired: () {}),
    repo,
    french: french,
  );
  await tester.tap(find.text(l10n.bookClinicPay));
  await pumpFor(tester, _second);
  await tester.tap(find.text(l10n.bookConfirmClinic));
  await pumpFor(tester, _second);
}

/// Confirm screen → card → pay → POST /checkout answers [reply].
Future<void> _checkoutRefused(
  WidgetTester tester,
  http.Response reply, {
  bool french = false,
}) async {
  final repo = _api(
    (r) => r.url.path == '/v1/appointments/h-1/checkout'
        ? reply
        : _json(204, null),
  );
  await _pump(
    tester,
    BookConfirmScreen(hold: _hold(repo), onDone: (_) {}, onExpired: () {}),
    repo,
    french: french,
    extra: [openUrlProvider.overrideWithValue((_) async => true)],
  );
  await tester.tap(find.text((french ? _fr : _ar).bookPay(2000)));
  await pumpFor(tester, _second);
}

/// My appointments → cancel → confirm in the dialog → POST /cancel answers.
Future<void> _cancelRefused(
  WidgetTester tester,
  http.Response reply, {
  bool french = false,
}) async {
  final l10n = french ? _fr : _ar;
  final repo = _api((r) {
    final p = r.url.path;
    if (p == '/v1/appointments' && r.method == 'GET') {
      return _json(200, [_appointment()]);
    }
    if (p == '/v1/appointments/follow-up') return _json(200, null);
    if (p == '/v1/appointments/a-1/cancel') return reply;
    return _error(404, 'not_found');
  });
  await _pump(
    tester,
    MyAppointmentsScreen(onBookNew: () {}),
    repo,
    french: french,
  );
  await tester.tap(find.text(l10n.apptCancel));
  await pumpFor(tester, _second);
  await tester.tap(find.text(l10n.apptCancel).last);
  await pumpFor(tester, _second);
}

typedef _Action =
    Future<void> Function(WidgetTester, http.Response, {bool french});

/// What the patient should see for one refusal.
enum _Shows {
  /// "Someone else just took this time" snackbar.
  slotGone,

  /// The "time is up, pick another time" view.
  expired,

  /// "Less than 24 h, call the clinic".
  tooLate,

  /// Some message; which one the PRD does not say.
  anyMessage,
}

class _Case {
  const _Case(this.action, this.name, this.status, this.code, this.shows);
  final _Action action;
  final String name;
  final int status;
  final String code;
  final _Shows shows;
}

const _cases = <_Case>[
  // POST /v1/appointments/holds
  _Case(_holdRefused, 'hold', 409, 'slot_unavailable', _Shows.slotGone),
  _Case(_holdRefused, 'hold', 404, 'doctor_not_found', _Shows.anyMessage),
  _Case(_holdRefused, 'hold', 403, 'not_verified', _Shows.anyMessage),
  _Case(_holdRefused, 'hold', 403, 'forbidden', _Shows.anyMessage),
  _Case(_holdRefused, 'hold', 401, 'token_invalid', _Shows.anyMessage),
  _Case(_holdRefused, 'hold', 401, 'not_authenticated', _Shows.anyMessage),
  // POST /v1/appointments/{id}/confirm
  _Case(_confirmRefused, 'confirm', 409, 'hold_expired', _Shows.expired),
  _Case(_confirmRefused, 'confirm', 409, 'not_a_hold', _Shows.expired),
  _Case(
    _confirmRefused,
    'confirm',
    404,
    'appointment_not_found',
    _Shows.expired,
  ),
  _Case(
    _confirmRefused,
    'confirm',
    400,
    'payment_method_unavailable',
    _Shows.anyMessage,
  ),
  _Case(_confirmRefused, 'confirm', 403, 'not_verified', _Shows.anyMessage),
  // POST /v1/appointments/{id}/checkout
  _Case(_checkoutRefused, 'checkout', 409, 'hold_expired', _Shows.expired),
  _Case(_checkoutRefused, 'checkout', 409, 'not_a_hold', _Shows.expired),
  _Case(
    _checkoutRefused,
    'checkout',
    502,
    'payments_unavailable',
    _Shows.anyMessage,
  ),
  _Case(
    _checkoutRefused,
    'checkout',
    503,
    'payments_unavailable',
    _Shows.anyMessage,
  ),
  _Case(
    _checkoutRefused,
    'checkout',
    400,
    'payment_method_unavailable',
    _Shows.anyMessage,
  ),
  // POST /v1/appointments/{id}/cancel
  _Case(_cancelRefused, 'cancel', 409, 'too_late_to_cancel', _Shows.tooLate),
  _Case(_cancelRefused, 'cancel', 409, 'not_cancellable', _Shows.anyMessage),
];

void main() {
  group('every booking error code becomes a human message (ar + fr)', () {
    for (final c in _cases) {
      for (final french in [false, true]) {
        final lang = french ? 'fr' : 'ar';
        testWidgets('${c.name} ${c.status} ${c.code} · $lang', (tester) async {
          final l10n = french ? _fr : _ar;
          await c.action(tester, _error(c.status, c.code), french: french);
          switch (c.shows) {
            case _Shows.slotGone:
              expect(find.text(l10n.bookSlotGone), findsOneWidget);
            case _Shows.expired:
              expect(find.text(l10n.bookExpiredTitle), findsOneWidget);
            case _Shows.tooLate:
              expect(find.text(l10n.apptLocked(24)), findsWidgets);
            case _Shows.anyMessage:
              expect(find.byType(SnackBar), findsOneWidget);
          }
          _expectHuman(tester, c.code, french: french);
        });
      }
    }

    testWidgets('a 422 validation body (list detail) is not shown raw', (
      tester,
    ) async {
      await _holdRefused(
        tester,
        _json(422, {
          'detail': [
            {
              'type': 'missing',
              'loc': ['body', 'start'],
              'msg': 'Field required',
            },
          ],
        }),
      );
      expect(find.byType(SnackBar), findsOneWidget);
      _expectHuman(tester, 'Field required', french: false);
    });
  });

  group('refusals that are not a connection problem', () {
    // These codes are answers from the server, but the app says "could not
    // load, check your connection" (bookLoadError) for all of them.
    for (final (action, name, status, code) in <(_Action, String, int, String)>[
      (_holdRefused, 'hold', 403, 'not_verified'),
      (_confirmRefused, 'confirm', 400, 'payment_method_unavailable'),
      (_checkoutRefused, 'checkout', 502, 'payments_unavailable'),
      (_cancelRefused, 'cancel', 409, 'not_cancellable'),
    ]) {
      testWidgets('$name $code does not blame the connection', (tester) async {
        await action(tester, _error(status, code), french: false);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(_ar.bookLoadError), findsNothing);
      });
    }

    testWidgets(
      'cancel 404 appointment_not_found shows a message and refreshes',
      (tester) async {
        await _cancelRefused(tester, _error(404, 'appointment_not_found'));
        expect(tester.takeException(), isNull);
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );
  });

  group('clinic time (Africa/Algiers) on screen', () {
    testWidgets('08:00Z is shown as 09:00 – 09:15 on the right day', (
      tester,
    ) async {
      final repo = _api((r) {
        if (r.url.path == '/v1/appointments') {
          return _json(200, [_appointment()]);
        }
        return _json(200, null);
      });
      await _pump(tester, MyAppointmentsScreen(onBookNew: () {}), repo);
      expect(find.text('09:00 – 09:15'), findsOneWidget);
      expect(find.text('الأحد 25 أكتوبر'), findsOneWidget);
    });

    testWidgets('23:30Z is 00:30 the next clinic day', (tester) async {
      final repo = _api((r) {
        if (r.url.path == '/v1/appointments') {
          return _json(200, [
            _appointment(
              start: '2026-10-25T23:30:00Z',
              end: '2026-10-25T23:45:00Z',
            ),
          ]);
        }
        return _json(200, null);
      });
      await _pump(
        tester,
        MyAppointmentsScreen(onBookNew: () {}),
        repo,
        french: true,
      );
      expect(find.text('00:30 – 00:45'), findsOneWidget);
      expect(find.text('lundi 26 octobre'), findsOneWidget);
    });
  });

  group('my appointments after booking', () {
    testWidgets('a confirmed appointment shows its 6-character booking code', (
      tester,
    ) async {
      final repo = _api((r) {
        if (r.url.path == '/v1/appointments') {
          return _json(200, [_appointment(checkinCode: 'K7M4PX')]);
        }
        return _json(200, null);
      });
      await _pump(tester, MyAppointmentsScreen(onBookNew: () {}), repo);
      expect(find.textContaining('K7M4PX'), findsOneWidget);
    });

    testWidgets(
      'an open hold (awaiting payment) offers no "cancel appointment"',
      (tester) async {
        final repo = _api((r) {
          if (r.url.path == '/v1/appointments') {
            return _json(200, [
              _appointment(
                status: 'awaiting_payment',
                method: 'edahabia',
                holdExpiresAt: '2026-10-17T16:20:00Z',
              ),
            ]);
          }
          return _json(200, null);
        });
        await _pump(tester, MyAppointmentsScreen(onBookNew: () {}), repo);
        expect(find.text(_ar.apptAwaitingPayment), findsOneWidget);
        expect(find.text(_ar.apptCancel), findsNothing);
      },
    );
  });
}
