import 'package:flutter_test/flutter_test.dart';
import 'package:identity_ocr/services/algerian_id_parser.dart';

void main() {
  const parser = AlgerianIdParser();

  test('extracts only uniquely labeled fields', () {
    final parsed = parser.parse(
      'NOM: EXAMPLE\n'
      'PRENOMS: ALPHA BETA\n'
      'NIN: 123456789012345678\n'
      'DATE DE NAISSANCE: 17/05/1990\n',
    );

    expect(parsed.surname, 'EXAMPLE');
    expect(parsed.givenNames, 'ALPHA BETA');
    expect(parsed.documentNumber, '123456789012345678');
    expect(parsed.dateOfBirth, DateTime(1990, 5, 17));
    expect(parsed.warnings.join(' '), contains('not been validated'));
  });

  test('does not choose between multiple candidate number values', () {
    final parsed = parser.parse(
      'NIN: 123456789012345678\nNIN: 987654321098765432\n',
    );

    expect(parsed.documentNumber, isNull);
    expect(
      parsed.validationErrors,
      contains('Multiple candidate identity-number labels were recognized.'),
    );
  });

  test('does not select one of multiple numeric values after a label', () {
    final parsed = parser.parse('NIN: 123456 654321\n');

    expect(parsed.documentNumber, isNull);
    expect(
      parsed.validationErrors,
      contains('More than one number followed an identity-number label.'),
    );
  });

  test('leaves an unsupported unlabeled layout unknown', () {
    final parsed = parser.parse(
      'REPUBLIQUE ALGERIENNE\n'
      '123456789012345678\n'
      '1990-05-17\n',
    );

    expect(parsed.documentNumber, isNull);
    expect(parsed.dateOfBirth, isNull);
    expect(parsed.surname, isNull);
    expect(parsed.warnings.join(' '), contains('No configured label template'));
  });

  test('handles empty OCR text without guessing', () {
    final parsed = parser.parse('');
    expect(parsed.documentNumber, isNull);
    expect(parsed.warnings.single, contains('No text was recognized'));
  });

  test('normalizes Arabic-Indic digits only after an explicit date label', () {
    final parsed = parser.parse('تاريخ الميلاد: ١٧/٠٥/١٩٩٠');
    expect(parsed.dateOfBirth, DateTime(1990, 5, 17));
  });

  test('reads a birth date with both numbers <= 12 as day/month', () {
    final parsed = parser.parse('DATE DE NAISSANCE: 05/03/1990');
    expect(parsed.dateOfBirth, DateTime(1990, 3, 5));
  });

  test('does not take another field label as a value', () {
    final parsed = parser.parse('NOM:\nPRENOMS: ALPHA\n');
    expect(parsed.surname, isNull);
    expect(parsed.givenNames, 'ALPHA');
  });

  test('a label must end before its value starts', () {
    final parsed = parser.parse(
      'NOMBRE: 5\nNINA: 000\nNIN: 123456789012345678\n',
    );
    expect(parsed.surname, isNull);
    expect(parsed.documentNumber, '123456789012345678');
  });

  test('reads the "née le" label with or without the accent or colon', () {
    expect(
      parser.parse('NÉE LE 17/05/1990').dateOfBirth,
      DateTime(1990, 5, 17),
    );
    expect(
      parser.parse('NE LE: 17/05/1990').dateOfBirth,
      DateTime(1990, 5, 17),
    );
  });
}
