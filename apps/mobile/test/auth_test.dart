import 'package:benmahdia_mobile/features/auth/auth_flow.dart';
import 'package:benmahdia_mobile/features/auth/auth_models.dart';
import 'package:benmahdia_mobile/features/auth/auth_repository.dart';
import 'package:benmahdia_mobile/features/auth/fake_auth_repository.dart';
import 'package:benmahdia_mobile/features/auth/login_screen.dart';
import 'package:benmahdia_mobile/features/auth/otp_screen.dart';
import 'package:benmahdia_mobile/features/auth/password_rules.dart';
import 'package:benmahdia_mobile/features/auth/password_screen.dart';
import 'package:benmahdia_mobile/features/auth/phone_entry_screen.dart';
import 'package:benmahdia_mobile/features/auth/phone_number.dart';
import 'package:benmahdia_mobile/features/auth/sign_up_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _second = Duration(seconds: 1);
const _code = FakeAuthRepository.devCode;

List<Override> _with(AuthRepository repo) => [
  authRepositoryProvider.overrideWithValue(repo),
];

/// The text field inside the sign-up / login / phone screens.
Finder _phoneField() => find.byType(TextField).first;

Finder _codeField() => find.descendant(
  of: find.byType(OtpScreen),
  matching: find.byType(TextField),
);

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(_codeField(), code);
  await tester.pump();
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) => pumpFor(tester, _second);

