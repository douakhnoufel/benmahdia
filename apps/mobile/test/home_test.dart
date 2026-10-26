import 'package:benmahdia_mobile/features/booking/fake_booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/my_appointments_screen.dart';
import 'package:benmahdia_mobile/features/booking/payment_launcher.dart';
import 'package:benmahdia_mobile/features/companion/companion_repository.dart';
import 'package:benmahdia_mobile/features/companion/fake_companion_repository.dart';
import 'package:benmahdia_mobile/features/home/home_shell.dart';
import 'package:benmahdia_mobile/features/recovery/addiction_form_screen.dart';
import 'package:benmahdia_mobile/features/recovery/daily_check_screen.dart';
import 'package:benmahdia_mobile/features/recovery/fake_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_models.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// Saturday 17 October 2026, 17:10: the clinic is open on Saturdays.
final _now = DateTime(2026, 10, 17, 17, 10);

class _Setup {
  _Setup()
    : recovery = FakeRecoveryRepository(clock: () => _now),
      booking = FakeBookingRepository(clock: () => _now);

  final FakeRecoveryRepository recovery;
  final FakeBookingRepository booking;
  final opened = <Uri>[];

  List<Override> get overrides => [
    recoveryRepositoryProvider.overrideWithValue(recovery),
    bookingRepositoryProvider.overrideWithValue(booking),
    companionRepositoryProvider.overrideWithValue(
      FakeCompanionRepository(delay: const Duration(milliseconds: 300)),
    ),
    openUrlProvider.overrideWithValue((url) async {
      opened.add(url);
      return true;
    }),
  ];
}

Future<_Setup> _pumpShell(WidgetTester tester) async {
  final setup = _Setup();
  await pumpApp(tester, const HomeShell(), overrides: setup.overrides);
  await tester.pumpAndSettle();
  return setup;
}

