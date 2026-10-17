import 'package:benmahdia_mobile/core/locale_provider.dart';
import 'package:benmahdia_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [home] inside the real app shell on a 390×844 phone.
Future<void> pumpApp(
  WidgetTester tester,
  Widget home, {
  bool reduceMotion = false,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: BenMahdiaApp(home: home),
    ),
  );
}

/// Switches the running app to French.
Future<void> useFrench(WidgetTester tester) async {
  ProviderScope.containerOf(
    tester.element(find.byType(Navigator)),
  ).read(localeProvider.notifier).set(const Locale('fr'));
  await tester.pump();
}

/// Pumps frames every 50 ms for [duration], like a running app would.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < duration; t += step) {
    await tester.pump(step);
  }
}

TextDirection directionOf(WidgetTester tester, Type screen) =>
    Directionality.of(tester.element(find.byType(screen)));