void main() {
  group('PhoneNumber', () {
    test('reads the ways people type an Algerian mobile', () {
      for (final input in [
        '0550123456',
        '0550 12 34 56',
        '550123456',
        '+213 550 12 34 56',
        '00213550123456',
        '213550123456',
        '٠٥٥٠١٢٣٤٥٦',
        '05-50-12-34-56',
      ]) {
        expect(
          PhoneNumber.tryParse(input)?.e164,
          '+213550123456',
          reason: input,
        );
      }
    });

    test('accepts 05, 06 and 07, nothing else', () {
      expect(PhoneNumber.tryParse('0661234567'), isNotNull);
      expect(PhoneNumber.tryParse('0771234567'), isNotNull);
      for (final input in [
        '021234567',
        '0450123456',
        '055012345',
        '05501234567',
        'abc',
        '',
      ]) {
        expect(PhoneNumber.tryParse(input), isNull, reason: input);
      }
    });

    test('national display', () {
      expect(PhoneNumber.tryParse('+213550123456')!.national, '0550 12 34 56');
    });
  });

  test('password rules', () {
    expect(PasswordRule.allMetBy('sobre2026'), isTrue);
    expect(PasswordRule.allMetBy('short1'), isFalse);
    expect(PasswordRule.allMetBy('onlyletters'), isFalse);
    expect(PasswordRule.allMetBy('12345678'), isFalse);
    expect(PasswordRule.allMetBy('كلمةسر2026'), isTrue);
  });

  group('SignUpScreen', () {
    testWidgets('rejects a number that is not an Algerian mobile', (
      tester,
    ) async {
      PhoneNumber? sent;
      await pumpApp(
        tester,
        SignUpScreen(
          onCodeSent: (p, _) => sent = p,
          onSignedIn: (_) {},
          onLogin: () {},
        ),
        overrides: _with(FakeAuthRepository()),
      );
      await _settle(tester);
      await tester.enterText(_phoneField(), '021 23 45 67');
      await tester.tap(find.text('متابعة'));
      await tester.pump();
      expect(find.textContaining('رقم هاتف نقّال جزائرياً'), findsOneWidget);
      expect(sent, isNull);
    });

    testWidgets('sends a code to a new number', (tester) async {
      PhoneNumber? sent;
      await pumpApp(
        tester,
        SignUpScreen(
          onCodeSent: (p, _) => sent = p,
          onSignedIn: (_) {},
          onLogin: () {},
        ),
        overrides: _with(FakeAuthRepository()),
      );
      await _settle(tester);
      await tester.enterText(_phoneField(), '0661 23 45 67');
      await tester.tap(find.text('متابعة'));
      await tester.pump();
      expect(sent?.e164, '+213661234567');
    });

    testWidgets('a number that already has an account says so', (tester) async {
      await pumpApp(
        tester,
        SignUpScreen(onCodeSent: (_, _) {}, onSignedIn: (_) {}, onLogin: () {}),
        overrides: _with(FakeAuthRepository()),
      );
      await _settle(tester);
      await tester.enterText(_phoneField(), '0550123456');
      await tester.tap(find.text('متابعة'));
      await _settle(tester);
      expect(find.textContaining('مسجّل في حساب آخر'), findsOneWidget);
    });

    testWidgets('Arabic is right-to-left; French is left-to-right', (
      tester,
    ) async {
      await pumpApp(
        tester,
        SignUpScreen(onCodeSent: (_, _) {}, onSignedIn: (_) {}, onLogin: () {}),
        overrides: _with(FakeAuthRepository()),
      );
      await _settle(tester);
      expect(directionOf(tester, SignUpScreen), TextDirection.rtl);
      expect(find.text('المتابعة باستخدام Google'), findsOneWidget);
      expect(find.text('المتابعة باستخدام Apple'), findsOneWidget);

      await useFrench(tester);
      await _settle(tester);
      expect(directionOf(tester, SignUpScreen), TextDirection.ltr);
      expect(find.text('Créer un compte'), findsWidgets);
      expect(find.text('Continuer avec Google'), findsOneWidget);
    });
  });

  group('OtpScreen', () {
    var now = DateTime(2026, 10, 17, 18);

    Future<(FakeAuthRepository, List<String>)> pumpOtp(
      WidgetTester tester,
    ) async {
      final repo = FakeAuthRepository(clock: () => now);
      final phone = PhoneNumber.tryParse('0661234567')!;
      final ticket = await repo.requestCode(phone, OtpPurpose.signUp);
      final proofs = <String>[];
      await pumpApp(
        tester,
        OtpScreen(
          phone: phone,
          purpose: OtpPurpose.signUp,
          ticket: ticket,
          onVerified: (p) async => proofs.add(p),
        ),
        overrides: _with(repo),
      );
      await _settle(tester);
      return (repo, proofs);
    }

    testWidgets('the right code is checked as soon as it is complete', (
      tester,
    ) async {
      final (_, proofs) = await pumpOtp(tester);
      expect(find.textContaining('0661 23 45 67'), findsOneWidget);
      await _enterCode(tester, _code);
      expect(proofs, hasLength(1));
    });

    testWidgets('a wrong code shows an error and clears the boxes', (
      tester,
    ) async {
      final (_, proofs) = await pumpOtp(tester);
      await _enterCode(tester, '000000');
      expect(find.text('الرمز غير صحيح. حاول مجدداً.'), findsOneWidget);
      expect(proofs, isEmpty);
      final field = tester.widget<TextField>(_codeField());
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('five wrong codes ask for a new one', (tester) async {
      final (_, proofs) = await pumpOtp(tester);
      for (var i = 0; i < 5; i++) {
        await _enterCode(tester, '00000$i');
      }
      expect(find.text('محاولات كثيرة. اطلب رمزاً جديداً.'), findsOneWidget);
      expect(proofs, isEmpty);
    });

    testWidgets('a new code can be asked for after 60 seconds', (tester) async {
      await pumpOtp(tester);
      expect(find.textContaining('يمكنك طلب رمز جديد بعد'), findsOneWidget);
      expect(find.text('إعادة إرسال الرمز'), findsNothing);

      await pumpFor(tester, const Duration(seconds: 60));
      now = now.add(const Duration(seconds: 60));
      expect(find.text('إعادة إرسال الرمز'), findsOneWidget);
      await tester.tap(find.text('إعادة إرسال الرمز'));
      await _settle(tester);
      expect(find.text('أرسلنا رمزاً جديداً'), findsOneWidget);
      expect(find.textContaining('يمكنك طلب رمز جديد بعد'), findsOneWidget);
    });
  });

  group('PasswordScreen', () {
    testWidgets('the button waits until every rule is met', (tester) async {
      final semantics = tester.ensureSemantics();
      String? saved;
      await pumpApp(
        tester,
        PasswordScreen(
          mode: PasswordMode.create,
          onSubmit: (p) async => saved = p,
        ),
      );
      await _settle(tester);
      final fields = find.byType(TextField);
      FilledButton button() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'إنشاء الحساب'),
      );

      await tester.enterText(fields.at(0), 'short');
      await tester.pump();
      expect(button().onPressed, isNull);
      expect(
        find.bySemanticsLabel('لم يتحقق بعد: 8 أحرف على الأقل'),
        findsOneWidget,
      );

      await tester.enterText(fields.at(0), 'sobre2026');
      await tester.enterText(fields.at(1), 'sobre2025');
      await tester.pump();
      expect(button().onPressed, isNull);

      await tester.enterText(fields.at(1), 'sobre2026');
      await _settle(tester);
      expect(
        find.bySemanticsLabel('تم: كلمتا المرور متطابقتان'),
        findsOneWidget,
      );
      await tester.tap(find.text('إنشاء الحساب'));
      await tester.pump();
      expect(saved, 'sobre2026');
      semantics.dispose();
    });

    testWidgets('the password can be shown', (tester) async {
      await pumpApp(
        tester,
        PasswordScreen(mode: PasswordMode.reset, onSubmit: (_) async {}),
      );
      await _settle(tester);
      expect(find.text('كلمة مرور جديدة'), findsOneWidget);
      bool obscured() =>
          tester.widget<TextField>(find.byType(TextField).first).obscureText;
      expect(obscured(), isTrue);
      await tester.tap(find.byTooltip('إظهار كلمة المرور').first);
      await tester.pump();
      expect(obscured(), isFalse);
    });
  });

  group('LoginScreen', () {
    Future<List<AuthSession>> pumpLogin(WidgetTester tester) async {
      final sessions = <AuthSession>[];
      await pumpApp(
        tester,
        LoginScreen(
          onSignedIn: sessions.add,
          onForgot: (_) {},
          onCreateAccount: () {},
        ),
        overrides: _with(FakeAuthRepository()),
      );
      await _settle(tester);
      return sessions;
    }

    Future<void> logIn(WidgetTester tester, String password) async {
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '0550 12 34 56');
      await tester.enterText(fields.at(1), password);
      await tester.tap(find.widgetWithText(FilledButton, 'تسجيل الدخول'));
      await _settle(tester);
    }

    testWidgets('signs in with the right password', (tester) async {
      final sessions = await pumpLogin(tester);
      await logIn(tester, FakeAuthRepository.samplePassword);
      expect(sessions.single.user.verified, isTrue);
    });

    testWidgets('five wrong passwords lock the account', (tester) async {
      final sessions = await pumpLogin(tester);
      await logIn(tester, 'wrong-1');
      expect(find.text('رقم الهاتف أو كلمة المرور غير صحيحة.'), findsOneWidget);
      for (var i = 2; i <= 5; i++) {
        await logIn(tester, 'wrong-$i');
      }
      expect(find.textContaining('حاول مجدداً بعد 15 دقيقة'), findsOneWidget);
      // Even the right password waits now.
      await logIn(tester, FakeAuthRepository.samplePassword);
      expect(find.textContaining('أوقفنا الدخول مؤقتاً'), findsOneWidget);
      expect(sessions, isEmpty);
    });
  });

  group('flows', () {
    Future<List<AuthSession>> start(
      WidgetTester tester, {
      required bool signUp,
    }) async {
      final sessions = <AuthSession>[];
      await pumpApp(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => signUp
                    ? openSignUp(context, onSignedIn: sessions.add)
                    : openLogin(context, onSignedIn: sessions.add),
                child: const Text('go'),
              ),
            ),
          ),
        ),
        overrides: _with(FakeAuthRepository()),
      );
      await tester.tap(find.text('go'));
      await _settle(tester);
      return sessions;
    }

    testWidgets('sign-up by phone: number, code, password', (tester) async {
      final sessions = await start(tester, signUp: true);
      await tester.enterText(_phoneField(), '0661234567');
      await tester.tap(find.text('متابعة'));
      await _settle(tester);
      await _enterCode(tester, _code);
      await _settle(tester);
      expect(find.byType(PasswordScreen), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'sobre2026');
      await tester.enterText(fields.at(1), 'sobre2026');
      await tester.pump();
      await tester.tap(find.text('إنشاء الحساب'));
      await _settle(tester);

      expect(find.text('go'), findsOneWidget, reason: 'account screens closed');
      final session = sessions.single;
      expect(session.user.phone?.e164, '+213661234567');
      expect(session.user.verified, isFalse);
      final container = ProviderScope.containerOf(
        tester.element(find.text('go')),
      );
      expect(container.read(sessionProvider), same(session));
    });

    testWidgets('Google, then a confirmed phone number', (tester) async {
      final sessions = await start(tester, signUp: true);
      await tester.tap(find.text('المتابعة باستخدام Google'));
      await _settle(tester);
      expect(find.byType(PhoneEntryScreen), findsOneWidget);
      expect(sessions, isEmpty, reason: 'a phone number is still needed');

      await tester.enterText(_phoneField(), '0771234567');
      await tester.tap(find.text('إرسال الرمز'));
      await _settle(tester);
      await _enterCode(tester, _code);
      await _settle(tester);

      expect(find.text('go'), findsOneWidget);
      expect(sessions.single.user.phone?.e164, '+213771234567');
    });

    testWidgets('forgot password: code, new password, signed in', (
      tester,
    ) async {
      final sessions = await start(tester, signUp: false);
      await tester.enterText(_phoneField(), '0550123456');
      await tester.tap(find.text('نسيت كلمة المرور؟'));
      await _settle(tester);
      expect(find.byType(PhoneEntryScreen), findsOneWidget);
      // What was typed on the login screen is kept.
      expect(find.text('0550123456'), findsOneWidget);
      await tester.tap(find.text('إرسال الرمز'));
      await _settle(tester);
      await _enterCode(tester, _code);
      await _settle(tester);
      expect(find.text('كلمة مرور جديدة'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'nouveau2026');
      await tester.enterText(fields.at(1), 'nouveau2026');
      await tester.pump();
      await tester.tap(find.text('حفظ كلمة المرور'));
      await _settle(tester);
      expect(sessions.single.user.verified, isTrue);
    });

    testWidgets('sign-up and login link to each other', (tester) async {
      await start(tester, signUp: true);
      await tester.tap(find.widgetWithText(TextButton, 'تسجيل الدخول'));
      await _settle(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(SignUpScreen), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'إنشاء حساب'));
      await _settle(tester);
      expect(find.byType(SignUpScreen), findsOneWidget);
    });
  });
}