/// Scrolls the recovery list until [finder] is built and visible.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(
      of: find.byType(RecoveryScreen),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('milestones', () {
    test('the next milestone follows PRD 5.1, then every year', () {
      expect(nextMilestone(0), 1);
      expect(nextMilestone(1), 3);
      expect(nextMilestone(9), 14);
      expect(nextMilestone(14), 30);
      expect(nextMilestone(364), 365);
      expect(nextMilestone(365), 730);
    });

    test('a relapse keeps the longest streak and the total', () {
      final a = Addiction(
        id: 'a',
        type: AddictionType.alcohol,
        start: DateTime(2026, 9, 1),
        longestPastDays: 10,
        pastDays: 30,
      );
      final after = a.relapsed(DateTime(2026, 10, 1));
      expect(after.days(DateTime(2026, 10, 1)), 0);
      expect(after.longestPastDays, 30);
      expect(after.pastDays, 60);
      expect(after.type, AddictionType.alcohol);
    });
  });

  group('home shell', () {
    testWidgets('opens on recovery with three tabs, in Arabic RTL', (
      tester,
    ) async {
      await _pumpShell(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('مواعيدي'), findsWidgets);
      expect(find.text('المرافق'), findsWidgets);
      expect(find.text('البريغابالين'), findsOneWidget);
      expect(find.textContaining('دون تعاطٍ منذ'), findsOneWidget);
      expect(directionOf(tester, RecoveryScreen), TextDirection.rtl);
    });

    testWidgets('the appointments tab has no back button', (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(MyAppointmentsScreen), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('French labels, left to right', (tester) async {
      await _pumpShell(tester);
      await useFrench(tester);
      await tester.pumpAndSettle();
      expect(find.text('Mon parcours'), findsWidgets);
      expect(find.text('Rendez-vous'), findsOneWidget);
      expect(find.text('Compagnon'), findsOneWidget);
      expect(directionOf(tester, RecoveryScreen), TextDirection.ltr);
    });
  });

  group('recovery', () {
    testWidgets('the daily check per substance fills the week', (tester) async {
      final setup = await _pumpShell(tester);
      await _scrollTo(tester, find.text('سجّل يومك'));
      expect(find.text('6 من 7'), findsOneWidget);
      await tester.tap(find.text('سجّل يومك'));
      await tester.pumpAndSettle();
      expect(find.byType(DailyCheckScreen), findsOneWidget);
      expect(find.text('اليوم دون البريغابالين؟'), findsOneWidget);

      final save = find.widgetWithText(FilledButton, 'حفظ');
      await tester.tap(find.text('نعم'));
      await tester.tap(
        find.byKey(const ValueKey('rating-الرغبة في التعاطي-2')),
      );
      await tester.tap(find.byKey(const ValueKey('rating-القلق-3')));
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('rating-صعوبة النوم-1')));
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.byType(DailyCheckScreen), findsNothing);
      final today = setup.recovery.checks.last;
      expect((today.used, today.craving), (false, 2));
      expect(today.signals, {'anxiety': 3, 'sleep': 1});
      expect(find.text('سُجّل يومك. أحسنت.'), findsWidgets);
      expect(find.text('7 من 7'), findsOneWidget);
    });

    testWidgets('the daily reminder can be stopped', (tester) async {
      await _pumpShell(tester);
      await _scrollTo(tester, find.text('التذكير اليومي'));
      expect(find.widgetWithText(TextButton, '21:00'), findsOneWidget);
      await tester.tap(find.byTooltip('إيقاف التذكير'));
      await tester.pumpAndSettle();
      expect(find.text('متوقف'), findsOneWidget);
      await tester.tap(find.text('متوقف'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
    });

    testWidgets('marking a dose as taken', (tester) async {
      await _pumpShell(tester);
      await _scrollTo(tester, find.text('أخذته'));
      expect(find.text('1 من 2'), findsOneWidget);
      await tester.tap(find.text('أخذته'));
      await tester.pumpAndSettle();
      expect(find.text('2 من 2'), findsOneWidget);
      expect(find.text('أخذته'), findsNothing);
    });

    testWidgets('a relapse restarts the counter but keeps the past', (
      tester,
    ) async {
      final setup = await _pumpShell(tester);
      expect(find.text('21 يوماً'), findsOneWidget); // longest
      expect(find.text('64 يوماً'), findsOneWidget); // total

      await _scrollTo(tester, find.text('مررت بانتكاسة'));
      await tester.tap(find.text('مررت بانتكاسة'));
      await tester.pumpAndSettle();
      expect(find.text('لا بأس، هذا جزء من الطريق'), findsOneWidget);
      await tester.tap(find.text('أمس'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أعد بدء العدّاد'));
      await tester.pumpAndSettle();

      expect(setup.recovery.relapses, hasLength(1));
      expect(setup.recovery.relapses.single.at.day, 16);
      expect(find.text('بداية جديدة. أيامك السابقة محفوظة.'), findsOneWidget);
      expect(find.text('21 يوماً'), findsOneWidget);
    });

    testWidgets('the patient adds an addiction, pending review', (
      tester,
    ) async {
      await _pumpShell(tester);
      await _scrollTo(tester, find.text('أضف إدماناً آخر'));
      await tester.tap(find.text('أضف إدماناً آخر'));
      await tester.pumpAndSettle();
      expect(find.byType(AddictionFormScreen), findsOneWidget);

      final save = find.widgetWithText(FilledButton, 'حفظ');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(find.text('مادة أخرى'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('القمار'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('القمار'));
      await tester.dragUntilVisible(
        find.byType(TextField),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.enterText(find.byType(TextField), 'ألعاب الرهان');
      await tester.pump();
      await tester.dragUntilVisible(
        save,
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.byType(AddictionFormScreen), findsNothing);
      expect(find.text('حُفظ. سيراجعه طبيبك.'), findsOneWidget);
      await _scrollTo(tester, find.text('ألعاب الرهان'));
      expect(find.text('في انتظار مراجعة الطبيب'), findsOneWidget);
    });

    testWidgets('the clinic card calls and opens Maps', (tester) async {
      final setup = await _pumpShell(tester);
      await _scrollTo(tester, find.text('افتح في خرائط Google'));
      expect(find.text('مفتوحة اليوم'), findsOneWidget);
      await tester.tap(find.text('افتح في خرائط Google'));
      await tester.tap(find.text('+213 551 03 83 85'));
      await tester.pump();
      expect(setup.opened, [
        Uri.parse('https://share.google/gizHNbNpfRqdHfYmQ'),
        Uri(scheme: 'tel', path: '+213551038385'),
      ]);
    });

    testWidgets('the next appointment opens the appointments tab', (
      tester,
    ) async {
      await _pumpShell(tester);
      await _scrollTo(tester, find.text('موعدك القادم'));
      await tester.tap(find.text('موعدك القادم'));
      await tester.pumpAndSettle();
      expect(find.byType(MyAppointmentsScreen), findsOneWidget);
    });
  });

  group('companion', () {
    Future<void> openChat(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded).last);
      await tester.pumpAndSettle();
      expect(find.text('قبل أن نبدأ'), findsOneWidget);
      await tester.tap(find.text('فهمت، لنبدأ'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks consent first, then greets', (tester) async {
      await _pumpShell(tester);
      await openChat(tester);
      expect(
        find.text('مرحباً، أنا المرافق. أنا هنا لأستمع إليك. كيف تشعر الآن؟'),
        findsOneWidget,
      );
      expect(
        find.text('لا يقدّم المرافق تشخيصاً ولا يغيّر دواءك.'),
        findsOneWidget,
      );
    });

    testWidgets('"talk to the doctor" offers booking', (tester) async {
      await _pumpShell(tester);
      await openChat(tester);
      await tester.ensureVisible(find.text('أريد التحدّث مع الطبيب'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أريد التحدّث مع الطبيب'));
      await tester.pump();
      expect(find.text('المرافق يكتب…'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.text('احجز موعداً'));
      await tester.pumpAndSettle();
      expect(find.byType(MyAppointmentsScreen), findsOneWidget);
    });

    testWidgets('a crisis message opens urgent help', (tester) async {
      final setup = await _pumpShell(tester);
      await openChat(tester);
      await tester.enterText(find.byType(TextField), 'أفكر في الانتحار');
      await tester.tap(find.byTooltip('إرسال'));
      await tester.pumpAndSettle();
      expect(find.text('أنت لست وحدك'), findsOneWidget);
      await tester.tap(find.text('اتصل بالعيادة'));
      await tester.pump();
      expect(setup.opened, [Uri(scheme: 'tel', path: '+213551038385')]);
    });
  });
}
