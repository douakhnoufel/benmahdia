import 'dart:typed_data';

import 'package:benmahdia_mobile/features/booking/booking_flow.dart';
import 'package:benmahdia_mobile/features/booking/booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/fake_booking_repository.dart';
import 'package:benmahdia_mobile/features/profile/capture.dart';
import 'package:benmahdia_mobile/features/profile/fake_identity_repository.dart';
import 'package:benmahdia_mobile/features/profile/id_text_parser.dart';
import 'package:benmahdia_mobile/features/profile/identity_models.dart';
import 'package:benmahdia_mobile/features/profile/identity_repository.dart';
import 'package:benmahdia_mobile/features/profile/profile_flow.dart';
import 'package:benmahdia_mobile/features/profile/profile_form_screen.dart';
import 'package:benmahdia_mobile/features/profile/profile_prompt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _Reader implements IdReader {
  ScannedId? result = ScannedId(
    idNumber: '123456789012345678',
    birthDate: DateTime(1990, 5, 17),
  );
  bool fails = false;
  int scans = 0;

  @override
  Future<ScannedId?> scan() async {
    scans++;
    if (fails) throw const IdReadFailed();
    return result;
  }
}

class _Camera implements SelfieCamera {
  Uint8List? shot = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 7, 7]);

  @override
  Future<Uint8List?> take() async => shot;
}

const _second = Duration(seconds: 1);

List<Override> _with(
  FakeIdentityRepository identity, {
  _Reader? reader,
  _Camera? camera,
}) => [
  identityRepositoryProvider.overrideWithValue(identity),
  idReaderProvider.overrideWithValue(reader ?? _Reader()),
  selfieCameraProvider.overrideWithValue(camera ?? _Camera()),
  bookingRepositoryProvider.overrideWithValue(
    FakeBookingRepository(clock: () => DateTime(2026, 10, 17, 17, 10)),
  ),
];

Widget _launcher(void Function(BuildContext) open) => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(onPressed: () => open(context), child: const Text('go')),
    ),
  ),
);

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpFor(tester, _second);
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

Future<void> _openForm(WidgetTester tester) async {
  await tester.tap(find.text('go'));
  await pumpFor(tester, _second);
  await _tap(tester, 'profile-consent');
  await _tap(tester, 'profile-start');
}

