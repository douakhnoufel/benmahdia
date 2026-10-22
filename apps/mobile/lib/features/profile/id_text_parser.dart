/// What could be read from an ID card or a passport.
class ScannedId {
  const ScannedId({this.idNumber, this.birthDate, this.fullName, this.issuer});

  final String? idNumber;
  final DateTime? birthDate;

  /// Only from a passport's machine-readable lines, surname first.
  final String? fullName;

  /// Issuing country of a passport (ICAO code, `DZA` for Algeria).
  final String? issuer;

  bool get isEmpty => idNumber == null && birthDate == null;

  @override
  bool operator ==(Object other) =>
      other is ScannedId &&
      other.idNumber == idNumber &&
      other.birthDate == birthDate &&
      other.fullName == fullName &&
      other.issuer == issuer;

  @override
  int get hashCode => Object.hash(idNumber, birthDate, fullName, issuer);
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
    return _valid(int.parse(a[1]!), int.parse(a[2]!), int.parse(a[3]!), today);
  }
  final b = RegExp('^${_dayFirst.pattern}\$').firstMatch(t);
  if (b != null) {
    return _valid(int.parse(b[3]!), int.parse(b[2]!), int.parse(b[1]!), today);
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
          ? _valid(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), today)
          : _valid(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!), today);
      if (date != null) dates.add(date);
      return ' ';
    });
  }
  dates.sort();
  final runs = RegExp(r'\d{9,18}').allMatches(rest).map((m) => m[0]!).toList();
  final number =
      runs.where((r) => r.length == 18).firstOrNull ?? runs.firstOrNull;
  return ScannedId(idNumber: number, birthDate: dates.firstOrNull);
}

/// ICAO 9303 check digit: weights 7, 3, 1; digits as themselves, A–Z as
/// 10–35, the filler `<` as 0.
int mrzCheckDigit(String field) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < field.length; i++) {
    final c = field.codeUnitAt(i);
    final int value;
    if (c >= 0x30 && c <= 0x39) {
      value = c - 0x30;
    } else if (c >= 0x41 && c <= 0x5A) {
      value = c - 0x41 + 10;
    } else {
      value = 0;
    }
    sum += value * weights[i % 3];
  }
  return sum % 10;
}

/// One OCR line as MRZ characters: upper case, no spaces, `«` read as `<<`.
String _mrzLine(String line) => line
    .toUpperCase()
    .replaceAll('«', '<<')
    .replaceAll(RegExp('[‹＜]'), '<')
    .replaceAll(RegExp(r'[^A-Z0-9<]'), '');

/// Letters OCR often reads instead of digits, in fields that are only digits.
String _digitsOnly(String field) {
  const fixes = {
    'O': '0', 'Q': '0', 'D': '0', 'I': '1', 'L': '1', //
    'Z': '2', 'S': '5', 'G': '6', 'B': '8',
  };
  return field.split('').map((c) => fixes[c] ?? c).join();
}

final _td3Second = RegExp(r'^[A-Z0-9<]{9}[0-9][A-Z<]{3}[0-9]{7}');

/// Reads a passport's two machine-readable lines (ICAO 9303, TD3): the
/// number, the birth date and the name. Null unless both check digits match,
/// so a misread line is never used.
ScannedId? parseMrz(String text, {required DateTime today}) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map(_mrzLine)
      .where((l) => l.length >= 28)
      .toList();
  for (var i = 0; i < lines.length; i++) {
    var second = lines[i];
    if (second.length < 44) second = second.padRight(44, '<');
    second =
        second.substring(0, 9) +
        _digitsOnly(second.substring(9, 10)) +
        second.substring(10, 13) +
        _digitsOnly(second.substring(13, 20)) +
        second.substring(20);
    if (!_td3Second.hasMatch(second)) continue;

    final number = second.substring(0, 9);
    final birth = second.substring(13, 19);
    if (mrzCheckDigit(number) != int.parse(second[9])) continue;
    if (mrzCheckDigit(birth) != int.parse(second[19])) continue;

    final yy = int.parse(birth.substring(0, 2));
    final mm = int.parse(birth.substring(2, 4));
    final dd = int.parse(birth.substring(4, 6));
    final year = yy > today.year % 100 ? 1900 + yy : 2000 + yy;
    final date = DateTime(year, mm, dd);
    if (date.month != mm || date.day != dd || date.isAfter(today)) continue;

    String? name;
    var issuer = second.substring(10, 13).replaceAll('<', '');
    final first = i > 0 ? lines[i - 1] : '';
    if (first.startsWith('P') && first.length > 5) {
      final state = first.substring(2, 5).replaceAll('<', '');
      if (state.length == 3) issuer = state;
      final parts = first
          .substring(5)
          .split('<<')
          .map((p) => p.replaceAll('<', ' ').trim())
          .where((p) => p.isNotEmpty)
          .take(2)
          .toList();
      if (parts.isNotEmpty) name = parts.join(' ');
    }
    return ScannedId(
      idNumber: number.replaceAll('<', ''),
      birthDate: date,
      fullName: name,
      issuer: issuer,
    );
  }
  return null;
}
