import '../models/identity_document.dart';
import 'date_parser.dart';

/// A label-driven rule set. A deployment can add a layout only after it has
/// been checked against lawfully obtained samples for that card generation.
class IdLayoutTemplate {
  const IdLayoutTemplate({
    required this.name,
    required this.surnameLabels,
    required this.givenNameLabels,
    required this.documentNumberLabels,
    required this.birthDateLabels,
    this.issueDateLabels = const [],
    this.expiryDateLabels = const [],
  });

  final String name;
  final List<String> surnameLabels;
  final List<String> givenNameLabels;
  final List<String> documentNumberLabels;
  final List<String> birthDateLabels;
  final List<String> issueDateLabels;
  final List<String> expiryDateLabels;
}

/// These label phrases are generic French/Arabic cues, not a claim about a
/// particular Algerian card generation. No field is selected by screen order.
const genericAlgerianIdLabels = IdLayoutTemplate(
  name: 'generic-labeled-fields',
  surnameLabels: ['NOM', 'SURNAME', 'اللقب'],
  givenNameLabels: ['PRENOM', 'PRENOMS', 'GIVEN NAME', 'GIVEN NAMES', 'الاسم'],
  documentNumberLabels: [
    'NIN',
    'NUMERO D IDENTIFICATION NATIONAL',
    'N° DE DOCUMENT',
    'NO DE DOCUMENT',
    'NUMERO DE DOCUMENT',
    'NUMERO DE CARTE',
    'رقم التعريف الوطني',
  ],
  birthDateLabels: [
    'DATE DE NAISSANCE',
    'NEE LE',
    'NE LE',
    'BIRTH DATE',
    'تاريخ الميلاد',
  ],
  issueDateLabels: [
    'DATE DE DELIVRANCE',
    'DELIVRE LE',
    'ISSUED ON',
    'تاريخ الإصدار',
  ],
  expiryDateLabels: [
    'DATE D EXPIRATION',
    'VALABLE JUSQU AU',
    'EXPIRY DATE',
    'تاريخ الانتهاء',
  ],
);

class AlgerianIdParser {
  const AlgerianIdParser({this.templates = const [genericAlgerianIdLabels]});

  final List<IdLayoutTemplate> templates;

  IdentityDocument parse(String rawText) {
    final lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return const IdentityDocument(
        documentType: DocumentType.nationalId,
        rawOcrText: '',
        warnings: [
          'No text was recognized. Retake the image or enter fields manually.',
        ],
      );
    }

    for (final template in templates) {
      final result = _parseWithTemplate(rawText, lines, template);
      if (_hasAnyField(result)) return result;
    }

