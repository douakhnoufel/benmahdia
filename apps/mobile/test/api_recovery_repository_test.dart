import 'dart:convert';

import 'package:benmahdia_mobile/features/recovery/api_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/fake_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _addiction({
  String id = 'a-1',
  String type = 'cannabis',
  String? substance = 'haschich',
  String since = '2026-10-07T18:00:00Z',
  int longest = 0,
  int past = 0,
  String review = 'pending',
}) => {
  'id': id,
  'type': type,
  'substance': substance,
  'clean_since': since,
  'longest_past_days': longest,
  'past_days': past,
  'review_status': review,
};

http.Response _json(int status, Object? body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late List<http.Request> sent;
  var token = 'access-1';
  var refreshed = 0;

  ApiRecoveryRepository repo(
    http.Response Function(http.Request) answer, {
    Future<bool> Function()? refresh,
  }) {
    sent = [];
    return ApiRecoveryRepository(
      baseUrl: Uri.parse('http://api.test/'),
      token: () => token,
      refresh:
          refresh ??
          () async {
            refreshed++;
            token = 'access-2';
            return true;
          },
      rest: FakeRecoveryRepository(),
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

  test('lists the addictions with their counters and review state', () async {
    final r = repo(
      (_) => _json(200, [
        _addiction(),
        _addiction(id: 'a-2', review: 'confirmed', longest: 8, past: 11),
      ]),
    );
    final [pending, confirmed] = await r.addictions();
    expect(sent.single.method, 'GET');
    expect(sent.single.url.path, '/v1/me/addictions');
    expect(sent.single.headers['authorization'], 'Bearer access-1');
    expect(pending.type, AddictionType.cannabis);
    expect(pending.substance, 'haschich');
    expect(pending.reviewed, isFalse);
    expect(pending.start.toUtc(), DateTime.utc(2026, 10, 7, 18));
    expect(confirmed.reviewed, isTrue);
    expect((confirmed.longestPastDays, confirmed.pastDays), (8, 11));
  });

  test('adds an addiction, sending the clean-since date in UTC', () async {
    final r = repo((_) => _json(201, _addiction(type: 'alcohol')));
    final added = await r.addAddiction(
      type: AddictionType.alcohol,
      cleanSince: DateTime.utc(2026, 10, 7, 18),
      substance: 'vin',
    );
    expect(sent.single.method, 'POST');
    expect(sent.single.url.path, '/v1/me/addictions');
    expect(jsonDecode(sent.single.body), {
      'type': 'alcohol',
      'substance': 'vin',
      'clean_since': '2026-10-07T18:00:00.000Z',
    });
    expect(added.type, AddictionType.alcohol);
  });

  test('logs a relapse and returns the restarted counter', () async {
    final r = repo(
      (_) => _json(
        201,
        _addiction(since: '2026-10-15T09:30:00Z', longest: 8, past: 8),
      ),
    );
    final before = Addiction(
      id: 'a-1',
      type: AddictionType.cannabis,
      start: DateTime.utc(2026, 10, 7, 9),
      longestPastDays: 0,
      pastDays: 0,
    );
    final after = await r.logRelapse(
      before,
      note: 'soirée',
      at: DateTime.utc(2026, 10, 15, 9, 30),
    );
    expect(sent.single.url.path, '/v1/me/addictions/a-1/relapses');
    expect(jsonDecode(sent.single.body), {
      'at': '2026-10-15T09:30:00.000Z',
      'note': 'soirée',
    });
    expect(after.start.toUtc(), DateTime.utc(2026, 10, 15, 9, 30));
    expect((after.longestPastDays, after.pastDays), (8, 8));
  });

  test('leaves out the time and note when there are none', () async {
    final r = repo((_) => _json(201, _addiction()));
    final a = Addiction(
      id: 'a-1',
      type: AddictionType.cannabis,
      start: DateTime.utc(2026, 10, 7),
      longestPastDays: 0,
      pastDays: 0,
    );
    await r.logRelapse(a);
    expect(jsonDecode(sent.single.body), isEmpty);
  });

  test('refreshes once on 401 and retries with the new token', () async {
    final r = repo(
      (request) => request.headers['authorization'] == 'Bearer access-2'
          ? _json(200, [_addiction()])
          : _json(401, {
              'detail': {'code': 'token_invalid'},
            }),
    );
    expect(await r.addictions(), hasLength(1));
    expect(refreshed, 1);
    expect(sent.map((s) => s.headers['authorization']), [
      'Bearer access-1',
      'Bearer access-2',
    ]);
  });

  test('is unavailable when the refresh fails', () async {
    final r = repo((_) => _json(401, const {}), refresh: () async => false);
    await expectLater(r.addictions(), throwsA(isA<RecoveryUnavailable>()));
  });

  test('is unavailable on a server error, bad JSON or no network', () async {
    await expectLater(
      repo((_) => _json(500, const {})).addictions(),
      throwsA(isA<RecoveryUnavailable>()),
    );
    await expectLater(
      repo((_) => http.Response('<html>', 200)).addictions(),
      throwsA(isA<RecoveryUnavailable>()),
    );
    await expectLater(
      repo((_) => _json(200, {'oops': 1})).addictions(),
      throwsA(isA<RecoveryUnavailable>()),
    );
    await expectLater(
      repo((_) => _json(200, [_addiction(type: 'coffee')])).addictions(),
      throwsA(isA<RecoveryUnavailable>()),
    );
    final offline = ApiRecoveryRepository(
      baseUrl: Uri.parse('http://api.test/'),
      token: () => token,
      refresh: () async => false,
      rest: FakeRecoveryRepository(),
      client: MockClient((_) async => throw http.ClientException('down')),
    );
    await expectLater(offline.addictions(), throwsA(isA<RecoveryUnavailable>()));
  });

  test('reads the ticked days as calendar days', () async {
    final r = repo((_) => _json(200, ['2026-10-16', '2026-10-17']));
    expect(await r.checkIns(), {DateTime(2026, 10, 16), DateTime(2026, 10, 17)});
    expect(sent.single.url.path, '/v1/me/checkins');
    await expectLater(
      repo((_) => _json(200, ['oops'])).checkIns(),
      throwsA(isA<RecoveryUnavailable>()),
    );
  });

  test('ticks a day with a PUT on that date', () async {
    final r = repo((_) => http.Response('', 204));
    await r.checkIn(DateTime(2026, 10, 7, 21, 30));
    expect(sent.single.method, 'PUT');
    expect(sent.single.url.path, '/v1/me/checkins/2026-10-07');
  });

  test('a failed tick is reported', () async {
    await expectLater(
      repo((_) => _json(422, const {})).checkIn(DateTime(2026, 10, 17)),
      throwsA(isA<RecoveryUnavailable>()),
    );
  });

  test('reads, sets and clears the reminder time', () async {
    expect(
      await repo((_) => _json(200, {'time': '21:05'})).reminder(),
      (hour: 21, minute: 5),
    );
    expect(await repo((_) => _json(200, {'time': null})).reminder(), isNull);
    await expectLater(
      repo((_) => _json(200, {'time': '9pm'})).reminder(),
      throwsA(isA<RecoveryUnavailable>()),
    );
    final r = repo((_) => _json(200, {'time': '08:00'}));
    await r.setReminder((hour: 8, minute: 0));
    expect(sent.single.method, 'PUT');
    expect(sent.single.url.path, '/v1/me/reminder');
    expect(jsonDecode(sent.single.body), {'time': '08:00'});
    await r.setReminder(null);
    expect(jsonDecode(sent.last.body), {'time': null});
  });

  test("lists today's doses for the phone's day", () async {
    final r = repo(
      (_) => _json(200, [
        {
          'medication_id': 'm-1',
          'name': 'Sertraline',
          'amount': '50 mg',
          'instruction': 'Après le repas',
          'time': '08:00',
          'status': 'taken',
        },
        {
          'medication_id': 'm-1',
          'name': 'Sertraline',
          'amount': '50 mg',
          'instruction': null,
          'time': '20:30',
          'status': 'missed',
        },
      ]),
    );
    final [morning, evening] = await r.todaysDoses();
    expect(sent.single.url.path, '/v1/me/doses');
    expect(sent.single.url.queryParameters, {'day': '2026-10-17'});
    expect(morning.id, 'm-1|08:00');
    expect(morning.name.of('fr'), 'Sertraline');
    expect(morning.name.of('ar'), 'Sertraline');
    expect(morning.instruction?.of('fr'), 'Après le repas');
    expect((morning.hour, morning.minute), (8, 0));
    expect(morning.status, DoseStatus.taken);
    expect(evening.instruction, isNull);
    expect((evening.hour, evening.minute), (20, 30));
    expect(evening.status, DoseStatus.due);
  });

  test('answers a dose taken or skipped', () async {
    final r = repo(
      (_) => _json(200, {
        'medication_id': 'm-1',
        'name': 'Sertraline',
        'amount': '50 mg',
        'instruction': null,
        'time': '08:00',
        'status': 'skipped',
      }),
    );
    const dose = Dose(
      id: 'm-1|08:00',
      name: LocalizedText(ar: 'Sertraline', fr: 'Sertraline'),
      amount: LocalizedText(ar: '50 mg', fr: '50 mg'),
      hour: 8,
      minute: 0,
      status: DoseStatus.due,
    );
    final updated = await r.markDose(dose, DoseStatus.skipped);
    expect(sent.single.method, 'PUT');
    expect(sent.single.url.path, '/v1/me/doses');
    expect(jsonDecode(sent.single.body), {
      'medication_id': 'm-1',
      'day': '2026-10-17',
      'time': '08:00',
      'status': 'skipped',
    });
    expect(updated.status, DoseStatus.skipped);
    // "Due" is not an answer: nothing is sent.
    expect(await r.markDose(dose, DoseStatus.due), same(dose));
    expect(sent, hasLength(1));
  });

  test('reads the quote of the day without an author line', () async {
    final r = repo((_) => _json(200, {'text_ar': 'يوماً بعد يوم.', 'text_fr': 'Un jour à la fois.'}));
    final quote = (await r.quoteOfDay())!;
    expect(sent.single.url.path, '/v1/me/quote');
    expect(quote.text.of('fr'), 'Un jour à la fois.');
    expect(quote.text.of('ar'), 'يوماً بعد يوم.');
    expect(quote.source.of('fr'), isEmpty);
  });

  test('has no quote when the server has none, but fails on a real error', () async {
    expect(
      await repo(
        (_) => _json(404, {
          'detail': {'code': 'no_quote'},
        }),
      ).quoteOfDay(),
      isNull,
    );
    await expectLater(
      repo((_) => _json(500, const {})).quoteOfDay(),
      throwsA(isA<RecoveryUnavailable>()),
    );
  });

  test('keeps the clinic card local and tells the time', () async {
    final r = repo((_) => _json(500, const {}));
    expect((await r.clinic()).phones, isNotEmpty);
    expect(sent, isEmpty);
    expect(r.now(), DateTime.utc(2026, 10, 17, 18));
  });
}
