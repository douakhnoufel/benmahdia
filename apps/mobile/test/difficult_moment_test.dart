import 'dart:convert';

import 'package:benmahdia_mobile/features/craving/api_craving_repository.dart';
import 'package:benmahdia_mobile/features/craving/craving_models.dart';
import 'package:benmahdia_mobile/features/craving/craving_repository.dart';
import 'package:benmahdia_mobile/features/craving/difficult_moment_screen.dart';
import 'package:benmahdia_mobile/features/craving/fake_craving_repository.dart';
import 'package:benmahdia_mobile/features/craving/moment_entry_card.dart';
import 'package:benmahdia_mobile/l10n/app_localizations.dart';
import 'package:benmahdia_mobile/main.dart';
import 'package:benmahdia_mobile/widgets/breathing_circle.dart';
import 'package:benmahdia_mobile/widgets/sharing_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

// The difficult-moment screen (urge surfing): rate the craving, name a HALT
// state, breathe, rate again, see before and after. Sample data only.

final _ar = lookupAppLocalizations(const Locale('ar'));
final _fr = lookupAppLocalizations(const Locale('fr'));

/// A repository that fails the first [failStart] starts and the first
/// [failPass] passes, like a phone with a poor connection.
class _Flaky extends FakeCravingRepository {
  _Flaky({this.failStart = 0, this.failPass = 0});

  int failStart;
  int failPass;

  @override
  Future<CravingLog> start({
    required int intensity,
    required Set<Halt> halt,
  }) async {
    if (failStart-- > 0) throw const CravingUnavailable();
    return super.start(intensity: intensity, halt: halt);
  }

  @override
  Future<CravingLog> markPassed(CravingLog log, int intensity) async {
    if (failPass-- > 0) throw const CravingUnavailable();
    return super.markPassed(log, intensity);
  }
}

Future<void> _open(
  WidgetTester tester,
  CravingRepository repo, {
  MemoryIfThenPlanStore? plan,
  bool french = false,
  bool reduceMotion = false,
}) async {
  await pumpApp(
    tester,
    const DifficultMomentScreen(),
    reduceMotion: reduceMotion,
    overrides: [
      cravingRepositoryProvider.overrideWithValue(repo),
      ifThenPlanStoreProvider.overrideWithValue(
        plan ?? MemoryIfThenPlanStore(),
      ),
    ],
  );
  await tester.pump();
  if (french) await useFrench(tester);
}

/// Scrolls [target] into view, then taps it.
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
}

/// The breathing circle never stops, so "settled" is a fixed short wait.
Future<void> _settle(WidgetTester tester) =>
    pumpFor(tester, const Duration(milliseconds: 600));

Future<void> _pick(WidgetTester tester, int n) async {
  await tester.tap(find.bySemanticsLabel(_labelOf(tester, n)));
  await tester.pump();
}

String _labelOf(WidgetTester tester, int n) {
  final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
  return l10n.momentIntensityOption(n);
}

