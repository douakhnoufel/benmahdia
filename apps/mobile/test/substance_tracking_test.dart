import 'package:benmahdia_mobile/features/booking/booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/fake_booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/my_appointments_screen.dart';
import 'package:benmahdia_mobile/features/companion/companion_repository.dart';
import 'package:benmahdia_mobile/features/companion/fake_companion_repository.dart';
import 'package:benmahdia_mobile/features/home/home_shell.dart';
import 'package:benmahdia_mobile/features/recovery/daily_check_screen.dart';
import 'package:benmahdia_mobile/features/recovery/fake_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_models.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// Per-substance tracking, small goals and good habits on the recovery home
// (PRD 5.6). The sample patient tracks pregabalin, clean for 9 days.

final _now = DateTime(2026, 10, 17, 17, 10);

Future<FakeRecoveryRepository> _pump(
  WidgetTester tester, {
  bool locked = false,
}) async {
  final recovery = FakeRecoveryRepository(clock: () => _now, locked: locked);
  await pumpApp(
    tester,
    const HomeShell(),
    overrides: [
      recoveryRepositoryProvider.overrideWithValue(recovery),
      bookingRepositoryProvider.overrideWithValue(
        FakeBookingRepository(clock: () => _now),
      ),
      companionRepositoryProvider.overrideWithValue(
        FakeCompanionRepository(delay: Duration.zero),
      ),
    ],
  );
  await tester.pumpAndSettle();
  return recovery;
}

Finder get _list => find.descendant(
  of: find.byType(RecoveryScreen),
  matching: find.byType(Scrollable),
);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: _list);
  await tester.pumpAndSettle();
}

Finder _rating(String label, int value) =>
    find.byKey(ValueKey('rating-$label-$value'));

Future<void> _openCheck(WidgetTester tester, String action) async {
  await _scrollTo(tester, find.text(action));
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('locked until the first paid visit, with a way to book', (
    tester,
  ) async {
    await _pump(tester, locked: true);
    expect(find.text('يُفتح بعد موعدك الأول'), findsOneWidget);
    expect(find.text('البريغابالين'), findsNothing);
    await tester.tap(find.text('احجز موعداً'));
    await tester.pumpAndSettle();
    expect(find.byType(MyAppointmentsScreen), findsOneWidget);
  });

  testWidgets('the counter shows the profile, its goal and early note', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('البريغابالين'), findsOneWidget);
    // Day 9: the next small step is 14 days; the day-7 note still shows.
    expect(find.textContaining('14'), findsWidgets);
    await _scrollTo(tester, find.text('أسبوع كامل. كل يوم يقوّي عزيمتك.'));
  });

  testWidgets('the patient picks a higher small goal', (tester) async {
    final recovery = await _pump(tester);
    await _scrollTo(tester, find.text('غيّر الهدف'));
    await tester.tap(find.text('غيّر الهدف'));
    await tester.pumpAndSettle();
    expect(find.text('هدفك الصغير التالي'), findsOneWidget);
    // Steps already reached (1, 3, 7) are not offered.
    expect(find.widgetWithText(ChoiceChip, '7 أيام'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '28 يوماً'));
    await tester.pumpAndSettle();
    expect(recovery.storedAddictions.single.goalDays, 28);
    expect(find.textContaining('28 يوماً'), findsWidgets);
  });

  testWidgets('"used" in the daily check opens relapse logging', (
    tester,
  ) async {
    final recovery = await _pump(tester);
    await _openCheck(tester, 'سجّل يومك');
    await tester.tap(find.text('لا'));
    await tester.tap(_rating('الرغبة في التعاطي', 5));
    await tester.tap(_rating('القلق', 4));
    await tester.tap(_rating('صعوبة النوم', 4));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();

    expect(recovery.checks.last.used, isTrue);
    expect(find.text('لا بأس، هذا جزء من الطريق'), findsOneWidget);
    await tester.tap(find.text('أعد بدء العدّاد'));
    await tester.pumpAndSettle();
    expect(recovery.relapses, hasLength(1));
  });

  testWidgets('the daily check ticks good habits too', (tester) async {
    final recovery = await _pump(tester);
    await _openCheck(tester, 'سجّل يومك');
    await tester.tap(find.text('نعم'));
    await tester.tap(_rating('الرغبة في التعاطي', 1));
    await tester.tap(_rating('القلق', 1));
    await tester.tap(_rating('صعوبة النوم', 1));
    await tester.dragUntilVisible(
      find.widgetWithText(CheckboxListTile, 'الرياضة أو المشي'),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'الرياضة أو المشي'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();
    final [sport] = recovery.storedHabits;
    expect(sport.days, contains(DateTime(2026, 10, 17)));
  });

  testWidgets('adding an addiction by substance profile', (tester) async {
    await _pump(tester);
    await _scrollTo(tester, find.text('أضف إدماناً آخر'));
    await tester.tap(find.text('أضف إدماناً آخر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('النيكوتين'));
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'حفظ');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('النيكوتين'));
  });

  testWidgets('good habits: tick, add from the list, remove', (tester) async {
    final recovery = await _pump(tester);
    await _scrollTo(tester, find.text('عاداتي الجيدة'));
    expect(find.text('الرياضة أو المشي'), findsOneWidget);
    expect(find.text('18:00'), findsOneWidget);

    final box = find.byType(Checkbox);
    expect(tester.widget<Checkbox>(box).value, isFalse);
    await tester.ensureVisible(box);
    await tester.pumpAndSettle();
    await tester.tap(box);
    // Nothing animates: let the sample data's delay pass.
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Checkbox>(box).value, isTrue);
    expect(recovery.storedHabits.single.days, contains(DateTime(2026, 10, 17)));

    await _scrollTo(tester, find.text('أضف عادة'));
    await tester.tap(find.text('أضف عادة'));
    await tester.pumpAndSettle();
    // The habit already kept is not offered again.
    expect(find.widgetWithText(ChoiceChip, 'الرياضة أو المشي'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'تنظيف الأسنان'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('تنظيف الأسنان'), findsOneWidget);

    final remove = find.byTooltip('إزالة الرياضة أو المشي');
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      [for (final h in recovery.storedHabits) h.kind],
      [HabitKind.brushTeeth],
    );
  });

  testWidgets('a habit in the patient\'s own words', (tester) async {
    final recovery = await _pump(tester);
    await _scrollTo(tester, find.text('أضف عادة'));
    await tester.tap(find.text('أضف عادة'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'بكلماتي'));
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'حفظ');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'البستنة');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final own = recovery.storedHabits.last;
    expect((own.kind, own.text), (HabitKind.custom, 'البستنة'));
  });

  testWidgets('the daily check in French, left to right', (tester) async {
    await _pump(tester);
    await useFrench(tester);
    await tester.pumpAndSettle();
    await _openCheck(tester, 'Faire le point du jour');
    expect(find.text('Aujourd\'hui sans Prégabaline ?'), findsOneWidget);
    expect(find.text('Envie de consommer'), findsOneWidget);
    expect(find.text('Anxiété'), findsOneWidget);
    expect(directionOf(tester, DailyCheckScreen), TextDirection.ltr);
  });

  testWidgets('the daily check is right to left in Arabic', (tester) async {
    await _pump(tester);
    await _openCheck(tester, 'سجّل يومك');
    expect(directionOf(tester, DailyCheckScreen), TextDirection.rtl);
    expect(find.text('أجب عن كل الأسئلة للحفظ.'), findsOneWidget);
  });
}
