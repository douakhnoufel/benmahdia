import 'package:benmahdia_mobile/features/craving/craving_models.dart';
import 'package:benmahdia_mobile/features/craving/craving_repository.dart';
import 'package:benmahdia_mobile/features/craving/difficult_moment_screen.dart';
import 'package:benmahdia_mobile/features/craving/fake_craving_repository.dart';
import 'package:benmahdia_mobile/features/recovery/fake_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// The "difficult moment" screen (habit-tracking design, step 1): intensity
// 1-10, HALT triggers, breathing, a tip to try, the patient's if-then plan,
// reaching the clinic, then "the craving passed" with before and after.

// A Saturday: the sample clinic opens 07:30-14:30 every day but Friday.
final _openHours = DateTime(2026, 10, 17, 10, 0);
final _closedHours = DateTime(2026, 10, 17, 17, 10);

/// The sample clinic answers after 200 ms; waiting for it is explicit so the
/// test never ends on a pending timer.
const _clinicWait = Duration(milliseconds: 250);

/// A snackbar holds a 4 s timer; this clears it before the test ends.
const _snackBarLife = Duration(seconds: 5);

Future<FakeCravingRepository> _pump(
  WidgetTester tester, {
  bool failing = false,
  bool reduceMotion = true,
  DateTime? now,
}) async {
  final at = now ?? _openHours;
  final cravings = FakeCravingRepository(clock: () => at, failing: failing);
  await pumpApp(
    tester,
    const DifficultMomentScreen(),
    reduceMotion: reduceMotion,
    overrides: [
      cravingRepositoryProvider.overrideWithValue(cravings),
      recoveryRepositoryProvider.overrideWithValue(
        FakeRecoveryRepository(clock: () => at),
      ),
    ],
  );
  await tester.pumpAndSettle();
  return cravings;
}

Finder get _list => find.descendant(
  of: find.byType(DifficultMomentScreen),
  matching: find.byType(Scrollable),
);

Finder _intensity(int value) => find.byKey(ValueKey('intensity-$value'));

