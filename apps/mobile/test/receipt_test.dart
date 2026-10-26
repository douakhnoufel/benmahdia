import 'dart:convert';

import 'package:benmahdia_mobile/features/booking/api_booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/booking_models.dart';
import 'package:benmahdia_mobile/features/booking/booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/fake_booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/my_appointments_screen.dart';
import 'package:benmahdia_mobile/features/booking/receipt_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

// Saturday 17 October 2026, 17:10 clinic time.
final _now = DateTime(2026, 10, 17, 17, 10);
const _second = Duration(seconds: 1);

Appointment _visit({required bool paid, PaymentMethod? method}) => Appointment(
  id: 'r1',
  doctor: FakeBookingRepository.sampleDoctor,
  start: DateTime(2026, 10, 19, 9),
  end: DateTime(2026, 10, 19, 9, 15),
  status: AppointmentStatus.confirmed,
  priceDzd: 2000,
  method: method ?? PaymentMethod.cib,
  paid: paid,
);

FakeBookingRepository _repo({List<Appointment> history = const []}) =>
    FakeBookingRepository(clock: () => _now, history: history);

void main() {
  group('receipt screen', () {
    testWidgets('Arabic, right to left', (tester) async {
      await pumpApp(
        tester,
        ReceiptScreen(appointment: _visit(paid: true)),
        overrides: [bookingRepositoryProvider.overrideWithValue(_repo())],
      );
      await pumpFor(tester, _second);
      expect(find.text('وصل الدفع'), findsOneWidget);
      expect(find.text('BM-000000R1'), findsOneWidget);
      expect(find.text('بطاقة CIB'), findsWidgets);
      expect(find.text('وصل دفع، وليس فاتورة.'), findsOneWidget);
      expect(directionOf(tester, ReceiptScreen), TextDirection.rtl);
    });

    testWidgets('French, and the patient can copy it', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpApp(
        tester,
        ReceiptScreen(appointment: _visit(paid: true)),
        overrides: [bookingRepositoryProvider.overrideWithValue(_repo())],
      );
      await useFrench(tester);
      await pumpFor(tester, _second);
      expect(find.text('Reçu de paiement'), findsOneWidget);
      expect(find.text('2000 DA'), findsOneWidget);
      expect(find.text('Référence du paiement'), findsOneWidget);
      await tester.tap(find.text('Copier le reçu'));
      await pumpFor(tester, _second);
      expect(copied, contains('N° de reçu : BM-000000R1'));
      expect(copied, contains('Reçu de paiement, pas une facture.'));
      expect(find.text('Reçu copié'), findsOneWidget);
    });

    testWidgets('pay-at-clinic has no payment reference', (tester) async {
      await pumpApp(
        tester,
        ReceiptScreen(
          appointment: _visit(paid: true, method: PaymentMethod.clinic),
        ),
        overrides: [bookingRepositoryProvider.overrideWithValue(_repo())],
      );
      await useFrench(tester);
      await pumpFor(tester, _second);
      expect(find.text('Payer à la clinique'), findsOneWidget);
      expect(find.text('Référence du paiement'), findsNothing);
    });

    testWidgets('an unpaid visit says so', (tester) async {
      await pumpApp(
        tester,
        ReceiptScreen(appointment: _visit(paid: false)),
        overrides: [bookingRepositoryProvider.overrideWithValue(_repo())],
      );
      await useFrench(tester);
      await pumpFor(tester, _second);
      expect(
        find.text("Ce rendez-vous n'est pas encore payé."),
        findsOneWidget,
      );
    });
  });

  testWidgets('a paid visit offers its receipt, an unpaid one does not', (
    tester,
  ) async {
    final repo = _repo(
      history: [
        _visit(paid: true),
        Appointment(
          id: 'r2',
          doctor: FakeBookingRepository.sampleDoctor,
          start: DateTime(2026, 10, 20, 9),
          end: DateTime(2026, 10, 20, 9, 15),
          status: AppointmentStatus.confirmed,
          priceDzd: 2000,
          method: PaymentMethod.clinic,
        ),
      ],
    );
    await pumpApp(
      tester,
      MyAppointmentsScreen(onBookNew: () {}),
      overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
    );
    await useFrench(tester);
    await pumpFor(tester, _second);
    expect(find.text('Voir le reçu'), findsOneWidget);
    await tester.tap(find.text('Voir le reçu'));
    await pumpFor(tester, _second);
    expect(find.byType(ReceiptScreen), findsOneWidget);
  });

  test('the API repository reads paid and the receipt', () async {
    final r = ApiBookingRepository(
      baseUrl: Uri.parse('http://api.test/'),
      token: () => 'access-1',
      refresh: () async => false,
      clock: () => DateTime.utc(2026, 10, 17, 18),
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'number': 'BM-1A2B3C4D',
            'appointment_id': 'a-1',
            'doctor_name_ar': 'د. بن مهدية حسين',
            'doctor_name_fr': 'Dr Benmahdia Hocine',
            'start': '2026-10-19T08:00:00Z',
            'amount_dzd': 2000,
            'method': 'cib',
            'paid_at': '2026-10-17T17:00:00Z',
            'payment_ref': 'chk_1',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final receipt = await r.receipt(_visit(paid: true));
    expect(receipt.number, 'BM-1A2B3C4D');
    expect(receipt.start, DateTime(2026, 10, 19, 9));
    expect(receipt.paidAt, DateTime(2026, 10, 17, 18));
    expect((receipt.method, receipt.paymentRef), (PaymentMethod.cib, 'chk_1'));
  });
}
