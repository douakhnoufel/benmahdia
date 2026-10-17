/// An Algerian mobile number (05, 06 or 07), kept in E.164 form
/// (`+213` and 9 digits) so the app and the server agree on one spelling.
class PhoneNumber {
  const PhoneNumber._(this.e164);

  /// Reads what a patient typed: `0550 12 34 56`, `550123456`,
  /// `+213 550 12 34 56`, `00213…`, with spaces, dashes or Arabic-Indic
  /// digits. Returns null for anything that is not an Algerian mobile.
  static PhoneNumber? tryParse(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final c = String.fromCharCode(rune);
      final eastern = _easternDigits.indexOf(c);
      if (eastern >= 0) {
        buffer.write(eastern);
      } else if (RegExp(r'[0-9+]').hasMatch(c)) {
        buffer.write(c);
      } else if (!RegExp(r'[\s\-.()\u200e\u200f\u2066-\u2069]').hasMatch(c)) {
        return null;
      }
    }
    var digits = buffer.toString();
    if (digits.startsWith('+213')) {
      digits = digits.substring(4);
    } else if (digits.startsWith('00213')) {
      digits = digits.substring(5);
    } else if (digits.startsWith('213') && digits.length == 12) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (!RegExp(r'^[567]\d{8}$').hasMatch(digits)) return null;
    return PhoneNumber._('+213$digits');
  }

  /// `+213550123456`, as sent to the server.
  final String e164;

  /// `0550 12 34 56`, as shown to the patient. Wrap it in [TextDirection.ltr]
  /// (or [isolated]) inside Arabic text.
  String get national {
    final n = '0${e164.substring(4)}';
    return '${n.substring(0, 4)} ${n.substring(4, 6)} '
        '${n.substring(6, 8)} ${n.substring(8)}';
  }

  /// [national] inside a left-to-right isolate, for use in a sentence.
  String get isolated => '\u2066$national\u2069';

  static const _easternDigits = '٠١٢٣٤٥٦٧٨٩';

  @override
  bool operator ==(Object other) => other is PhoneNumber && other.e164 == e164;

  @override
  int get hashCode => e164.hashCode;

  @override
  String toString() => e164;
}