/// Brings [finder] on screen, scrolling the page when it is not built yet.
Future<void> _show(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 150, scrollable: _list);
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _show(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Logs a craving of [intensity] and waits for the breathing step, clinic
/// line included.
Future<void> _startAt(WidgetTester tester, int intensity) async {
  await _tap(tester, _intensity(intensity));
  await _tap(tester, find.text('لنتنفّس معاً'));
  await tester.pump(_clinicWait);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('logs the craving, then records that it passed', (tester) async {
    final cravings = await _pump(tester);

    // Nothing is saved before the patient says how strong the craving is.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );
    expect(find.text('اختر قوة الرغبة لنبدأ'), findsOne);

    await _tap(tester, _intensity(7));
    await _tap(tester, find.byKey(const ValueKey('trigger-tired')));
    await _tap(tester, find.text('لنتنفّس معاً'));
    await tester.pump(_clinicWait);
    await tester.pumpAndSettle();

    expect(cravings.logs, hasLength(1));
    expect(cravings.logs.single.intensityBefore, 7);
    expect(cravings.logs.single.triggers, [CravingTrigger.tired]);
    expect(find.text('جرّب الآن'), findsOne);

    await _tap(tester, find.text('مرّت الرغبة'));
    await _tap(tester, _intensity(3));
    await _tap(tester, find.text('احفظ'));

    expect(find.text('لقد تجاوزت هذه اللحظة'), findsOne);
    expect(find.text('7'), findsOne);
    expect(find.text('3'), findsOne);
    expect(cravings.logs.single.intensityAfter, 3);
    expect(cravings.logs.single.passed, isTrue);
  });

  testWidgets('the craving that stays strong is still a moment traversed', (
    tester,
  ) async {
    await _pump(tester);
    await _startAt(tester, 6);
    await _tap(tester, find.text('مرّت الرغبة'));
    await _tap(tester, _intensity(6));
    await _tap(tester, find.text('احفظ'));

    expect(
      find.text('ما زالت قوية، ومع ذلك لم تستسلم. هذا يُحسب لك.'),
      findsOne,
    );
  });

  testWidgets('a save that fails keeps the patient on the screen', (
    tester,
  ) async {
    final cravings = await _pump(tester, failing: true);
    await _tap(tester, _intensity(5));
    await _tap(tester, find.text('لنتنفّس معاً'));

    expect(cravings.logs, isEmpty);
    // Still on the first step, with a message and the button usable again.
    expect(find.text('لنتنفّس معاً'), findsOne);
    expect(find.text('تعذّر الحفظ. تحقّق من الاتصال وحاول مجدداً.'), findsOne);
    await tester.pumpAndSettle(_snackBarLife);
  });

  testWidgets('the tip rotates through the four suggestions', (tester) async {
    await _pump(tester);
    await _startAt(tester, 8);

    await _show(tester, find.text('اقتراح آخر'));
    expect(find.textContaining('الهريسة'), findsOne);
    await _tap(tester, find.text('اقتراح آخر'));
    expect(find.textContaining('النعناع'), findsOne);
    await _tap(tester, find.text('اقتراح آخر'));
    expect(find.textContaining('كأس ماء'), findsOne);
    await _tap(tester, find.text('اقتراح آخر'));
    expect(find.textContaining('امشِ'), findsOne);
    // Back to the first one.
    await _tap(tester, find.text('اقتراح آخر'));
    expect(find.textContaining('الهريسة'), findsOne);
  });

  testWidgets('says whether the clinic is open right now', (tester) async {
    await _pump(tester);
    await _startAt(tester, 4);
    await _show(tester, find.text('اتصل بالعيادة'));
    expect(find.text('العيادة مفتوحة الآن'), findsOne);
  });

  testWidgets('says the clinic is closed outside its hours', (tester) async {
    await _pump(tester, now: _closedHours);
    await _startAt(tester, 4);
    await _show(tester, find.text('اتصل بالعيادة'));
    expect(find.text('العيادة مغلقة الآن'), findsOne);
  });

  testWidgets('the if-then plan is the patient\'s own and stays private', (
    tester,
  ) async {
    await _pump(tester);
    await _startAt(tester, 5);

    await _show(tester, find.text('خطتي'));
    expect(find.text('أنت فقط ترى هذا'), findsOne);
    await _tap(tester, find.text('اكتب خطتي'));
    await tester.enterText(
      find.byType(TextField).first,
      'أشعر بالتعب في المساء',
    );
    await tester.enterText(find.byType(TextField).last, 'أشرب كأس ماء');
    await _tap(tester, find.text('احفظ الخطة'));
    // The plan goes to the phone's storage first, so the confirmation
    // arrives a frame later.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('حُفظت الخطة على هاتفك'), findsOne);
    await _show(tester, find.text('خطتي'));
    expect(
      find.text('عندما أشعر بالتعب في المساء، سوف أشرب كأس ماء.'),
      findsOne,
    );
    await tester.pumpAndSettle(_snackBarLife);
  });

  testWidgets('the screen says the doctor sees the craving log', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('طبيبك يرى هذا'), findsOne);
  });

  testWidgets('urgent help is reachable at every step', (tester) async {
    await _pump(tester);
    expect(find.text('مساعدة عاجلة'), findsOne);
    await _startAt(tester, 9);
    expect(find.text('مساعدة عاجلة'), findsOne);

    await _tap(tester, find.text('مساعدة عاجلة'));
    await tester.pump(_clinicWait);
    await tester.pumpAndSettle();
    expect(find.text('أنت لست وحدك'), findsOne);
  });

  testWidgets('Arabic is right to left, French left to right', (tester) async {
    await _pump(tester);
    expect(directionOf(tester, DifficultMomentScreen), TextDirection.rtl);
    expect(find.text('لحظة صعبة'), findsOne);

    await useFrench(tester);
    await tester.pumpAndSettle();
    expect(directionOf(tester, DifficultMomentScreen), TextDirection.ltr);
    expect(find.text('Un moment difficile'), findsOne);
    expect(find.text('Respirons ensemble'), findsOne);
  });

  testWidgets('the breathing circle runs, and is still under reduced motion', (
    tester,
  ) async {
    // Motion allowed: the circle walks through inhale, hold and exhale.
    await _pump(tester, reduceMotion: false);
    await _tap(tester, _intensity(6));
    await tester.tap(find.text('لنتنفّس معاً'));
    await tester.pump();
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('شهيق'), findsOne);
    await pumpFor(tester, const Duration(seconds: 5));
    expect(find.text('احبس'), findsOne);
    await pumpFor(tester, const Duration(seconds: 5));
    expect(find.text('زفير'), findsOne);
  });

  testWidgets('reduced motion shows one calm instruction, no countdown', (
    tester,
  ) async {
    await _pump(tester);
    await _startAt(tester, 6);
    expect(find.text('تنفّس ببطء'), findsOne);
    expect(find.text('شهيق'), findsNothing);
  });
}
