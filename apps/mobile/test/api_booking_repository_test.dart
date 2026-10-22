import 'dart:async';
import 'dart:convert';

import 'package:benmahdia_mobile/features/booking/api_booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/booking_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _doctor = {
  'id': 'd-1',
  'name_ar': 'د. بن مهدية حسين',
  'name_fr': 'Dr Benmahdia Hocine',
  'slot_minutes': 15,
  'price_dzd': 2000,
  'notice_hours': 24,
  'hold_minutes': 15,
  'horizon_days': 60,
};

Map<String, Object?> _appointment({
  String status = 'confirmed',
  String? method = 'clinic',
  String? holdExpiresAt,
}) => {
  'id': 'a-1',
  'doctor': _doctor,
  'start': '2026-10-19T08:00:00Z',
  'end': '2026-10-19T08:15:00Z',
  'status': status,
  'price_dzd': 2000,
  'method': method,
  'hold_expires_at': holdExpiresAt,
};

http.Response _json(int status, Object? body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

const _d = Doctor(
  id: 'd-1',
  nameAr: 'د. بن مهدية حسين',
  nameFr: 'Dr Benmahdia Hocine',
  initialsAr: 'م ح',
  initialsFr: 'BH',
  slotMinutes: 15,
  priceDzd: 2000,
);

void main() {
  late List<http.Request> sent;
  var token = 'access-1';
  var refreshed = 0;

  ApiBookingRepository repo(
    http.Response Function(http.Request) answer, {
    Future<bool> Function()? refresh,
  }) {
    sent = [];
    return ApiBookingRepository(
      baseUrl: Uri.parse('http://api.test/'),
      token: () => token,
      refresh:
          refresh ??
          () async {
            refreshed++;
            token = 'access-2';
            return true;
          },
      clock: () => DateTime.utc(2026, 10, 17, 18),
      client: MockClient((request) async {
        sent.add(request);
        return answer(request);
      }),
    );
  }

  setUp(() {
    token = 'access-1';
    refreshed = 0;
  });

  test('now is clinic time, one hour ahead of UTC', () {
    expect(repo((_) => _json(200, const [])).now(), DateTime(2026, 10, 17, 19));
  });

  test('lists doctors with initials and the booking settings', () async {
    final r = repo((_) => _json(200, [_doctor]));
    final [d] = await r.doctors();
    expect(sent.single.url.path, '/v1/doctors');
    expect(sent.single.headers['authorization'], 'Bearer access-1');
    expect((d.id, d.slotMinutes, d.priceDzd), ('d-1', 15, 2000));
    expect((d.initialsFr, d.initialsAr), ('BH', 'م ح'));
    expect(
      (r.notice, r.horizon, r.holdFor),
      (
        const Duration(hours: 24),
        const Duration(days: 60),
        const Duration(minutes: 15),
      ),
    );
  });

  test('offers cards through the Chargily checkout and the clinic', () {
    final r = repo((_) => _json(200, const []));
    expect(r.methods, PaymentMethod.values.toSet());
    expect(r.cardsUseCheckout, isTrue);
  });

  test('opens a checkout and returns its page', () async {
    final r = repo(
      (_) => _json(201, {
        'payment_id': 'p-1',
        'checkout_url': 'https://pay.chargily.net/test/checkouts/c-1/pay',
      }),
    );
    final hold = Hold(
      id: 'a-1',
      doctor: _d,
      start: DateTime(2026, 10, 19, 9),
      end: DateTime(2026, 10, 19, 9, 15),
      expiresAt: DateTime(2026, 10, 17, 19, 15),
    );
    final url = await r.checkout(hold, PaymentMethod.cib);
    expect(sent.single.url.path, '/v1/appointments/a-1/checkout');
    expect(jsonDecode(sent.single.body), {'method': 'cib'});
    expect(url.host, 'pay.chargily.net');
  });

  test('paid waits, then confirms, or reports a lost slot', () async {
    final hold = Hold(
      id: 'a-1',
      doctor: _d,
      start: DateTime(2026, 10, 19, 9),
      end: DateTime(2026, 10, 19, 9, 15),
      expiresAt: DateTime(2026, 10, 17, 19, 15),
    );
    final waiting = repo(
      (_) =>
          _json(200, [_appointment(status: 'awaiting_payment', method: null)]),
    );
    expect(await waiting.paid(hold), isNull);
    final done = repo((_) => _json(200, [_appointment(method: 'cib')]));
    expect((await done.paid(hold))!.method, PaymentMethod.cib);
    final gone = repo((_) => _json(200, const []));
    expect(gone.paid(hold), throwsA(isA<SlotUnavailable>()));
  });

  test('reads the calendar in clinic time', () async {
    final r = repo(
      (_) => _json(200, {
        'doctor_id': 'd-1',
        'days': [
          {'day': '2026-10-17', 'closure': 'too_soon', 'slots': []},
          {'day': '2026-10-23', 'closure': 'closed', 'slots': []},
          {
            'day': '2026-10-19',
            'closure': 'none',
            'slots': [
              {'start': '2026-10-19T08:00:00Z', 'free': true},
              {'start': '2026-10-19T08:15:00Z', 'free': false},
            ],
          },
        ],
      }),
    );
    final doctor = _d;
    final days = await r.calendar(doctor);
    expect(sent.single.url.path, '/v1/doctors/d-1/calendar');
    expect(days.map((d) => d.closure), [
      DayClosure.tooSoon,
      DayClosure.closed,
      DayClosure.none,
    ]);
    expect(days[2].day, DateTime(2026, 10, 19));
    expect(days[2].slots.first.start, DateTime(2026, 10, 19, 9));
    expect(days[2].slots.map((s) => s.free), [true, false]);
  });

  test('holds a slot, sending the UTC instant', () async {
    final r = repo(
      (_) => _json(
        201,
        _appointment(
          status: 'awaiting_payment',
          method: null,
          holdExpiresAt: '2026-10-17T18:15:00Z',
        ),
      ),
    );
    final doctor = _d;
    final hold = await r.hold(doctor, DateTime(2026, 10, 19, 9));
    expect(sent.single.url.path, '/v1/appointments/holds');
    expect(jsonDecode(sent.single.body), {
      'doctor_id': 'd-1',
      'start': '2026-10-19T08:00:00.000Z',
    });
    expect(hold.id, 'a-1');
    expect(hold.start, DateTime(2026, 10, 19, 9));
    expect(hold.expiresAt, DateTime(2026, 10, 17, 19, 15));
  });

  test('a taken slot is SlotUnavailable', () async {
    final r = repo(
      (_) => _json(409, {
        'detail': {'code': 'slot_unavailable'},
      }),
    );
    final doctor = _d;
    expect(
      r.hold(doctor, DateTime(2026, 10, 19, 9)),
      throwsA(isA<SlotUnavailable>()),
    );
  });

  test('releases a hold and ignores a failed release', () async {
    final r = repo((_) => http.Response('', 204));
    final doctor = _d;
    final hold = Hold(
      id: 'a-1',
      doctor: doctor,
      start: DateTime(2026, 10, 19, 9),
      end: DateTime(2026, 10, 19, 9, 15),
      expiresAt: DateTime(2026, 10, 17, 19, 15),
    );
    await r.release(hold);
    expect(sent.single.method, 'DELETE');
    expect(sent.single.url.path, '/v1/appointments/a-1/hold');
    await repo((_) => _json(500, {})).release(hold);
  });

  test('confirms with the chosen method', () async {
    final r = repo((_) => _json(200, _appointment()));
    final doctor = _d;
    final hold = Hold(
      id: 'a-1',
      doctor: doctor,
      start: DateTime(2026, 10, 19, 9),
      end: DateTime(2026, 10, 19, 9, 15),
      expiresAt: DateTime(2026, 10, 17, 19, 15),
    );
    final a = await r.confirm(hold, PaymentMethod.clinic);
    expect(jsonDecode(sent.single.body), {'method': 'clinic'});
    expect(a.status, AppointmentStatus.confirmed);
    expect(a.method, PaymentMethod.clinic);
  });

  test('an expired hold on confirm is SlotUnavailable', () async {
    final r = repo(
      (_) => _json(409, {
        'detail': {'code': 'hold_expired'},
      }),
    );
    final doctor = _d;
    final hold = Hold(
      id: 'a-1',
      doctor: doctor,
      start: DateTime(2026, 10, 19, 9),
      end: DateTime(2026, 10, 19, 9, 15),
      expiresAt: DateTime(2026, 10, 17, 19, 15),
    );
    expect(
      r.confirm(hold, PaymentMethod.clinic),
      throwsA(isA<SlotUnavailable>()),
    );
  });

  test('lists appointments and maps every status', () async {
    final r = repo(
      (_) => _json(200, [
        for (final s in [
          'awaiting_payment',
          'confirmed',
          'completed',
          'cancelled',
          'no_show',
        ])
          _appointment(status: s),
      ]),
    );
    final all = await r.appointments();
    expect(all.map((a) => a.status), AppointmentStatus.values);
  });

  test('cancels, and a refusal inside the notice is TooLateToCancel', () async {
    final a = (await repo(
      (_) => _json(200, [_appointment()]),
    ).appointments()).single;
    final ok = repo((_) => _json(200, _appointment(status: 'cancelled')));
    expect((await ok.cancel(a)).status, AppointmentStatus.cancelled);
    expect(sent.single.url.path, '/v1/appointments/a-1/cancel');
    final late = repo(
      (_) => _json(409, {
        'detail': {'code': 'too_late_to_cancel'},
      }),
    );
    expect(late.cancel(a), throwsA(isA<TooLateToCancel>()));
  });

  test('follow-up is null without a visit, else the suggested day', () async {
    expect(await repo((_) => _json(200, null)).followUp(), isNull);
    final f = await repo(
      (_) => _json(200, {
        'after': _appointment(status: 'completed'),
        'day': '2026-11-18',
        'days': 30,
      }),
    ).followUp();
    expect((f!.day, f.days), (DateTime(2026, 11, 18), 30));
  });

  test('refreshes the login once after a 401 and retries', () async {
    final r = repo(
      (request) => request.headers['authorization'] == 'Bearer access-1'
          ? _json(401, {
              'detail': {'code': 'token_invalid'},
            })
          : _json(200, [_doctor]),
    );
    expect(await r.doctors(), hasLength(1));
    expect(refreshed, 1);
    expect(sent.map((s) => s.headers['authorization']), [
      'Bearer access-1',
      'Bearer access-2',
    ]);
  });

  test('shares one refresh across concurrent expired requests', () async {
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    final r = repo(
      (request) {
        if (request.headers['authorization'] == 'Bearer access-1') {
          return _json(401, {
            'detail': {'code': 'token_invalid'},
          });
        }
        return request.url.path.endsWith('/follow-up')
            ? _json(200, null)
            : _json(200, [_doctor]);
      },
      refresh: () async {
        refreshed++;
        refreshStarted.complete();
        await releaseRefresh.future;
        token = 'access-2';
        return true;
      },
    );

    final doctors = r.doctors();
    await refreshStarted.future;
    final followUp = r.followUp();
    await Future<void>.delayed(Duration.zero);
    expect(refreshed, 1);
    releaseRefresh.complete();

    expect(await doctors, hasLength(1));
    expect(await followUp, isNull);
    expect(refreshed, 1);
  });

  test('malformed server responses become BookingUnavailable', () {
    final r = repo((_) => http.Response('<html>bad gateway</html>', 502));
    expect(r.doctors(), throwsA(isA<BookingUnavailable>()));
  });

  test('network errors become BookingUnavailable', () {
    final r = ApiBookingRepository(
      baseUrl: Uri.parse('http://api.test/'),
      token: () => 't',
      refresh: () async => false,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(r.doctors(), throwsA(isA<BookingUnavailable>()));
  });
}
