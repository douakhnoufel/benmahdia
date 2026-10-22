import '../models/identity_document.dart';

class PassportMrzParser {
  const PassportMrzParser();

  static const _confusions = <String, String>{
    'O': '0',
    'Q': '0',
    'D': '0',
    'I': '1',
    'L': '1',
    'Z': '2',
    'S': '5',
    'G': '6',
    'B': '8',
  };

  IdentityDocument parse(String rawText) {
    final sourceLines = rawText
        .split(RegExp(r'[\r\n]+'))
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final lines = sourceLines.map(_mrzCharacters).toList();
    final firstIndex = _findFirstMrzLine(lines);
    final secondIndex = firstIndex >= 0 && firstIndex + 1 < lines.length
        ? firstIndex + 1
        : -1;
    final normalizedMrz = firstIndex >= 0 && secondIndex >= 0
        ? '${lines[firstIndex]}\n${lines[secondIndex]}'
        : lines.join('\n');
    final errors = <String>[];
    final warnings = <String>[];

    if (firstIndex < 0 || secondIndex < 0) {
      errors.add('Two TD3 passport MRZ lines were not found.');
      return IdentityDocument(
        documentType: DocumentType.passport,
        mrz: normalizedMrz,
        rawOcrText: rawText,
        validationErrors: errors,
        warnings: const [
          'No passport fields were inferred from a partial MRZ.',
        ],
      );
    }

    final first = lines[firstIndex];
    final second = lines[secondIndex];
    if (first.length != 44 || second.length != 44) {
      errors.add(
        'TD3 lines must each contain 44 characters; received ${first.length} and ${second.length}.',
      );
      return IdentityDocument(
        documentType: DocumentType.passport,
        mrz: normalizedMrz,
        rawOcrText: rawText,
        validationErrors: errors,
        warnings: const ['Retake the image or type the fields manually.'],
      );
    }

    if (!RegExp(r'^P[<A-Z][A-Z0-9<]{42}$').hasMatch(first)) {
      errors.add('The first line does not match the TD3 passport layout.');
    }

    final issuer = first.substring(2, 5).replaceAll('<', '');
    final surnameAndGiven = first.substring(5).split('<<');
    final surname = _cleanName(surnameAndGiven.first);
    final givenNames = surnameAndGiven.length > 1
        ? surnameAndGiven
              .skip(1)
              .map(_cleanName)
              .where((part) => part.isNotEmpty)
              .join(' ')
        : '';

    final originalBirth = second.substring(13, 19);
    final originalExpiry = second.substring(21, 27);
    final documentCheck = _numericField(second[9], warnings);
    final birth = _numericField(originalBirth, warnings);
    final birthCheck = _numericField(second[19], warnings);
    final expiry = _numericField(originalExpiry, warnings);
    final expiryCheck = _numericField(second[27], warnings);
    final compositeCheck = _numericField(second[43], warnings);
    final documentNumber = second.substring(0, 9);
    final nationality = second.substring(10, 13);
    final sexCode = second[20];

    if (documentCheck == null ||
        mrzCheckDigit(documentNumber) != int.tryParse(documentCheck)) {
      errors.add('Passport number check digit is invalid.');
    }
    if (birth == null ||
        birthCheck == null ||
        mrzCheckDigit(birth) != int.tryParse(birthCheck)) {
      errors.add('Date of birth check digit is invalid.');
    } else if (!_plausibleMrzDate(birth)) {
      errors.add('Date of birth in the MRZ is not a valid calendar date.');
    }
    if (expiry == null ||
        expiryCheck == null ||
        mrzCheckDigit(expiry) != int.tryParse(expiryCheck)) {
      errors.add('Expiry date check digit is invalid.');
    } else if (!_plausibleMrzDate(expiry)) {
      errors.add('Expiry date in the MRZ is not a valid calendar date.');
    }

    final normalizedDocumentCheck = documentCheck ?? second[9];
    final normalizedBirth = birth ?? originalBirth;
    final normalizedBirthCheck = birthCheck ?? second[19];
    final normalizedExpiry = expiry ?? originalExpiry;
    final normalizedExpiryCheck = expiryCheck ?? second[27];
    final composite =
        second.substring(0, 9) +
        normalizedDocumentCheck +
        normalizedBirth +
        normalizedBirthCheck +
        normalizedExpiry +
        normalizedExpiryCheck +
        second.substring(28, 43);
    if (compositeCheck == null ||
        mrzCheckDigit(composite) != int.tryParse(compositeCheck)) {
      errors.add('Composite MRZ check digit is invalid.');
    }
    if (issuer != 'DZA') {
      errors.add('Passport issuing state is not DZA.');
    }
    if (nationality != 'DZA') {
      warnings.add('Passport nationality is not DZA.');
    }

    if (birth != null &&
        birthCheck != null &&
        mrzCheckDigit(birth) == int.tryParse(birthCheck)) {
      warnings.add(
        'MRZ birth year ${birth.substring(0, 2)} has no century; the date was not inferred.',
      );
    }
    if (expiry != null &&
        expiryCheck != null &&
        mrzCheckDigit(expiry) == int.tryParse(expiryCheck)) {
      warnings.add(
        'MRZ expiry year ${expiry.substring(0, 2)} has no century; the date was not inferred.',
      );
    }

    final sex = switch (sexCode) {
      'M' => 'M',
      'F' => 'F',
      '<' => null,
      _ => null,
    };
    if (sex == null && sexCode != '<') {
      warnings.add('Sex marker is not recognized.');
    }

    final normalizedSecond =
        second.substring(0, 9) +
        normalizedDocumentCheck +
        second.substring(10, 13) +
        normalizedBirth +
        normalizedBirthCheck +
        second.substring(20, 21) +
        normalizedExpiry +
        normalizedExpiryCheck +
        second.substring(28, 43) +
        (compositeCheck ?? second[43]);
    final numberCheckFailed = errors.any(
      (error) => error.contains('Passport number'),
    );
    final review = <IdentityField, FieldReview>{
      IdentityField.documentNumber: FieldReview(
        level: numberCheckFailed ? ReviewLevel.uncertain : ReviewLevel.reliable,
        originalRecognizedValue: documentNumber,
      ),
      IdentityField.dateOfBirth: FieldReview(
        level: ReviewLevel.uncertain,
        originalRecognizedValue: originalBirth,
        reason: 'Two-digit MRZ year is ambiguous.',
      ),
      IdentityField.expiryDate: FieldReview(
        level: ReviewLevel.uncertain,
        originalRecognizedValue: originalExpiry,
        reason: 'Two-digit MRZ year is ambiguous.',
      ),
      IdentityField.surname: FieldReview(
        level: surname.isEmpty ? ReviewLevel.unknown : ReviewLevel.uncertain,
        originalRecognizedValue: surname,
      ),
      IdentityField.givenNames: FieldReview(
        level: givenNames.isEmpty ? ReviewLevel.unknown : ReviewLevel.uncertain,
        originalRecognizedValue: givenNames,
      ),
      IdentityField.nationality: FieldReview(
        level: nationality == 'DZA'
            ? ReviewLevel.reliable
            : ReviewLevel.uncertain,
        originalRecognizedValue: nationality,
      ),
    };

    return IdentityDocument(
      documentType: DocumentType.passport,
      surname: surname.isEmpty ? null : surname,
      givenNames: givenNames.isEmpty ? null : givenNames,
      documentNumber: documentNumber.replaceAll('<', '').trim().isEmpty
          ? null
          : documentNumber.replaceAll('<', '').trim(),
      nationality: nationality,
      issuingState: issuer,
      sex: sex,
      mrz: '$first\n$normalizedSecond',
      rawOcrText: rawText,
      fieldReview: review,
      validationErrors: errors,
      warnings: warnings,
    );
  }

