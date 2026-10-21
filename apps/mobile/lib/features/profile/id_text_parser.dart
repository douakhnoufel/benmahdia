/// What could be read from the text of an ID card photo.
class ScannedId {
  const ScannedId({this.idNumber, this.birthDate});

  final String? idNumber;
  final DateTime? birthDate;

  bool get isEmpty => idNumber == null && birthDate == null;
}

/// Eastern Arabic and Persian digits → 0-9.
String asciiDigits(String text) {
  final out = StringBuffer();
  for (final unit in text.runes) {
    if (unit >= 0x0660 && unit <= 0x0669) {
      out.writeCharCode(0x30 + unit - 0x0660);
    } else if (unit >= 0x06F0 && unit <= 0x06F9) {
      out.writeCharCode(0x30 + unit - 0x06F0);
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString();
}

/// Trim, drop spaces and separators, upper case: the form the API checks.
String normalizeIdNumber(String raw) =>
    asciiDigits(raw).replaceAll(RegExp(r'[\s\-./]'), '').toUpperCase();

final _yearFirst = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})');
final _dayFirst = RegExp(r'(\d{1,2})[-./](\d{1,2})[-./](\d{4})');

DateTime? _valid(int y, int m, int d, DateTime today) {
  if (y < 1900) return null;
  final date = DateTime(y, m, d);
  if (date.year != y || date.month != m || date.day != d) return null;
  return date.isAfter(DateTime(today.year, today.month, today.day))
      ? null
      : date;
}

/// A date typed as `1990-05-17` or `17/05/1990` (`-`, `/` or `.`), or null
/// when it is not a real date between 1900 and [today].
DateTime? parseDate(String text, {required DateTime today}) {
  final t = asciiDigits(text).trim();
  final a = RegExp('^${_yearFirst.pattern}\$').firstMatch(t);
  if (a != null) {
    return _valid(
      int.parse(a[1]!),
      int.parse(a[2]!),
      int.parse(a[3]!),
      today,
    );
  }
  final b = RegExp('^${_dayFirst.pattern}\$').firstMatch(t);
  if (b != null) {
    return _valid(
      int.parse(b[3]!),
      int.parse(b[2]!),
      int.parse(b[1]!),
      today,
    );
  }
  return null;
}

/// Picks the ID number and birth date out of recognised card text. The card
/// also carries issue and expiry dates, which are later than the birth
/// date, so the earliest valid date wins. The number is the first run of 9
/// to 18 digits left once the dates are removed (the national number has 18).
/// The name is left to the patient: reading names from a card is unreliable.
ScannedId parseIdText(String text, {required DateTime today}) {
  var rest = asciiDigits(text);
  final dates = <DateTime>[];
  for (final pattern in [_yearFirst, _dayFirst]) {
    rest = rest.replaceAllMapped(pattern, (m) {
      final date = pattern == _yearFirst
          ? _valid(
              int.parse(m[1]!),
              int.parse(m[2]!),
              int.parse(m[3]!),
              today,
            )
          : _valid(
              int.parse(m[3]!),
              int.parse(m[2]!),
              int.parse(m[1]!),
              today,
            );
      if (date != null) dates.add(date);
      return ' ';
    });
  }
  dates.sort();
  final runs = RegExp(r'\d{9,18}').allMatches(rest).map((m) => m[0]!).toList();
  final number = runs.where((r) => r.length == 18).firstOrNull ?? runs.firstOrNull;
  return ScannedId(idNumber: number, birthDate: dates.firstOrNull);
}
