import 'package:flutter_test/flutter_test.dart';
import 'package:identity_ocr/models/identity_document.dart';
import 'package:identity_ocr/services/date_parser.dart';

void main() {
  test('parses an unambiguous ISO date and outputs ISO 8601', () {
    final parsed = parseDocumentDate('1990-05-17');
    expect(parsed.value, DateTime(1990, 5, 17));
    expect(dateToIso(parsed.value), '1990-05-17');
  });

  test('parses an unambiguous day-first date', () {
    final parsed = parseDocumentDate('17/05/1990');
    expect(parsed.value, DateTime(1990, 5, 17));
  });

  test('preserves ambiguous order and two-digit years', () {
    final order = parseDocumentDate('05/06/1990');
    final century = parseDocumentDate('17/05/90');

    expect(order.value, isNull);
    expect(order.isAmbiguous, isTrue);
    expect(century.value, isNull);
    expect(century.isAmbiguous, isTrue);
    expect(century.originalValue, '17/05/90');
  });

  test('rejects impossible calendar dates and unsupported formats', () {
    expect(parseDocumentDate('31/02/1990').value, isNull);
    expect(parseDocumentDate('1990-13-17').value, isNull);
    expect(parseDocumentDate('1990').value, isNull);
  });

  test(
    'reads numeric dates day-first when asked, as on Algerian documents',
    () {
      expect(
        parseDocumentDate('05/03/1990', dayFirst: true).value,
        DateTime(1990, 3, 5),
      );
      expect(
        parseDocumentDate('17/05/1990', dayFirst: true).value,
        DateTime(1990, 5, 17),
      );
      expect(parseDocumentDate('05/17/1990', dayFirst: true).value, isNull);
      expect(parseDocumentDate('05/03/90', dayFirst: true).isAmbiguous, isTrue);
    },
  );
}
