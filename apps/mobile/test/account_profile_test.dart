import 'package:benmahdia_mobile/features/account/account_repository.dart';
import 'package:benmahdia_mobile/features/account/fake_account_repository.dart';
import 'package:benmahdia_mobile/features/auth/auth_models.dart';
import 'package:benmahdia_mobile/features/auth/auth_repository.dart';
import 'package:benmahdia_mobile/features/auth/fake_auth_repository.dart';
import 'package:benmahdia_mobile/features/booking/booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/fake_booking_repository.dart';
import 'package:benmahdia_mobile/features/companion/companion_repository.dart';
import 'package:benmahdia_mobile/features/companion/fake_companion_repository.dart';
import 'package:benmahdia_mobile/features/home/home_shell.dart';
import 'package:benmahdia_mobile/features/recovery/fake_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_repository.dart';
import 'package:benmahdia_mobile/features/welcome/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

final _now = DateTime(2026, 10, 17, 17, 10);

class _LogOutSpy extends FakeAuthRepository {
  var loggedOut = 0;

  @override
  Future<void> logOut(AuthSession session) async => loggedOut++;
}

Future<(FakeAccountRepository, _LogOutSpy)> _pumpProfile(
  WidgetTester tester,
) async {
  final account = FakeAccountRepository();
  final auth = _LogOutSpy();
  await pumpApp(
    tester,
    const HomeShell(),
    overrides: [
      accountRepositoryProvider.overrideWithValue(account),
      authRepositoryProvider.overrideWithValue(auth),
      recoveryRepositoryProvider.overrideWithValue(
        FakeRecoveryRepository(clock: () => _now),
      ),
      bookingRepositoryProvider.overrideWithValue(
        FakeBookingRepository(clock: () => _now),
      ),
      companionRepositoryProvider.overrideWithValue(FakeCompanionRepository()),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('حسابي'));
  await tester.pumpAndSettle();
  return (account, auth);
}

void main() {
  testWidgets('the bottom bar has four tabs, profile last', (tester) async {
    await _pumpProfile(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(4));
    expect(bar.selectedIndex, 3);
    expect(find.text('الحساب والإعدادات'), findsOneWidget);
  });

  testWidgets('shows the number left to right and no email yet', (
    tester,
  ) async {
    await _pumpProfile(tester);
    final phone = tester.widget<Text>(
      find.text(FakeAuthRepository.samplePhone.e164),
    );
    expect(phone.textDirection, TextDirection.ltr);
    expect(find.text('غير محدد'), findsOneWidget);
    expect(find.text('هوية مُصرَّح بها'), findsOneWidget);
  });

  testWidgets('sets the contact email, refusing a bad one', (tester) async {
    final (account, _) = await _pumpProfile(tester);
    await tester.tap(find.text('البريد الإلكتروني للتواصل'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('عنوان البريد الإلكتروني غير صالح.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Patient@Example.com');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('patient@example.com'), findsOneWidget);
    expect((await account.me()).email, 'patient@example.com');
  });

  testWidgets('switches the language to French', (tester) async {
    await _pumpProfile(tester);
    await tester.tap(find.text('اللغة'));
    await tester.pumpAndSettle();
    expect(find.text('Profil et réglages'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
  });

  testWidgets('signs out and returns to the welcome screen', (tester) async {
    final (_, auth) = await _pumpProfile(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeShell)),
    );
    container
        .read(sessionProvider.notifier)
        .set(
          await FakeAuthRepository().logIn(
            FakeAuthRepository.samplePhone,
            FakeAuthRepository.samplePassword,
          ),
        );
    await tester.tap(find.text('تسجيل الخروج'));
    // Clearing the saved login goes through the (absent) storage plugin.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    // The welcome screen animates for ever: pump a while, not until settled.
    await pumpFor(tester, const Duration(seconds: 2));
    expect(auth.loggedOut, 1);
    expect(container.read(sessionProvider), isNull);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
  });
}
