import 'package:benmahdia_mobile/features/booking/payment_launcher.dart';
import 'package:benmahdia_mobile/features/craving/craving_models.dart';
import 'package:benmahdia_mobile/features/craving/craving_repository.dart';
import 'package:benmahdia_mobile/features/craving/difficult_moment_screen.dart';
import 'package:benmahdia_mobile/features/craving/fake_craving_repository.dart';
import 'package:benmahdia_mobile/features/recovery/fake_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// Saturday 17 October 2026, 10:00: the clinic is open 07:30-14:30.
final _open = DateTime(2026, 10, 17, 10);
// Saturday, 03:00: closed.
final _closed = DateTime(2026, 10, 17, 3);

class _Failing implements CravingRepository {
  @override
  Future<CravingLog> start(int intensity, List<HaltTrigger> triggers) =>
      throw const CravingUnavailable();

  @override
  Future<CravingLog> passed(String id, int intensity) =>
      throw const CravingUnavailable();

  @override
  Future<List<CravingLog>> recent({int days = 30}) =>
      throw const CravingUnavailable();
}

Future<FakeCravingRepository> _pump(
  WidgetTester tester, {
  DateTime? now,
  bool reduceMotion = false,
  CravingRepository? repo,
  List<Uri>? opened,
}) async {
  final fake = FakeCravingRepository(clock: () => _open);
  await pumpApp(
    tester,
    DifficultMomentScreen(now: () => now ?? _open),
    reduceMotion: reduceMotion,
    overrides: [
      cravingRepositoryProvider.overrideWithValue(repo ?? fake),
      recoveryRepositoryProvider.overrideWithValue(
        FakeRecoveryRepository(clock: () => _open),
      ),
      openUrlProvider.overrideWithValue((url) async {
        opened?.add(url);
        return true;
      }),
    ],
  );
  await tester.pumpAndSettle();
  // The sample clinic answers after a short delay.
  await tester.pump(const Duration(milliseconds: 300));
  return fake;
}

/// Starts the moment and lands on the breathing view.
Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.text('ابدأ'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Unmounts the screen so the breathing timer is cancelled.
Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('shows the doctor sharing label, in Arabic', (tester) async {
    await _pump(tester);
    expect(find.text('طبيبك يرى هذا'), findsOneWidget);
    expect(directionOf(tester, DifficultMomentScreen), TextDirection.rtl);
    expect(find.text('جوع'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('shows the doctor sharing label, in French', (tester) async {
    await _pump(tester);
    await useFrench(tester);
    expect(find.text('Votre médecin voit ceci'), findsOneWidget);
    expect(find.text('Faim'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('start saves the craving with its triggers', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('جوع'));
    await tester.tap(find.text('تعب'));
    await _start(tester);
    final logs = await repo.recent();
    expect(logs, hasLength(1));
    expect(logs.single.before, 5);
    expect(logs.single.triggers, [HaltTrigger.hungry, HaltTrigger.tired]);
    expect(find.text('تنفّس مع الدائرة'), findsWidgets);
    await _leave(tester);
  });

  testWidgets('breathing: inhale 4, hold 4, exhale 6', (tester) async {
    await _pump(tester);
    await _start(tester);
    expect(find.text('شهيق'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('احبس النفَس'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('زفير'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('شهيق'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('breathing still guides under reduced motion', (tester) async {
    await _pump(tester, reduceMotion: true);
    await _start(tester);
    expect(find.text('شهيق'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('احبس النفَس'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('another tip rotates the tip', (tester) async {
    await _pump(tester);
    await _start(tester);
    // The 17th % 4 = 1: the mint gum tip.
    expect(find.text('امضغ علكة بالنعناع'), findsOneWidget);
    await tester.tap(find.text('نصيحة أخرى'));
    await tester.pump();
    expect(find.text('اشرب كوب ماء ببطء'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('the plan is marked only you', (tester) async {
    await _pump(tester);
    await _start(tester);
    expect(find.text('أنت فقط'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('clinic open or closed follows its hours', (tester) async {
    await _pump(tester);
    await _start(tester);
    expect(find.text('العيادة مفتوحة الآن'), findsOneWidget);
    await _leave(tester);

    await _pump(tester, now: _closed);
    await _start(tester);
    expect(find.text('العيادة مغلقة الآن'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('call the clinic opens the dialer', (tester) async {
    final opened = <Uri>[];
    await _pump(tester, opened: opened);
    await _start(tester);
    await tester.ensureVisible(find.text('اتصل بالعيادة'));
    await tester.pump();
    await tester.tap(find.text('اتصل بالعيادة'));
    await tester.pump();
    expect(opened.single.scheme, 'tel');
    await _leave(tester);
  });

  testWidgets('urgent help is always there', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('مساعدة عاجلة'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('it passed records the after score', (tester) async {
    final repo = await _pump(tester);
    await _start(tester);
    await tester.ensureVisible(find.text('مرّت الرغبة'));
    await tester.pump();
    await tester.tap(find.text('مرّت الرغبة'));
    await tester.pump();
    await tester.tap(find.text('تسجيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final log = (await repo.recent()).single;
    expect((log.before, log.after), (5, 3));
    expect(find.text('أحسنت، لقد تجاوزتها'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('a failed save still opens the help and tells the patient', (
    tester,
  ) async {
    await _pump(tester, repo: _Failing());
    await _start(tester);
    expect(find.text('شهيق'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    await _leave(tester);
  });
}