    return IdentityDocument(
      documentType: DocumentType.nationalId,
      rawOcrText: rawText,
      warnings: const [
        'No configured label template matched this image. Fields were left unknown.',
        'Algerian card layouts need validation with lawfully obtained samples.',
      ],
    );
  }

  IdentityDocument _parseWithTemplate(
    String rawText,
    List<String> lines,
    IdLayoutTemplate template,
  ) {
    final warnings = <String>[
      'Field labels are generic rules and have not been validated against a genuine Algerian card sample.',
    ];
    final review = <IdentityField, FieldReview>{};
    final allLabels = [
      ...template.surnameLabels,
      ...template.givenNameLabels,
      ...template.documentNumberLabels,
      ...template.birthDateLabels,
      ...template.issueDateLabels,
      ...template.expiryDateLabels,
    ];
    _LabeledValue find(List<String> labels) =>
        _uniqueLabeledValue(lines, labels, allLabels);
    final surname = find(template.surnameLabels);
    final givenNames = find(template.givenNameLabels);
    final documentCandidates = find(template.documentNumberLabels);
    final birth = find(template.birthDateLabels);
    final issue = find(template.issueDateLabels);
    final expiry = find(template.expiryDateLabels);

    for (final field in [
      surname,
      givenNames,
      documentCandidates,
      birth,
      issue,
      expiry,
    ]) {
      if (field.ambiguous) warnings.add(field.warning!);
    }

    final parsedBirth = _dateValue(
      birth,
      IdentityField.dateOfBirth,
      review,
      warnings,
    );
    final parsedIssue = _dateValue(
      issue,
      IdentityField.issueDate,
      review,
      warnings,
    );
    final parsedExpiry = _dateValue(
      expiry,
      IdentityField.expiryDate,
      review,
      warnings,
    );

    _addReview(review, IdentityField.surname, surname);
    _addReview(review, IdentityField.givenNames, givenNames);
    _addReview(review, IdentityField.documentNumber, documentCandidates);

    final errors = <String>[];
    String? documentNumber;
    if (!documentCandidates.ambiguous &&
        documentCandidates.value != null &&
        documentCandidates.value!.isNotEmpty) {
      final numberRuns = RegExp(r'\d+')
          .allMatches(documentCandidates.value!)
          .map((match) => match.group(0)!)
          .toList();
      if (numberRuns.length > 1) {
        errors.add('More than one number followed an identity-number label.');
        warnings.add('Document number is uncertain; edit it manually.');
      } else {
        documentNumber = documentCandidates.value!.trim();
      }
    }

    if (documentCandidates.ambiguous) {
      errors.add('Multiple candidate identity-number labels were recognized.');
    }

    return IdentityDocument(
      documentType: DocumentType.nationalId,
      surname: surname.ambiguous ? null : _nonEmpty(surname.value),
      givenNames: givenNames.ambiguous ? null : _nonEmpty(givenNames.value),
      documentNumber: documentNumber,
      dateOfBirth: parsedBirth,
      issueDate: parsedIssue,
      expiryDate: parsedExpiry,
      rawOcrText: rawText,
      fieldReview: review,
      validationErrors: errors,
      warnings: warnings,
    );
  }

  bool _hasAnyField(IdentityDocument result) =>
      result.surname != null ||
      result.givenNames != null ||
      result.documentNumber != null ||
      result.dateOfBirth != null ||
      result.issueDate != null ||
      result.expiryDate != null ||
      result.validationErrors.isNotEmpty;

  _LabeledValue _uniqueLabeledValue(
    List<String> lines,
    List<String> labels,
    List<String> allLabels,
  ) {
    if (labels.isEmpty) return const _LabeledValue(null);
    final candidates = <String>[];
    final orderedLabels = [...labels]
      ..sort((first, second) => second.length.compareTo(first.length));
    for (var index = 0; index < lines.length; index++) {
      final normalizedLine = _normalizeLabelText(lines[index]);
      for (final label in orderedLabels) {
        final match = _labelPattern(label).firstMatch(normalizedLine);
        if (match == null) continue;

        var value = match.group(1)!.trim();
        if (value.isEmpty && index + 1 < lines.length) {
          // A value is associated only with a preceding explicit field label.
          value = lines[index + 1].trim();
          if (_lineStartsWithKnownLabel(value, allLabels)) value = '';
        }
        if (value.isNotEmpty) candidates.add(value);
        break;
      }
    }

    final unique = candidates.toSet().toList();
    if (unique.length > 1) {
      return _LabeledValue(
        null,
        ambiguous: true,
        warning:
            'More than one candidate value matched a document field label.',
      );
    }
    return _LabeledValue(unique.isEmpty ? null : unique.single);
  }

  bool _lineStartsWithKnownLabel(String line, List<String> labels) {
    final normalizedLine = _normalizeLabelText(line);
    return labels.any((label) => _labelPattern(label).hasMatch(normalizedLine));
  }

  /// A label must be followed by a separator, whitespace or the end of the
  /// line, so "NOM" does not match "NOMBRE" or "NIN" does not match "NINA".
  RegExp _labelPattern(String label) => RegExp(
    r'^\s*' +
        RegExp.escape(_normalizeLabelText(label)) +
        r'(?:\s*[:：-]\s*|\s+|$)(.*)$',
    caseSensitive: false,
  );

  DateTime? _dateValue(
    _LabeledValue labeled,
    IdentityField field,
    Map<IdentityField, FieldReview> review,
    List<String> warnings,
  ) {
    if (labeled.ambiguous || labeled.value == null) return null;
    final rawValue = labeled.value!;
    final parsed = parseDocumentDate(_asciiDigits(rawValue), dayFirst: true);
    review[field] = FieldReview(
      level: parsed.value == null
          ? ReviewLevel.uncertain
          : ReviewLevel.reliable,
      originalRecognizedValue: rawValue,
      reason: parsed.error,
    );
    if (parsed.error != null) warnings.add(parsed.error!);
    return parsed.value;
  }

  void _addReview(
    Map<IdentityField, FieldReview> review,
    IdentityField field,
    _LabeledValue labeled,
  ) {
    if (labeled.ambiguous) {
      review[field] = const FieldReview(
        level: ReviewLevel.uncertain,
        reason: 'Multiple labeled candidates were found.',
      );
    } else if (labeled.value != null) {
      review[field] = FieldReview(
        level: ReviewLevel.uncertain,
        originalRecognizedValue: labeled.value,
      );
    }
  }

  String _normalizeLabelText(String input) => input
      .toUpperCase()
      .replaceAll(RegExp(r'[ÉÈÊË]'), 'E')
      .replaceAll(RegExp(r'[ÀÂÄ]'), 'A')
      .replaceAll(RegExp(r'[ÎÏ]'), 'I')
      .replaceAll(RegExp(r'[ÔÖ]'), 'O')
      .replaceAll(RegExp(r'[ÙÛÜ]'), 'U')
      .replaceAll(RegExp(r'[\s\u00a0]+'), ' ')
      .trim();

  String _asciiDigits(String input) {
    final result = StringBuffer();
    for (final codePoint in input.runes) {
      if (codePoint >= 0x0660 && codePoint <= 0x0669) {
        result.writeCharCode(0x30 + codePoint - 0x0660);
      } else if (codePoint >= 0x06F0 && codePoint <= 0x06F9) {
        result.writeCharCode(0x30 + codePoint - 0x06F0);
      } else {
        result.writeCharCode(codePoint);
      }
    }
    return result.toString();
  }

  String? _nonEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}

class _LabeledValue {
  const _LabeledValue(this.value, {this.ambiguous = false, this.warning});

  final String? value;
  final bool ambiguous;
  final String? warning;
}
