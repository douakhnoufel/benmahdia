import 'dart:async';

import 'package:benmahdia_mobile/features/splash/splash_screen.dart';
import 'package:benmahdia_mobile/features/start/app_start.dart';
import 'package:benmahdia_mobile/theme/app_tokens.dart';
import 'package:benmahdia_mobile/widgets/breathing_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('splash waits for startup work', (tester) async {
    final ready = Completer<void>();
    var done = 0;
    await pumpApp(
      tester,
      SplashScreen(ready: ready.future, onDone: () => done++),
    );
    await tester.pump(AppMotion.splashMinimum * 2);
    expect(done, 0);

    ready.complete();
    await tester.pump();
    expect(done, 1);
  });

  testWidgets('splash stays at least the minimum time', (tester) async {
    var done = 0;
    await pumpApp(
      tester,
      SplashScreen(ready: Future<void>.value(), onDone: () => done++),
    );
    await tester.pump(AppMotion.splashMinimum - AppMotion.fast);
    expect(done, 0);
    await tester.pump(AppMotion.fast * 2);
    expect(done, 1);
  });

  testWidgets('splash shows the name and both lines', (tester) async {
    await pumpApp(
      tester,
      SplashScreen(ready: Completer<void>().future, onDone: () {}),
    );
    await tester.pump();
    expect(find.text('بن مهدية'), findsOneWidget);
    expect(find.text('خطوة بخطوة نحو التعافي'), findsOneWidget);
    expect(find.text('من أجل جودة الحياة'), findsOneWidget);
    await tester.pump(AppMotion.splashMinimum);
  });

  testWidgets('logo breathes, and stays still under reduced motion', (
    tester,
  ) async {
    const logo = Scaffold(body: Center(child: BreathingLogo()));
    await pumpApp(tester, logo);
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);

    await pumpApp(tester, logo, reduceMotion: true);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('app start: splash, then intro, then welcome', (tester) async {
    await pumpApp(tester, AppStart(ready: Future<void>.value()));
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);

    await pumpFor(tester, AppMotion.splashMinimum + AppMotion.slow * 2);
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('كل يوم يُحسب'), findsOneWidget);

    await tester.tap(find.text('تخطي'));
    await pumpFor(tester, AppMotion.slow * 2);
    expect(find.text('كل يوم جديد خطوة نحو التعافي'), findsOneWidget);
  });
}
