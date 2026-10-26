import 'dart:convert';

import 'package:benmahdia_mobile/features/recovery/api_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/fake_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Per-substance tracking, small goals and good habits over the API
// (backend/app/routers/addiction_checks.py, habits.py; PRD 5.6).

http.Response _json(int status, Object? body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _addiction({String? profile, int? goal}) => {
  'id': 'a-1',
  'type': 'pills',
  'profile': profile,
  'goal_days': goal,
  'substance': null,
  'clean_since': '2026-10-07T18:00:00Z',
  'longest_past_days': 0,
  'past_days': 0,
  'review_status': 'confirmed',
  'goal': 14,
};

Map<String, Object?> _habit({
  String id = 'h-1',
  String kind = 'brush_teeth',
  String? text,
  String? reminder = '21:30',
  List<String> days = const ['2026-10-16'],
}) => {
  'id': id,
  'kind': kind,
  'text': text,
  'reminder_time': reminder,
  'days': days,
};

const _habitBrush = Habit(id: 'h-1', kind: HabitKind.brushTeeth);

void main() {
  late List<http.Request> sent;

  ApiRecoveryRepository repo(http.Response Function(http.Request) answer) {
    sent = [];
    return ApiRecoveryRepository(
      baseUrl: Uri.parse('http://api.test/'),
      token: () => 'access-1',
      refresh: () async => false,
      rest: FakeRecoveryRepository(),
      clock: () => DateTime(2026, 10, 17, 18),
      // Each check looks at the latest request only.
      client: MockClient((request) async {
        sent = [request];
        return answer(request);
      }),
    );
  }

  group('lock', () {
    test('recovery_locked becomes RecoveryLocked', () async {
      final r = repo(
        (_) => _json(403, {
          'detail': {'code': 'recovery_locked'},
        }),
      );
      await expectLater(r.addictions(), throwsA(isA<RecoveryLocked>()));
      await expectLater(r.habits(), throwsA(isA<RecoveryLocked>()));
    });

    test('another 403 is only unavailable', () async {
      final r = repo(
        (_) => _json(403, {
          'detail': {'code': 'forbidden'},
        }),
      );
      await expectLater(
        r.addictions(),
        throwsA(
          isA<RecoveryUnavailable>().having(
            (e) => e is RecoveryLocked,
            'locked',
            isFalse,
          ),
        ),
      );
    });
  });

  group('profiles and checks', () {
    test('reads the profile catalog', () async {
      final r = repo(
        (_) => _json(200, [
          {
            'key': 'pregabalin',
            'type': 'pills',
            'name': {'ar': 'البريغابالين', 'fr': 'Prégabaline'},
            'signals': [
              {
                'key': 'anxiety',
                'label': {'ar': 'القلق', 'fr': 'Anxiété'},
              },
              {
                'key': 'sleep',
                'label': {'ar': 'صعوبة النوم', 'fr': 'Troubles du sommeil'},
              },
            ],
            'notes': [
              {
                'day': 3,
                'text': {'ar': 'ع', 'fr': 'f'},
              },
            ],
          },
        ]),
      );
      final [p] = await r.profiles();
      expect(sent.single.url.path, '/v1/me/recovery/profiles');
      expect(p.profile, SubstanceProfile.pregabalin);
      expect(p.type, AddictionType.pills);
      expect(p.name.fr, 'Prégabaline');
      expect([for (final s in p.signals) s.key], ['anxiety', 'sleep']);
      expect(p.notes.single.day, 3);
    });

    test('a malformed catalog is unavailable, not a crash', () async {
      final r = repo(
        (_) => _json(200, [
          {'key': 'heroin'},
        ]),
      );
      await expectLater(r.profiles(), throwsA(isA<RecoveryUnavailable>()));
    });

    test('adds an addiction by profile, without a type', () async {
      final r = repo((_) => _json(201, _addiction(profile: 'pregabalin')));
      final a = await r.addAddiction(
        profile: SubstanceProfile.pregabalin,
        cleanSince: DateTime.utc(2026, 10, 7, 18),
      );
      expect(jsonDecode(sent.single.body), {
        'profile': 'pregabalin',
        'substance': null,
        'clean_since': '2026-10-07T18:00:00.000Z',
      });
      expect(a.profile, SubstanceProfile.pregabalin);
    });

    test('reads the checks and the fully checked days', () async {
      final r = repo(
        (_) => _json(200, {
          'checks': [
            {
              'addiction_id': 'a-1',
              'day': '2026-10-16',
              'used': false,
              'craving': 3,
              'signals': {'anxiety': 2, 'sleep': 4},
            },
          ],
          'done_days': ['2026-10-16'],
        }),
      );
      final history = await r.addictionChecks();
      expect(sent.single.url.path, '/v1/me/addiction-checks');
      final c = history.checks.single;
      expect(
        (c.addictionId, c.day, c.used, c.craving),
        ('a-1', DateTime(2026, 10, 16), false, 3),
      );
      expect(c.signals, {'anxiety': 2, 'sleep': 4});
      expect(history.doneDays, {DateTime(2026, 10, 16)});
    });

    test('saves a check on its day', () async {
      final r = repo((_) => http.Response('', 204));
      await r.saveCheck(
        AddictionCheck(
          addictionId: 'a-1',
          day: DateTime(2026, 10, 17),
          used: true,
          craving: 5,
          signals: const {'anxiety': 4, 'sleep': 3},
        ),
      );
      expect(sent.single.method, 'PUT');
      expect(sent.single.url.path, '/v1/me/addictions/a-1/checks/2026-10-17');
      expect(jsonDecode(sent.single.body), {
        'used': true,
        'craving': 5,
        'signals': {'anxiety': 4, 'sleep': 3},
      });
    });

    test('sets and clears the small goal', () async {
      final r = repo(
        (request) => _json(
          200,
          _addiction(goal: jsonDecode(request.body)['days'] as int?),
        ),
      );
      final a = Addiction(
        id: 'a-1',
        type: AddictionType.pills,
        start: DateTime.utc(2026, 10, 7, 18),
        longestPastDays: 0,
        pastDays: 0,
      );
      expect((await r.setGoal(a, 28)).goalDays, 28);
      expect(sent.single.url.path, '/v1/me/addictions/a-1/goal');
      expect((await r.setGoal(a, null)).goalDays, isNull);
      expect(jsonDecode(sent.single.body), {'days': null});
    });
  });

  group('habits', () {
    test('reads the catalog in both languages', () async {
      final r = repo(
        (_) => _json(200, [
          {
            'kind': 'call_family',
            'label': {'ar': 'الاتصال بالعائلة', 'fr': 'Appeler la famille'},
          },
        ]),
      );
      final catalog = await r.habitCatalog();
      expect(sent.single.url.path, '/v1/me/habits/catalog');
      expect(catalog[HabitKind.callFamily]?.fr, 'Appeler la famille');
    });

    test('lists habits with their reminder and days', () async {
      final r = repo(
        (_) => _json(200, [
          _habit(),
          _habit(id: 'h-2', kind: 'custom', text: 'Jardiner', reminder: null),
        ]),
      );
      final [brush, own] = await r.habits();
      expect(brush.kind, HabitKind.brushTeeth);
      expect(brush.reminder, (hour: 21, minute: 30));
      expect(brush.days, {DateTime(2026, 10, 16)});
      expect(
        (own.kind, own.text, own.reminder),
        (HabitKind.custom, 'Jardiner', null),
      );
    });

    test('adds a habit with the wire names', () async {
      final r = repo((_) => _json(201, _habit()));
      await r.addHabit(HabitKind.brushTeeth, reminder: (hour: 21, minute: 30));
      expect(sent.single.method, 'POST');
      expect(jsonDecode(sent.single.body), {
        'kind': 'brush_teeth',
        'reminder_time': '21:30',
      });
      await r.addHabit(HabitKind.custom, text: 'Jardiner');
      expect(jsonDecode(sent.single.body), {
        'kind': 'custom',
        'text': 'Jardiner',
      });
    });

    test('ticks, unticks, sets the reminder and removes', () async {
      final r = repo(
        (request) => request.url.path.endsWith('/reminder')
            ? _json(200, _habit(reminder: null))
            : http.Response('', 204),
      );
      await r.markHabit(_habitBrush, DateTime(2026, 10, 17), done: true);
      expect(
        (sent.single.method, sent.single.url.path),
        ('PUT', '/v1/me/habits/h-1/days/2026-10-17'),
      );
      await r.markHabit(_habitBrush, DateTime(2026, 10, 17), done: false);
      expect(sent.single.method, 'DELETE');
      final updated = await r.setHabitReminder(_habitBrush, null);
      expect(jsonDecode(sent.single.body), {'time': null});
      expect(updated.reminder, isNull);
      await r.removeHabit(_habitBrush);
      expect(
        (sent.single.method, sent.single.url.path),
        ('DELETE', '/v1/me/habits/h-1'),
      );
    });

    test('an unknown habit kind is unavailable', () async {
      final r = repo((_) => _json(200, [_habit(kind: 'yoga')]));
      await expectLater(r.habits(), throwsA(isA<RecoveryUnavailable>()));
    });
  });
}
