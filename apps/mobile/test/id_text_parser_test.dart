import 'package:benmahdia_mobile/features/profile/id_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime(2026, 10, 17);

void main() {
  group('parseIdText', () {
    test('finds the 18 digit number and the birth date', () {
      final scanned = parseIdText(
        'REPUBLIQUE ALGERIENNE\nNIN 109900012345678901\nNé le 1990-05-17\n',
        today: _today,
      );
      expect(scanned.idNumber, '109900012345678901');
      expect(scanned.birthDate, DateTime(1990, 5, 17));
    });

    test('takes the earliest date: issue and expiry come later', () {
      final scanned = parseIdText(
        '2019.03.02 1990.05.17 2029.03.01 109900012345678901',
        today: _today,
      );
      expect(scanned.birthDate, DateTime(1990, 5, 17));
    });

    test('reads day-first dates and keeps dates out of the number', () {
      final scanned = parseIdText('17/05/1990 123456789', today: _today);
      expect(scanned.birthDate, DateTime(1990, 5, 17));
      expect(scanned.idNumber, '123456789');
    });

    test('reads Arabic-Indic digits', () {
      final scanned = parseIdText('١٢٣٤٥٦٧٨٩ ١٩٩٠-٠٥-١٧', today: _today);
      expect(scanned.idNumber, '123456789');
      expect(scanned.birthDate, DateTime(1990, 5, 17));
    });

    test('ignores impossible and future dates', () {
      final scanned = parseIdText('1990-13-45 2030-01-01', today: _today);
      expect(scanned.birthDate, isNull);
    });

    test('returns nothing from text without a number or date', () {
      expect(parseIdText('hello 123 world', today: _today).isEmpty, isTrue);
    });
  });

  group('parseDate', () {
    test('accepts both orders and separators', () {
      expect(parseDate('1990-05-17', today: _today), DateTime(1990, 5, 17));
      expect(parseDate('17.05.1990', today: _today), DateTime(1990, 5, 17));
      expect(parseDate(' 17/5/1990 ', today: _today), DateTime(1990, 5, 17));
    });

    test('rejects what is not a real past date', () {
      for (final bad in [
        '',
        '1990',
        '31/02/1990',
        '1899-01-01',
        '2027-01-01',
      ]) {
        expect(parseDate(bad, today: _today), isNull, reason: bad);
      }
    });
  });

  test('normalizeIdNumber drops separators and upper-cases', () {
    expect(normalizeIdNumber(' ab-12 34.5 '), 'AB12345');
    expect(normalizeIdNumber('١٢٣٤٥٦'), '123456');
  });
}
