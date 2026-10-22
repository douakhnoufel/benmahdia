/// Text the clinic writes in both app languages (quotes, medication labels,
/// the clinic's address).
class LocalizedText {
  const LocalizedText({required this.ar, required this.fr});

  final String ar;
  final String fr;

  String of(String languageCode) => languageCode == 'ar' ? ar : fr;
}

/// Day counts that fill a sobriety circle (PRD 5.1): then every year.
const milestones = [1, 3, 7, 14, 30, 60, 90, 180, 365];

/// The next milestone after [days] (the ring's goal).
int nextMilestone(int days) {
  for (final m in milestones) {
    if (days < m) return m;
  }
  return (days ~/ 365 + 1) * 365;
}

/// Kinds of addiction the doctor can set (PRD 3).
enum AddictionType {
  opioids,
  cannabis,
  alcohol,
  tobacco,
  pills,
  gambling,
  other,
}

/// One addiction the patient tracks, with its own day counter (PRD 5.1).
/// The patient adds it (type, substance, clean-since date) and the doctor
/// reviews it; after that only a relapse moves the counter. A relapse
/// restarts [start] but keeps the past: the longest streak and the total of
/// days without use are never erased.
class Addiction {
  const Addiction({
    required this.id,
    required this.type,
    required this.start,
    required this.longestPastDays,
    required this.pastDays,
    this.substance,
    this.reviewed = true,
  });

  final String id;
  final AddictionType type;

  /// The exact product, in the patient's words (optional).
  final String? substance;

  /// Whether the doctor has checked what the patient entered.
  final bool reviewed;

  /// When the current streak began ("clean since").
  final DateTime start;

  /// Longest streak before the current one, in days.
  final int longestPastDays;

  /// Days without use in all earlier streaks.
  final int pastDays;

  int days(DateTime now) {
    final d = now.difference(start).inDays;
    return d < 0 ? 0 : d;
  }

  int longest(DateTime now) {
    final d = days(now);
    return d > longestPastDays ? d : longestPastDays;
  }

  int total(DateTime now) => pastDays + days(now);

  /// The counter after a relapse at [at] (never before the current start).
  Addiction relapsed(DateTime at) {
    final when = at.isBefore(start) ? start : at;
    return Addiction(
      id: id,
      type: type,
      substance: substance,
      reviewed: reviewed,
      start: when,
      longestPastDays: longest(when),
      pastDays: total(when),
    );
  }
}

/// A calendar day without its time, for daily check-ins.
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// A time of day, e.g. the daily check-in reminder.
typedef DayTime = ({int hour, int minute});

/// Quote of the day (PRD 5.2).
class Quote {
  const Quote({required this.text, required this.source});

  final LocalizedText text;
  final LocalizedText source;
}

enum DoseStatus { due, taken, skipped }

/// One dose to take today, as the doctor set it (PRD 5.3).
class Dose {
  const Dose({
    required this.id,
    required this.name,
    required this.amount,
    required this.hour,
    required this.minute,
    required this.status,
    this.instruction,
  });

  final String id;
  final LocalizedText name;
  final LocalizedText amount;
  final LocalizedText? instruction;
  final int hour;
  final int minute;
  final DoseStatus status;

  Dose withStatus(DoseStatus status) => Dose(
    id: id,
    name: name,
    amount: amount,
    instruction: instruction,
    hour: hour,
    minute: minute,
    status: status,
  );
}

/// Opening hours of one stretch of a day, in minutes after midnight.
typedef OpenHours = ({int from, int to});

/// Where the practice is and how to reach it.
class ClinicInfo {
  const ClinicInfo({
    required this.name,
    required this.specialty,
    required this.address,
    required this.phones,
    required this.maps,
    required this.hours,
  });

  final LocalizedText name;
  final LocalizedText specialty;
  final LocalizedText address;

  /// International format, e.g. "+213 551 03 83 85".
  final List<String> phones;

  /// Opens the practice in Google Maps.
  final Uri maps;

  /// Opening hours by [DateTime.weekday] (1 = Monday); empty = closed.
  final Map<int, List<OpenHours>> hours;

  List<OpenHours> hoursOn(DateTime day) => hours[day.weekday] ?? const [];
}

/// The recovery server could not be reached or answered badly. The screens
/// show a retry message and keep what they had.
class RecoveryUnavailable implements Exception {
  const RecoveryUnavailable();
}
