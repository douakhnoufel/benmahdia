import 'package:flutter_test/flutter_test.dart';
import 'package:identity_ocr/models/identity_document.dart';
import 'package:identity_ocr/services/passport_mrz_parser.dart';

void main() {
  const parser = PassportMrzParser();

  test('validates ICAO check digits and extracts TD3 fields', () {
    final mrz = _td3(surname: 'DE<LA<CRUZ', givenNames: 'ANNE<MARIE');
    final parsed = parser.parse(mrz);

    expect(parsed.validationErrors, isEmpty);
    expect(parsed.issuingState, 'DZA');
    expect(parsed.nationality, 'DZA');
    expect(parsed.documentNumber, 'A12B34C56');
    expect(parsed.surname, 'DE LA CRUZ');
    expect(parsed.givenNames, 'ANNE MARIE');
    expect(parsed.sex, 'F');
    expect(parsed.dateOfBirth, isNull);
    expect(
      parsed.fieldReview[IdentityField.dateOfBirth]?.originalRecognizedValue,
      '900101',
    );
    expect(parsed.warnings.join(' '), contains('no century'));
  });

  test('reports number, date and composite check digit failures', () {
    final lines = _td3().split('\n');
    final line = lines[1];
    final wrongNumberCheck = ((int.parse(line[9]) + 1) % 10).toString();
    final wrongCompositeCheck = ((int.parse(line[43]) + 1) % 10).toString();
    final corrupted =
        line.substring(0, 9) +
        wrongNumberCheck +
        line.substring(10, 43) +
        wrongCompositeCheck;
    final parsed = parser.parse('${lines[0]}\n$corrupted');

    expect(
      parsed.validationErrors,
      contains('Passport number check digit is invalid.'),
    );
    expect(
      parsed.validationErrors,
      contains('Composite MRZ check digit is invalid.'),
    );
  });

  test('keeps partial and missing lines unknown instead of padding them', () {
    final complete = _td3().split('\n');
    final partial = parser.parse(
      '${complete[0]}\n${complete[1].substring(0, 35)}',
    );
    final missing = parser.parse(complete[0]);

    expect(partial.documentNumber, isNull);
    expect(partial.validationErrors.single, contains('44 characters'));
    expect(missing.documentNumber, isNull);
    expect(missing.validationErrors.single, contains('not found'));
  });

  test(
    'corrects OCR confusions only inside numeric fields and reports them',
    () {
      final lines = _td3(birth: '000101').split('\n');
      final second = lines[1].replaceRange(13, 14, 'O');
      final parsed = parser.parse('${lines[0]}\n$second');

      expect(parsed.validationErrors, isEmpty);
      expect(parsed.mrz, contains('000101'));
      expect(parsed.warnings.join(' '), contains('read as 0'));
      expect(parsed.dateOfBirth, isNull);
    },
  );

  test('rejects passports with a non-Algerian issuing state', () {
    final parsed = parser.parse(_td3(issuer: 'UTO'));
    expect(parsed.issuingState, 'UTO');
    expect(
      parsed.validationErrors,
      contains('Passport issuing state is not DZA.'),
    );
  });

  test('finds the MRZ below the printed page text', () {
    final parsed = parser.parse(
      'PASSEPORT\nPASSPORT\nREPUBLIQUE ALGERIENNE DEMOCRATIQUE ET POPULAIRE\n'
      '${_td3()}\n',
    );

    expect(parsed.validationErrors, isEmpty);
    expect(parsed.documentNumber, 'A12B34C56');
    expect(parsed.surname, 'SAMPLE');
  });

  test('uses the ICAO character values for check digits', () {
    expect(mrzCheckDigit('A'), 0);
    expect(mrzCheckDigit('<'), 0);
  });
}

String _td3({
  String issuer = 'DZA',
  String nationality = 'DZA',
  String surname = 'SAMPLE',
  String givenNames = 'ALPHA<BETA',
  String birth = '900101',
  String expiry = '300101',
}) {
  final first = ('P<$issuer$surname<<$givenNames')
      .padRight(44, '<')
      .substring(0, 44);
  const documentNumber = 'A12B34C56';
  final documentCheck = mrzCheckDigit(documentNumber).toString();
  final birthCheck = mrzCheckDigit(birth).toString();
  final expiryCheck = mrzCheckDigit(expiry).toString();
  final optionalData = List.filled(14, '<').join();
  final lineWithoutComposite =
      '$documentNumber$documentCheck$nationality$birth${birthCheck}F$expiry$expiryCheck$optionalData<';
  final composite =
      lineWithoutComposite.substring(0, 10) +
      lineWithoutComposite.substring(13, 20) +
      lineWithoutComposite.substring(21, 43);
  return '$first\n$lineWithoutComposite${mrzCheckDigit(composite)}';
}
