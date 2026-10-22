class ParsedDate {
  const ParsedDate({
    required this.value,
    required this.originalValue,
    this.isAmbiguous = false,
    this.error,
  });

  final DateTime? value;
  final String originalValue;
  final bool isAmbiguous;
  final String? error;
}

/// Parses full-year ISO dates and unambiguous numeric day/month dates.
/// Two-digit years and dates where both day/month orders are plausible remain
/// unresolved so a user can review them without an inferred century/order.
///
/// With [dayFirst] (Algerian documents print day/month/year) a numeric date
/// such as 05/03/1990 is read as 5 March 1990 instead of being left
/// ambiguous. Two-digit years stay unresolved either way.
ParsedDate parseDocumentDate(String input, {bool dayFirst = false}) {
  final text = input.trim();
  if (text.isEmpty) {
    return ParsedDate(value: null, originalValue: input);
  }

  final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(text);
  if (iso != null) {
    return _checked(
      int.parse(iso[1]!),
      int.parse(iso[2]!),
      int.parse(iso[3]!),
      text,
    );
  }

  final numeric = RegExp(
    r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})$',
  ).firstMatch(text);
  if (numeric == null) {
    return ParsedDate(
      value: null,
      originalValue: input,
      isAmbiguous: RegExp(r'^\d{1,2}[-/.]\d{1,2}[-/.]\d{2}$').hasMatch(text),
      error: 'Unsupported or incomplete date format.',
    );
  }

  final first = int.parse(numeric[1]!);
  final second = int.parse(numeric[2]!);
  final yearText = numeric[3]!;
  if (yearText.length == 2) {
    return ParsedDate(
      value: null,
      originalValue: input,
      isAmbiguous: true,
      error: 'Two-digit year has no verified century.',
    );
  }

  if (!dayFirst && first <= 12 && second <= 12) {
    return ParsedDate(
      value: null,
      originalValue: input,
      isAmbiguous: true,
      error: 'Day and month order is ambiguous.',
    );
  }

  final day = dayFirst || first > 12 ? first : second;
  final month = dayFirst || first > 12 ? second : first;
  return _checked(int.parse(yearText), month, day, input);
}

ParsedDate _checked(int year, int month, int day, String original) {
  final date = DateTime(year, month, day);
  if (date.year != year ||
      date.month != month ||
      date.day != day ||
      year < 1900 ||
      year > 9999) {
    return ParsedDate(
      value: null,
      originalValue: original,
      error: 'Date is not a valid calendar date.',
    );
  }
  return ParsedDate(value: date, originalValue: original);
}
