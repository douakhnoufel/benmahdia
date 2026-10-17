import 'dart:async';

import 'package:benmahdia_mobile/features/verification/demo_signals.dart';
import 'package:benmahdia_mobile/features/verification/id_capture_screen.dart';
import 'package:benmahdia_mobile/features/verification/review_screen.dart';
import 'package:benmahdia_mobile/features/verification/selfie_screen.dart';
import 'package:benmahdia_mobile/features/verification/verification_flow.dart';
import 'package:benmahdia_mobile/features/verification/verification_models.dart';
import 'package:benmahdia_mobile/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _second = Duration(seconds: 1);

void main() {
  group('SelfieScreen', () {
    testWidgets('steps advance one by one, then capture is reported once', (
      tester,
    ) async {
      final steps = StreamController<LivenessStep>();
      addTearDown(steps.close);
      var captured = 0;
      await pumpApp(
        tester,
        SelfieScreen(steps: steps.stream, onCaptured: () => captured++),
      );
      await tester.pump();
      // Instruction pill + chip.
      expect(find.text('انظر إلى الكاميرا'), findsNWidgets(2));

      steps.add(LivenessStep.lookAtCamera);
      await tester.pump();
      await pumpFor(tester, _second);
      expect(find.text('أدر رأسك ببطء'), findsNWidgets(2));

      steps
        ..add(LivenessStep.turnHead)
        ..add(LivenessStep.blink);
      await tester.pump();
      await pumpFor(tester, _second ~/ 2);
      expect(find.text('تم التقاط الصورة'), findsOneWidget);
      expect(find.text('متابعة'), findsOneWidget);
      expect(captured, 0);

      await pumpFor(tester, AppMotion.slow * 2);
      expect(captured, 1);
    });

    testWidgets('Continue moves on at once and only once', (tester) async {
      final steps = StreamController<LivenessStep>();
      addTearDown(steps.close);
      var captured = 0;
      await pumpApp(
        tester,
        SelfieScreen(steps: steps.stream, onCaptured: () => captured++),
      );
      LivenessStep.values.forEach(steps.add);
      await tester.pump();
      await pumpFor(tester, _second ~/ 2);
      await tester.tap(find.text('متابعة'));
      await pumpFor(tester, AppMotion.slow * 3);
      expect(captured, 1);
    });

    testWidgets('pulse is off under reduced motion', (tester) async {
      await pumpApp(
        tester,
        SelfieScreen(
          steps: const Stream<LivenessStep>.empty(),
          onCaptured: () {},
        ),
        reduceMotion: true,
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('IdCaptureScreen', () {
    testWidgets('shutter wakes when a card is found, then flips to the back', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final found = <Completer<void>>[];
      Future<void> detect() {
        final c = Completer<void>();
        found.add(c);
        return c.future;
      }

      var done = 0;
      await pumpApp(
        tester,
        IdCaptureScreen(cardDetected: detect, onDone: () => done++),
      );
      await tester.pump();
      expect(find.text('نبحث عن البطاقة…'), findsOneWidget);

      // Inert until a card is detected.
      await tester.tap(find.bySemanticsLabel('التقاط الوجه الأمامي'));
      await tester.pump();
      expect(find.text('ضع الوجه الأمامي داخل الإطار'), findsOneWidget);

      found.single.complete();
      await tester.pump();
      await pumpFor(tester, _second);
      expect(find.text('تم رصد البطاقة، ثبّت الهاتف'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('التقاط الوجه الأمامي'));
      await tester.pump();
      await pumpFor(tester, _second);
      expect(
        find.text('اقلب البطاقة وضع الوجه الخلفي داخل الإطار'),
        findsOneWidget,
      );
      expect(find.text('نبحث عن البطاقة…'), findsOneWidget);
      expect(found, hasLength(2));
      expect(done, 0);

      found.last.complete();
      await tester.pump();
      await pumpFor(tester, _second);
      await tester.tap(find.bySemanticsLabel('التقاط الوجه الخلفي'));
      await tester.pump();
      expect(done, 1);
      semantics.dispose();
    });
  });

  group('ReviewScreen', () {
    testWidgets('submitting switches to the pending state', (tester) async {
      await pumpApp(
        tester,
        ReviewScreen(quality: demoIdQuality, onRetake: () {}),
      );
      await pumpFor(tester, _second);
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(5));
      expect(find.text('إعادة تصوير البطاقة'), findsNothing);

      await tester.tap(find.text('إرسال الملف'));
      await tester.pump();
      await pumpFor(tester, _second);
      expect(find.text('تم إرسال ملفك'), findsOneWidget);
      expect(find.text('قيد المراجعة'), findsOneWidget);
    });

    testWidgets('a failed check blocks submit and offers a retake', (
      tester,
    ) async {
      var retakes = 0;
      await pumpApp(
        tester,
        ReviewScreen(
          quality: const IdQuality(
            sharp: false,
            noGlare: true,
            wholeCard: true,
          ),
          onRetake: () => retakes++,
        ),
        reduceMotion: true,
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('إعادة تصوير البطاقة'));
      expect(retakes, 1);
    });
  });

  testWidgets('flow: selfie leads to the ID card', (tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => openVerification(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await pumpFor(tester, _second);
    expect(find.byType(SelfieScreen), findsOneWidget);

    // Demo liveness: three steps, two seconds apart, then a short pause.
    await pumpFor(tester, const Duration(seconds: 7));
    await pumpFor(tester, _second);
    expect(find.byType(IdCaptureScreen), findsOneWidget);

    // Let the demo card detector finish.
    await pumpFor(tester, const Duration(seconds: 3));
  });
}
