import 'package:benmahdia_mobile/theme/app_tokens.dart';
import 'package:benmahdia_mobile/widgets/sobriety_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Widget _ring({int days = 42, int goal = 60}) => Scaffold(
  body: Center(
    child: SobrietyRing(
      days: days,
      goal: goal,
      label: 'days',
      semanticLabel: '$days of $goal',
    ),
  ),
);

double _badgeScale(WidgetTester tester) => tester
    .widget<AnimatedScale>(
      find.ancestor(
        of: find.byIcon(Icons.star_rounded),
        matching: find.byType(AnimatedScale),
      ),
    )
    .scale;

void main() {
  testWidgets('counts up from 0 to the day total', (tester) async {
    await pumpApp(tester, _ring());
    expect(find.text('0'), findsOneWidget);

    await tester.pump(AppMotion.ringFill ~/ 2);
    expect(find.text('42'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('reads as one label for screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, _ring());
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('42 of 60'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('milestone badge pops in only once the goal is reached', (
    tester,
  ) async {
    await pumpApp(tester, _ring());
    await tester.pumpAndSettle();
    expect(_badgeScale(tester), 0);

    await pumpApp(tester, _ring(days: 60));
    await tester.pumpAndSettle();
    expect(_badgeScale(tester), 1);
  });

  testWidgets('reduced motion shows the final number at once', (tester) async {
    await pumpApp(tester, _ring(), reduceMotion: true);
    await tester.pump();
    expect(find.text('42'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