void main() {
  group('Complete your profile', () {
    testWidgets('starting needs consent', (tester) async {
      await pumpApp(
        tester,
        _launcher(openProfile),
        overrides: _with(FakeIdentityRepository()),
      );
      await tester.tap(find.text('go'));
      await pumpFor(tester, _second);

      FilledButton start() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('profile-start')),
      );
      expect(start().onPressed, isNull);
      await _tap(tester, 'profile-consent');
      expect(start().onPressed, isNotNull);
      await _tap(tester, 'profile-start');
      expect(find.byType(ProfileFormScreen), findsOneWidget);
    });

    testWidgets('skip comes back and carries on', (tester) async {
      var after = 0;
      await pumpApp(
        tester,
        _launcher((c) => openProfile(c, afterFinish: () => after++)),
        overrides: _with(FakeIdentityRepository()),
      );
      await tester.tap(find.text('go'));
      await pumpFor(tester, _second);
      expect(find.byType(ProfilePromptScreen), findsOneWidget);

      await _tap(tester, 'profile-skip');
      expect(find.byType(ProfilePromptScreen), findsNothing);
      expect(find.text('go'), findsOneWidget);
      expect(after, 1);
    });

    testWidgets('scan, selfie, send: the clinic gets exactly the declaration', (
      tester,
    ) async {
      final identity = FakeIdentityRepository();
      final camera = _Camera();
      var after = 0;
      await pumpApp(
        tester,
        _launcher((c) => openProfile(c, afterFinish: () => after++)),
        overrides: _with(identity, camera: camera),
      );
      await _openForm(tester);

      await _tap(tester, 'profile-scan');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('profile-id')))
            .controller!
            .text,
        '123456789012345678',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('profile-birth')))
            .controller!
            .text,
        '1990-05-17',
      );

      await _type(tester, 'profile-name', 'Karim  Benali');
      await _tap(tester, 'profile-selfie');
      await _tap(tester, 'profile-submit');

      expect(identity.submitted, hasLength(1));
      final sent = identity.submitted.single;
      expect(sent.draft.idNumber, '123456789012345678');
      expect(sent.draft.fullName, 'Karim Benali');
      expect(sent.draft.birthIso, '1990-05-17');
      expect(sent.selfie, camera.shot);

      await _tap(tester, 'profile-done');
      expect(find.text('go'), findsOneWidget);
      expect(after, 1);
    });

    testWidgets('typing the details works when the card cannot be read', (
      tester,
    ) async {
      final identity = FakeIdentityRepository();
      final reader = _Reader()..fails = true;
      await pumpApp(
        tester,
        _launcher(openProfile),
        overrides: _with(identity, reader: reader),
      );
      await _openForm(tester);

      await _tap(tester, 'profile-scan');
      expect(find.text('تعذّرت قراءة البطاقة. اكتب البيانات بنفسك.'), findsOneWidget);

      await _type(tester, 'profile-id', '12 34 56 78 90');
      await _type(tester, 'profile-name', 'Karim Benali');
      await _type(tester, 'profile-birth', '17/05/1990');
      await _tap(tester, 'profile-selfie');
      await _tap(tester, 'profile-submit');
      expect(identity.submitted.single.draft.idNumber, '1234567890');
      expect(identity.submitted.single.draft.birthIso, '1990-05-17');
    });

    testWidgets('closing the camera changes nothing', (tester) async {
      final reader = _Reader()..result = null;
      final camera = _Camera()..shot = null;
      await pumpApp(
        tester,
        _launcher(openProfile),
        overrides: _with(FakeIdentityRepository(), reader: reader, camera: camera),
      );
      await _openForm(tester);
      await _tap(tester, 'profile-scan');
      await _tap(tester, 'profile-selfie');
      expect(reader.scans, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('profile-id')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('الصورة جاهزة · أعد الصورة'), findsNothing);
    });

    testWidgets('empty or wrong fields are explained and nothing is sent', (
      tester,
    ) async {
      final identity = FakeIdentityRepository();
      await pumpApp(
        tester,
        _launcher(openProfile),
        overrides: _with(identity),
      );
      await _openForm(tester);
      await _tap(tester, 'profile-submit');

      expect(identity.submitted, isEmpty);
      expect(find.text('رقم الهوية غير صالح.'), findsOneWidget);
      expect(find.text('اكتب اسمك الكامل.'), findsOneWidget);
      expect(find.text('تاريخ الميلاد غير صالح. اكتبه هكذا: 1990-05-17.'), findsOneWidget);
      expect(find.text('التقط صورة سيلفي أولاً.'), findsOneWidget);
    });

    testWidgets('an ID linked to another account stays on the form', (
      tester,
    ) async {
      final identity = FakeIdentityRepository()
        ..failNext = const IdAlreadyLinked();
      await pumpApp(
        tester,
        _launcher(openProfile),
        overrides: _with(identity),
      );
      await _openForm(tester);
      await _tap(tester, 'profile-scan');
      await _type(tester, 'profile-name', 'Karim Benali');
      await _tap(tester, 'profile-selfie');
      await _tap(tester, 'profile-submit');

      expect(
        find.text('هذه الهوية مرتبطة بحساب آخر. تواصل مع العيادة.'),
        findsOneWidget,
      );
      expect(find.byType(ProfileFormScreen), findsOneWidget);
      expect(identity.submitted, isEmpty);
    });
  });

  group('booking is locked until the clinic approves', () {
    Future<void> openAppointmentsFrom(
      WidgetTester tester,
      FakeIdentityRepository identity,
    ) async {
      await pumpApp(
        tester,
        _launcher(openAppointments),
        overrides: _with(identity),
      );
      await tester.tap(find.text('go'));
      await pumpFor(tester, _second);
    }

    testWidgets('a patient who skipped sees the card, and book leads to it', (
      tester,
    ) async {
      await openAppointmentsFrom(tester, FakeIdentityRepository());
      expect(find.byKey(const ValueKey('profile-card')), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await pumpFor(tester, _second);
      expect(find.byType(ProfilePromptScreen), findsOneWidget);
    });

    testWidgets('the card starts the profile too', (tester) async {
      await openAppointmentsFrom(tester, FakeIdentityRepository());
      await _tap(tester, 'profile-card-action');
      expect(find.byType(ProfilePromptScreen), findsOneWidget);
    });

    testWidgets('after sending, the card waits for the clinic', (tester) async {
      final identity = FakeIdentityRepository(
        initial: const IdentityState(status: IdStatus.declared),
      );
      await openAppointmentsFrom(tester, identity);
      expect(find.text('في انتظار العيادة'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await pumpFor(tester, _second);
      expect(find.byType(ProfilePromptScreen), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);

      identity.approve();
      await _tap(tester, 'profile-card-action');
      expect(find.byKey(const ValueKey('profile-card')), findsNothing);
    });

    testWidgets('a refusal shows the reason and allows sending again', (
      tester,
    ) async {
      final identity = FakeIdentityRepository(
        initial: const IdentityState(
          status: IdStatus.rejected,
          rejectReason: 'Photo floue',
          submissionsLeft: 2,
        ),
      );
      await openAppointmentsFrom(tester, identity);
      expect(find.text('لم تُقبل البيانات'), findsOneWidget);
      expect(find.textContaining('Photo floue'), findsOneWidget);
      await _tap(tester, 'profile-card-action');
      expect(find.byType(ProfilePromptScreen), findsOneWidget);
    });

    testWidgets('no attempts left: no way to send again', (tester) async {
      final identity = FakeIdentityRepository(
        initial: const IdentityState(
          status: IdStatus.rejected,
          submissionsLeft: 0,
        ),
      );
      await openAppointmentsFrom(tester, identity);
      expect(find.byKey(const ValueKey('profile-card-action')), findsNothing);
    });

    testWidgets('an approved patient sees no card and can book', (tester) async {
      final identity = FakeIdentityRepository(
        initial: const IdentityState(status: IdStatus.approved),
      );
      await openAppointmentsFrom(tester, identity);
      expect(find.byKey(const ValueKey('profile-card')), findsNothing);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await pumpFor(tester, _second);
      expect(find.byType(ProfilePromptScreen), findsNothing);
    });
  });
}