  /// Finds the first MRZ line. Page text printed above the MRZ (for example
  /// "PASSEPORT") also starts with "P", so a pair of 44-character lines is
  /// preferred; otherwise a long line with filler characters is used so that
  /// a damaged MRZ still produces a specific length error.
  int _findFirstMrzLine(List<String> lines) {
    final typeCode = RegExp(r'^P[<A-Z]');
    for (var index = 0; index + 1 < lines.length; index++) {
      if (lines[index].length == 44 &&
          lines[index + 1].length == 44 &&
          typeCode.hasMatch(lines[index])) {
        return index;
      }
    }
    return lines.indexWhere(
      (line) =>
          line.length >= 36 && line.contains('<') && typeCode.hasMatch(line),
    );
  }

  String _mrzCharacters(String line) => line
      .toUpperCase()
      .replaceAll('«', '<<')
      .replaceAll(RegExp('[‹＜]'), '<')
      .replaceAll(RegExp(r'[^A-Z0-9<]'), '');

  String? _numericField(String input, List<String> warnings) {
    final output = StringBuffer();
    for (final character in input.split('')) {
      if (RegExp(r'^\d$').hasMatch(character)) {
        output.write(character);
      } else {
        final replacement = _confusions[character];
        if (replacement == null) return null;
        output.write(replacement);
        warnings.add(
          'OCR character $character was read as $replacement in a numeric MRZ field.',
        );
      }
    }
    return output.toString();
  }

  bool _plausibleMrzDate(String yymmdd) {
    if (yymmdd.length != 6) return false;
    final month = int.tryParse(yymmdd.substring(2, 4));
    final day = int.tryParse(yymmdd.substring(4, 6));
    if (month == null || month < 1 || month > 12 || day == null || day < 1) {
      return false;
    }
    final date = DateTime(2000, month, day);
    return date.month == month && date.day == day;
  }

  String _cleanName(String part) =>
      part.replaceAll('<', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// ICAO 9303 character values with repeating 7, 3, 1 weights.
int mrzCheckDigit(String value) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var index = 0; index < value.length; index++) {
    final code = value.codeUnitAt(index);
    final int numeric;
    if (code >= 48 && code <= 57) {
      numeric = code - 48;
    } else if (code >= 65 && code <= 90) {
      numeric = code - 65 + 10;
    } else if (code == 60) {
      numeric = 0;
    } else {
      throw FormatException('Invalid MRZ character.');
    }
    sum += numeric * weights[index % weights.length];
  }
  return sum % 10;
}