void main() {
  group('breathAt', () {
    test('breathe in 4 seconds, hold 4, breathe out 6', () {
      expect(breathAt(Duration.zero).phase, BreathPhase.inhale);
      expect(breathAt(Duration.zero).fill, 0);
      expect(breathAt(const Duration(seconds: 2)).fill, 0.5);
      expect(breathAt(const Duration(seconds: 4)).phase, BreathPhase.hold);
      expect(breathAt(const Duration(seconds: 7)).fill, 1);
      expect(breathAt(const Duration(seconds: 8)).phase, BreathPhase.exhale);
      expect(breathAt(const Duration(seconds: 11)).fill, 0.5);
      expect(breathAt(const Duration(seconds: 14)).phase, BreathPhase.inhale);
      expect(breathAt(const Duration(seconds: 15)).fill, 0.25);
    });
  });

  group('setup', () {
    testWidgets('Start needs an intensity; HALT is optional (ar)', (
      tester,
    ) async {
      await _open(tester, FakeCravingRepository());
      expect(directionOf(tester, DifficultMomentScreen), TextDirection.rtl);
      expect(find.text(_ar.momentIntensityTitle), findsOneWidget);
      for (final h in [
        _ar.momentHaltHungry,
        _ar.momentHaltAngry,
        _ar.momentHaltLonely,
        _ar.momentHaltTired,
      ]) {
        expect(find.text(h), findsOneWidget);
      }
      final start = find.widgetWithText(FilledButton, _ar.momentStart);
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      await _pick(tester, 7);
      expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    });

    testWidgets('says that the doctor sees the log (fr)', (tester) async {
      await _open(tester, FakeCravingRepository(), french: true);
      expect(find.text(_fr.sharingDoctor), findsOneWidget);
      expect(find.text(_fr.momentIntro), findsOneWidget);
    });

    testWidgets('intensity circles and chips are at least 44 px', (
      tester,
    ) async {
      await _open(tester, FakeCravingRepository());
      for (var n = 1; n <= 10; n++) {
        final box = find.bySemanticsLabel(_ar.momentIntensityOption(n));
        final size = tester.getSize(box);
        expect(size.width, greaterThanOrEqualTo(44), reason: 'circle $n');
        expect(size.height, greaterThanOrEqualTo(44), reason: 'circle $n');
      }
      final chip = tester.getSize(find.byType(FilterChip).first);
      expect(chip.height, greaterThanOrEqualTo(44));
    });

    testWidgets('fits a 320 px phone in both languages', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cravingRepositoryProvider.overrideWithValue(
              FakeCravingRepository(),
            ),
            ifThenPlanStoreProvider.overrideWithValue(MemoryIfThenPlanStore()),
          ],
          child: const BenMahdiaApp(home: DifficultMomentScreen()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('the moment', () {
    testWidgets('full flow: rate, breathe, pass, rate, result (ar)', (
      tester,
    ) async {
      final repo = FakeCravingRepository(clock: () => DateTime(2026, 11, 2));
      await _open(tester, repo);
      await _pick(tester, 8);
      await tester.tap(find.text(_ar.momentHaltTired));
      await tester.pump();
      await tester.tap(find.text(_ar.momentStart));
      await tester.pump();

      // Breathing: the circle speaks, the timer runs, the tip and the plan
      // card are there, urgent help is one tap away.
      expect(find.text(_ar.momentInhale), findsOneWidget);
      await pumpFor(tester, const Duration(seconds: 5));
      expect(find.text(_ar.momentHold), findsOneWidget);
      expect(find.text(_ar.momentTimer('00:05')), findsOneWidget);
      expect(find.text(_ar.momentTipBody), findsOneWidget);
      expect(find.text(_ar.momentTipCaution), findsOneWidget);
      expect(find.text(_ar.momentPlanEmpty), findsOneWidget);
      expect(find.text(_ar.companionUrgent), findsOneWidget);
      expect((await repo.recent()).single.before, 8);

      await _tap(tester, find.text(_ar.momentPassed));
      expect(find.text(_ar.momentAfterTitle), findsOneWidget);
      await _pick(tester, 3);
      await tester.tap(find.text(_ar.momentFinish));
      await tester.pump();
      await tester.pump();

      expect(find.text(_ar.momentResultTitle), findsOneWidget);
      expect(find.text(_ar.momentBefore), findsOneWidget);
      expect(find.text(_ar.momentAfter), findsOneWidget);
      expect(find.text(_ar.momentResultDown), findsOneWidget);
      final saved = (await repo.recent()).single;
      expect([saved.before, saved.after], [8, 3]);
      expect(saved.halt, {Halt.tired});
      expect(saved.isPassed, isTrue);
    });

    testWidgets('a craving that did not drop gets a calm, honest line (fr)', (
      tester,
    ) async {
      await _open(tester, FakeCravingRepository(), french: true);
      await _pick(tester, 5);
      await tester.tap(find.text(_fr.momentStart));
      await tester.pump();
      await _tap(tester, find.text(_fr.momentPassed));
      await _pick(tester, 6);
      await tester.tap(find.text(_fr.momentFinish));
      await tester.pump();
      await tester.pump();
      expect(find.text(_fr.momentResultSame), findsOneWidget);
      expect(find.text(_fr.momentResultDown), findsNothing);
    });

    testWidgets('a failed start never blocks the patient', (tester) async {
      final repo = _Flaky(failStart: 1);
      await _open(tester, repo);
      await _pick(tester, 9);
      await tester.tap(find.text(_ar.momentStart));
      await tester.pump();
      expect(find.text(_ar.momentInhale), findsOneWidget);
      await _tap(tester, find.text(_ar.momentPassed));
      await _pick(tester, 2);
      await tester.tap(find.text(_ar.momentFinish));
      await tester.pump();
      await tester.pump();
      // The moment is saved at the end, with both numbers.
      expect(find.text(_ar.momentResultTitle), findsOneWidget);
      final saved = (await repo.recent()).single;
      expect([saved.before, saved.after], [9, 2]);
    });

    testWidgets('a failed save shows a message and can be retried', (
      tester,
    ) async {
      final repo = _Flaky(failPass: 1);
      await _open(tester, repo);
      await _pick(tester, 6);
      await tester.tap(find.text(_ar.momentStart));
      await tester.pump();
      await _tap(tester, find.text(_ar.momentPassed));
      await _pick(tester, 4);
      await tester.tap(find.text(_ar.momentFinish));
      await tester.pump();
      await tester.pump();
      expect(find.text(_ar.momentSaveFailed), findsOneWidget);
      expect(find.text(_ar.momentResultTitle), findsNothing);
      await tester.tap(find.text(_ar.momentFinish));
      await tester.pump();
      await tester.pump();
      expect(find.text(_ar.momentResultTitle), findsOneWidget);
      expect((await repo.recent()).single.after, 4);
    });

    testWidgets('urgent help opens from the first screen', (tester) async {
      await _open(tester, FakeCravingRepository());
      await _tap(tester, find.text(_ar.companionUrgent));
      await tester.pumpAndSettle();
      expect(find.text(_ar.crisisTitle), findsOneWidget);
    });

    testWidgets('reduced motion keeps the circle still but still speaks', (
      tester,
    ) async {
      await _open(tester, FakeCravingRepository(), reduceMotion: true);
      await _pick(tester, 5);
      await tester.tap(find.text(_ar.momentStart));
      await tester.pump();
      expect(find.text(_ar.momentInhale), findsOneWidget);
      await pumpFor(tester, const Duration(seconds: 5));
      expect(find.text(_ar.momentHold), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('if-then plan', () {
    testWidgets('written once, kept on the phone, labelled "only you"', (
      tester,
    ) async {
      final store = MemoryIfThenPlanStore();
      await _open(tester, FakeCravingRepository(), plan: store);
      await _pick(tester, 4);
      await tester.tap(find.text(_ar.momentStart));
      await tester.pump();
      expect(find.text(_ar.sharingOnlyYou), findsOneWidget);

      await _tap(tester, find.text(_ar.momentPlanAdd));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).at(0), 'شعرت بالوحدة');
      await tester.enterText(find.byType(TextField).at(1), 'اتصلت بأخي');
      await tester.tap(find.text(_ar.momentPlanSave));
      await _settle(tester);

      expect(
        find.text(_ar.momentPlanLine('شعرت بالوحدة', 'اتصلت بأخي')),
        findsOneWidget,
      );
      expect(store.plan?.thenText, 'اتصلت بأخي');
      expect(find.text(_ar.momentPlanEdit), findsOneWidget);
    });

    testWidgets('an empty half is not saved', (tester) async {
      final store = MemoryIfThenPlanStore();
      await _open(tester, FakeCravingRepository(), plan: store);
      await _pick(tester, 4);
      await tester.tap(find.text(_ar.momentStart));
      await tester.pump();
      await _tap(tester, find.text(_ar.momentPlanAdd));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).at(0), 'x');
      await tester.tap(find.text(_ar.momentPlanSave));
      await _settle(tester);
      expect(store.plan, isNull);
    });
  });

  group('entry', () {
    testWidgets('the card opens the screen', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(body: MomentEntryCard()),
        overrides: [
          cravingRepositoryProvider.overrideWithValue(FakeCravingRepository()),
          ifThenPlanStoreProvider.overrideWithValue(MemoryIfThenPlanStore()),
        ],
      );
      await tester.pump();
      expect(find.text(_ar.momentEntryTitle), findsOneWidget);
      expect(
        tester.getSize(find.byType(MomentEntryCard)).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.byType(MomentEntryCard));
      await tester.pumpAndSettle();
      expect(find.byType(DifficultMomentScreen), findsOneWidget);
    });
  });

  group('sharing label', () {
    testWidgets('both audiences, both languages', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(
          body: Column(
            children: [
              SharingLabel(Audience.onlyYou),
              SharingLabel(Audience.yourDoctor),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.text(_ar.sharingOnlyYou), findsOneWidget);
      expect(find.text(_ar.sharingDoctor), findsOneWidget);
      await useFrench(tester);
      expect(find.text(_fr.sharingOnlyYou), findsOneWidget);
      expect(find.text(_fr.sharingDoctor), findsOneWidget);
    });
  });

  group('wording', () {
    test('no exclamation mark and no emoji in the new strings', () {
      final emoji = RegExp(
        r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]',
        unicode: true,
      );
      for (final l10n in [_ar, _fr]) {
        final strings = [
          l10n.momentEntryTitle,
          l10n.momentEntrySub,
          l10n.momentTitle,
          l10n.momentIntro,
          l10n.momentIntensityTitle,
          l10n.momentHaltTitle,
          l10n.momentStart,
          l10n.momentTipTitle,
          l10n.momentTipBody,
          l10n.momentTipCaution,
          l10n.momentPlanTitle,
          l10n.momentPlanEmpty,
          l10n.momentPassed,
          l10n.momentAfterTitle,
          l10n.momentSaveFailed,
          l10n.momentResultTitle,
          l10n.momentResultDown,
          l10n.momentResultSame,
          l10n.sharingOnlyYou,
          l10n.sharingDoctor,
        ];
        for (final s in strings) {
          expect(s.contains('!'), isFalse, reason: s);
          expect(s.contains('！'), isFalse, reason: s);
          expect(emoji.hasMatch(s), isFalse, reason: s);
        }
      }
    });
  });

  group('API', () {
    http.Response json(int status, Object? body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

    Map<String, Object?> row({int? after, String? passed}) => {
      'id': 'c-1',
      'intensity_before': 8,
      'intensity_after': after,
      'halt': ['tired', 'lonely'],
      'created_at': '2026-11-02T18:00:00',
      'passed_at': passed,
    };

    late List<http.Request> sent;

    ApiCravingRepository repo(http.Response Function(http.Request) answer) {
      sent = [];
      return ApiCravingRepository(
        baseUrl: Uri.parse('http://api.test/'),
        token: () => 'access-1',
        refresh: () async => false,
        client: MockClient((request) async {
          sent.add(request);
          return answer(request);
        }),
      );
    }

    test('start posts the intensity and the HALT keys only', () async {
      final api = repo((_) => json(201, row()));
      final log = await api.start(
        intensity: 8,
        halt: {Halt.tired, Halt.lonely},
      );
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, '/v1/me/cravings');
      expect(sent.single.headers['authorization'], 'Bearer access-1');
      expect(jsonDecode(sent.single.body), {
        'intensity_before': 8,
        'halt': ['tired', 'lonely'],
      });
      expect(log.id, 'c-1');
      expect(log.before, 8);
      expect(log.halt, {Halt.tired, Halt.lonely});
      expect(log.isPassed, isFalse);
    });

    test('markPassed posts the second intensity', () async {
      final api = repo(
        (_) => json(200, row(after: 3, passed: '2026-11-02T18:05:00')),
      );
      final start = CravingLog(
        id: 'c-1',
        before: 8,
        halt: const {},
        startedAt: DateTime(2026, 11, 2),
      );
      final done = await api.markPassed(start, 3);
      expect(sent.single.url.path, '/v1/me/cravings/c-1/passed');
      expect(jsonDecode(sent.single.body), {'intensity_after': 3});
      expect(done.after, 3);
      expect(done.isPassed, isTrue);
    });

    test('recent lists the moments', () async {
      final api = repo((_) => json(200, [row()]));
      final list = await api.recent();
      expect(sent.single.method, 'GET');
      expect(list.single.before, 8);
    });

    test('server errors and bad bodies become CravingUnavailable', () async {
      expect(
        repo((_) => json(500, {})).recent(),
        throwsA(isA<CravingUnavailable>()),
      );
      expect(
        repo((_) => json(409, {'detail': {'code': 'craving_already_passed'}}))
            .markPassed(
              CravingLog(
                id: 'c-1',
                before: 5,
                halt: const {},
                startedAt: DateTime(2026, 11, 2),
              ),
              2,
            ),
        throwsA(isA<CravingUnavailable>()),
      );
      expect(
        repo((_) => json(200, {'oops': 1})).recent(),
        throwsA(isA<CravingUnavailable>()),
      );
    });
  });
}
