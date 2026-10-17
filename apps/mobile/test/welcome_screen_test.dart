import 'package:benmahdia_mobile/core/locale_provider.dart';
import 'package:benmahdia_mobile/features/welcome/welcome_screen.dart';
import 'package:benmahdia_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _arTitle = 'كل يوم جديد خطوة نحو التعافي';
const _frTitle = 'Chaque nouveau jour est un pas vers le rétablissement';

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onCreate,
  VoidCallback? onLogin,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: BenMahdiaApp(
        home: WelcomeScreen(
          onCreateAccount: onCreate ?? () {},
          onLogin: onLogin ?? () {},
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

TextDirection _direction(WidgetTester tester) =>
    Directionality.of(tester.element(find.byType(WelcomeScreen)));

void main() {
  testWidgets('defaults to Arabic and RTL', (tester) async {
    await _pump(tester);
    expect(find.text(_arTitle), findsOneWidget);
    expect(_direction(tester), TextDirection.rtl);
  });

  testWidgets('quality of life is mentioned in both languages', (tester) async {
    await _pump(tester);
    expect(find.textContaining('جودة حياتك'), findsOneWidget);
    await tester.tap(find.text('Français'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('qualité de vie'), findsOneWidget);
  });

  testWidgets('French toggle switches copy and flips to LTR', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Français'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_frTitle), findsOneWidget);
    expect(_direction(tester), TextDirection.ltr);

    await tester.tap(find.text('العربية'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_arTitle), findsOneWidget);
    expect(_direction(tester), TextDirection.rtl);
  });

  testWidgets('locale provider tracks the toggle', (tester) async {
    await _pump(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WelcomeScreen)),
    );
    expect(container.read(localeProvider), const Locale('ar'));
    await tester.tap(find.text('Français'));
    await tester.pump();
    expect(container.read(localeProvider), const Locale('fr'));
  });

  testWidgets('both buttons fire their callbacks', (tester) async {
    var created = 0;
    var logins = 0;
    await _pump(tester, onCreate: () => created++, onLogin: () => logins++);

    await tester.tap(find.text('إنشاء حساب'));
    await tester.tap(find.text('لدي حساب — تسجيل الدخول'));
    expect(created, 1);
    expect(logins, 1);
  });

  testWidgets('reduced motion renders the final state and settles', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.text(_arTitle), findsOneWidget);
  });
}
