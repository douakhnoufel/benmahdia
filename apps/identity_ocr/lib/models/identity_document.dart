enum DocumentType { nationalId, passport }

enum IdentityField {
  surname,
  givenNames,
  documentNumber,
  nationality,
  issuingState,
  sex,
  dateOfBirth,
  issueDate,
  expiryDate,
}

enum ReviewLevel { reliable, uncertain, unknown }

class FieldReview {
  const FieldReview({
    required this.level,
    this.originalRecognizedValue,
    this.reason,
  });

  final ReviewLevel level;
  final String? originalRecognizedValue;
  final String? reason;
}

class IdentityDocument {
  const IdentityDocument({
    required this.documentType,
    this.surname,
    this.givenNames,
    this.documentNumber,
    this.nationality,
    this.issuingState,
    this.sex,
    this.dateOfBirth,
    this.issueDate,
    this.expiryDate,
    this.mrz,
    this.rawOcrText = '',
    this.fieldReview = const {},
    this.validationErrors = const [],
    this.warnings = const [],
  });

  final DocumentType documentType;
  final String? surname;
  final String? givenNames;
  final String? documentNumber;
  final String? nationality;
  final String? issuingState;
  final String? sex;
  final DateTime? dateOfBirth;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? mrz;

  /// Kept separate from normalized fields and never sent to logs or exports.
  final String rawOcrText;
  final Map<IdentityField, FieldReview> fieldReview;
  final List<String> validationErrors;
  final List<String> warnings;

  IdentityDocument copyWith({
    String? surname,
    String? givenNames,
    String? documentNumber,
    String? nationality,
    String? issuingState,
    String? sex,
    DateTime? dateOfBirth,
    DateTime? issueDate,
    DateTime? expiryDate,
  }) {
    return IdentityDocument(
      documentType: documentType,
      surname: surname ?? this.surname,
      givenNames: givenNames ?? this.givenNames,
      documentNumber: documentNumber ?? this.documentNumber,
      nationality: nationality ?? this.nationality,
      issuingState: issuingState ?? this.issuingState,
      sex: sex ?? this.sex,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      issueDate: issueDate ?? this.issueDate,
      expiryDate: expiryDate ?? this.expiryDate,
      mrz: mrz,
      rawOcrText: rawOcrText,
      fieldReview: fieldReview,
      validationErrors: validationErrors,
      warnings: warnings,
    );
  }
}

String dateToIso(DateTime? date) {
  if (date == null) return '';
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
