import 'package:benmahdia_mobile/features/intro/intro_screen.dart';
import 'package:benmahdia_mobile/widgets/page_dots.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _ar1 = 'كل يوم يُحسب';
const _ar2 = 'لست وحدك، في أي ساعة';
const _ar3 = 'طبيبك معك بين المواعيد';

Future<void> _settle(WidgetTester tester) =>
    pumpFor(tester, const Duration(seconds: 2));

int _dot(WidgetTester tester) =>
    tester.widget<PageDots>(find.byType(PageDots)).index;

void main() {
  testWidgets('opens on the first slide, in Arabic and RTL', (tester) async {
    await pumpApp(tester, IntroScreen(onDone: () {}));
    await _settle(tester);
    expect(find.text(_ar1), findsOneWidget);
    expect(directionOf(tester, IntroScreen), TextDirection.rtl);
    expect(_dot(tester), 0);
  });

  testWidgets('Next walks the slides; the dot and button follow', (
    tester,
  ) async {
    var done = 0;
    await pumpApp(tester, IntroScreen(onDone: () => done++));
    await _settle(tester);

    await tester.tap(find.text('التالي'));
    await _settle(tester);
    expect(find.text(_ar2), findsOneWidget);
    expect(_dot(tester), 1);

    await tester.tap(find.text('التالي'));
    await _settle(tester);
    expect(find.text(_ar3), findsOneWidget);
    expect(_dot(tester), 2);
    expect(find.text('ابدأ الآن'), findsOneWidget);

    await tester.tap(find.text('ابدأ الآن'));
    expect(done, 1);
  });

  testWidgets('Skip finishes the intro', (tester) async {
    var done = 0;
    await pumpApp(tester, IntroScreen(onDone: () => done++));
    await _settle(tester);
    await tester.tap(find.text('تخطي'));
    expect(done, 1);
  });

  testWidgets('swiping changes the slide', (tester) async {
    await pumpApp(tester, IntroScreen(onDone: () {}));
    await _settle(tester);
    // In RTL the next slide comes from the left, so swipe to the right.
    await tester.fling(find.text(_ar1), const Offset(300, 0), 1000);
    await _settle(tester);
    expect(find.text(_ar2), findsOneWidget);
  });

  testWidgets('French copy and LTR', (tester) async {
    await pumpApp(tester, IntroScreen(onDone: () {}));
    await useFrench(tester);
    await _settle(tester);
    expect(find.text('Chaque jour compte'), findsOneWidget);
    expect(find.text('Suivant'), findsOneWidget);
    expect(directionOf(tester, IntroScreen), TextDirection.ltr);
  });

  testWidgets('reduced motion: jumps between slides and settles', (
    tester,
  ) async {
    await pumpApp(tester, IntroScreen(onDone: () {}), reduceMotion: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    expect(find.text(_ar2), findsOneWidget);
  });
}
