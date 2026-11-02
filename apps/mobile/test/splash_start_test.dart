import 'dart:async';

import 'package:benmahdia_mobile/features/splash/life_quality_splash_screen.dart';
import 'package:benmahdia_mobile/features/start/app_start.dart';
import 'package:benmahdia_mobile/theme/app_tokens.dart';
import 'package:benmahdia_mobile/widgets/breathing_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _fourSeconds = Duration(seconds: 4);

void main() {
  testWidgets('splash waits for startup work', (tester) async {
    final ready = Completer<void>();
    var done = 0;
    await pumpApp(
      tester,
      LifeQualitySplashScreen(ready: ready.future, onFinish: () => done++),
    );
    await tester.pump(_fourSeconds * 2);
    expect(done, 0);

    ready.complete();
    await tester.pump();
    expect(done, 1);
  });

  testWidgets('splash stays for its duration, 4 s by default', (tester) async {
    var done = 0;
    await pumpApp(
      tester,
      LifeQualitySplashScreen(
        ready: Future<void>.value(),
        onFinish: () => done++,
      ),
    );
    await tester.pump(_fourSeconds - AppMotion.fast);
    expect(done, 0);
    await tester.pump(AppMotion.fast * 2);
    expect(done, 1);
  });

  testWidgets('splash duration is kept between 3 and 5 s', (tester) async {
    var done = 0;
    await pumpApp(
      tester,
      LifeQualitySplashScreen(
        splashDuration: const Duration(seconds: 1),
        onFinish: () => done++,
      ),
    );
    await tester.pump(const Duration(milliseconds: 2900));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(done, 1);
  });

  testWidgets('splash shows the logo and LIFE QUALITY, still '
      'under reduced motion', (tester) async {
    for (final reduce in [false, true]) {
      await pumpApp(
        tester,
        LifeQualitySplashScreen(
          ready: Completer<void>().future,
          onFinish: () {},
        ),
        reduceMotion: reduce,
      );
      await tester.pump();
      expect(
        find.image(const AssetImage('assets/brand/logo.png')),
        findsOneWidget,
      );
      expect(find.text('LIFE QUALITY'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (reduce) {
        await tester.pump(AppMotion.fast);
        expect(tester.hasRunningAnimations, isFalse);
      }
      await tester.pump(_fourSeconds);
    }
  });

  testWidgets('without a callback, the splash fades to the next screen', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const LifeQualitySplashScreen(nextScreen: Scaffold(body: Text('next'))),
    );
    await pumpFor(tester, _fourSeconds + AppMotion.slow * 2);
    expect(find.byType(LifeQualitySplashScreen), findsNothing);
    expect(find.text('next'), findsOneWidget);
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
    expect(find.byType(LifeQualitySplashScreen), findsOneWidget);

    await pumpFor(tester, _fourSeconds + AppMotion.slow * 2);
    expect(find.byType(LifeQualitySplashScreen), findsNothing);
    expect(find.text('كل يوم يُحسب'), findsOneWidget);

    await tester.tap(find.text('تخطي'));
    await pumpFor(tester, AppMotion.slow * 2);
    expect(find.text('كل يوم جديد خطوة نحو التعافي'), findsOneWidget);
  });
}
