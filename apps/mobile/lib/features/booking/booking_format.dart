import '../../l10n/app_localizations.dart';

// Dates and times for the booking screens. Weekday and month names come
// from the ARB files (Algerian month names in Arabic); digits stay Latin, as
// used in Algeria.

const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

String _weekdayKey(DateTime d) => _weekdays[d.weekday - 1];

String _monthKey(DateTime d) => 'm${d.month}';

String _two(int n) => n.toString().padLeft(2, '0');

/// "09:30".
String hhmm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// "09:30 – 09:45". Show it with [TextDirection.ltr].
String timeRange(DateTime start, DateTime end) =>
    '${hhmm(start)} – ${hhmm(end)}';

/// "14:52" for a countdown.
String mmss(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  return '${_two(s ~/ 60)}:${_two(s % 60)}';
}

extension BookingDates on AppLocalizations {
  /// "الأحد 18 أكتوبر" / "dimanche 18 octobre".
  String longDate(DateTime d) =>
      bookDateLong(bookWeekday(_weekdayKey(d)), d.day, bookMonth(_monthKey(d)));

  /// "أحد" / "dim.".
  String shortWeekday(DateTime d) => bookWeekdayShort(_weekdayKey(d));

  /// "أكتوبر" / "octobre".
  String month(DateTime d) => bookMonth(_monthKey(d));
}
