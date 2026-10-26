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

/// Small goals (PRD 5.6), in days of the current streak; after the last
/// step the milestone ladder takes over, then every year.
const goalSteps = [1, 3, 7, 14, 28];
const _laterGoals = [60, 90, 180, 365];

/// The step the app picks by itself: the first one not reached yet.
int nextGoal(int days) {
  for (final g in [...goalSteps, ..._laterGoals]) {
    if (days < g) return g;
  }
  return (days ~/ 365 + 1) * 365;
}

/// The patient's own goal while it is still ahead, else the next step.
int currentGoal(int days, int? chosen) =>
    chosen != null && days < chosen ? chosen : nextGoal(days);

/// Kinds of addiction the doctor can set (PRD 3).
enum AddictionType {
  opioids,
  cannabis,
  alcohol,
  tobacco,
  pills,
  stimulants,
  gambling,
  other,
}

/// How an addiction is tracked (PRD 5.6). Without one, tracking is
/// generic: the daily check rates craving only.
enum SubstanceProfile {
  nicotine,
  thc,
  pregabalin,
  buprenorphine,
  cocaine,
  amphetamines,
}

/// One signal a profile's daily check rates 1-5 (higher = harder).
class SignalSpec {
  const SignalSpec({required this.key, required this.label});

  final String key;
  final LocalizedText label;
}

/// A short "what to expect" note for an early day, written by the clinic.
class EarlyNote {
  const EarlyNote({required this.day, required this.text});

  final int day;
  final LocalizedText text;
}

/// What one substance profile tracks, from the server's catalog.
class ProfileSpec {
  const ProfileSpec({
    required this.profile,
    required this.type,
    required this.name,
    required this.signals,
    required this.notes,
  });

  final SubstanceProfile profile;
  final AddictionType type;
  final LocalizedText name;
  final List<SignalSpec> signals;
  final List<EarlyNote> notes;

  /// The note for the stage the patient is at: the latest one reached, shown
  /// for a week after its day.
  EarlyNote? noteFor(int days) {
    EarlyNote? found;
    for (final n in notes) {
      if (n.day <= days) found = n;
    }
    return found != null && days - found.day < 7 ? found : null;
  }
}

/// One day's check for one addiction (PRD 5.6).
class AddictionCheck {
  const AddictionCheck({
    required this.addictionId,
    required this.day,
    required this.used,
    required this.craving,
    this.signals = const {},
  });

  final String addictionId;

  /// A [dayOf] date.
  final DateTime day;
  final bool used;

  /// 1-5, as are the [signals] ratings.
  final int craving;
  final Map<String, int> signals;
}

/// The patient's checks and the days on which every addiction was checked.
typedef CheckHistory = ({List<AddictionCheck> checks, Set<DateTime> doneDays});

/// Good habits from the clinic's list, or one in the patient's own words.
enum HabitKind { sport, brushTeeth, water, reading, callFamily, sleep, custom }

/// A good habit the patient keeps instead of using (PRD 5.6).
class Habit {
  const Habit({
    required this.id,
    required this.kind,
    this.text,
    this.reminder,
    this.days = const {},
  });

  final String id;
  final HabitKind kind;

  /// The patient's own words, for [HabitKind.custom] only.
  final String? text;
  final DayTime? reminder;

  /// Days it was done, as [dayOf] dates.
  final Set<DateTime> days;

  Habit copyWith({
    DayTime? reminder,
    bool clearReminder = false,
    Set<DateTime>? days,
  }) => Habit(
    id: id,
    kind: kind,
    text: text,
    reminder: clearReminder ? null : reminder ?? this.reminder,
    days: days ?? this.days,
  );
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
    this.profile,
    this.goalDays,
  });

  final String id;
  final AddictionType type;

  /// How it is tracked (PRD 5.6); null = generic.
  final SubstanceProfile? profile;

  /// The small goal the patient chose; null lets the app pick.
  final int? goalDays;

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

  /// What the circle fills toward now.
  int goal(DateTime now) => currentGoal(days(now), goalDays);

  Addiction withGoal(int? days) => Addiction(
    id: id,
    type: type,
    profile: profile,
    substance: substance,
    reviewed: reviewed,
    start: start,
    longestPastDays: longestPastDays,
    pastDays: pastDays,
    goalDays: days,
  );

  /// The counter after a relapse at [at] (never before the current start).
  Addiction relapsed(DateTime at) {
    final when = at.isBefore(start) ? start : at;
    // The goal goes back to the first small step (PRD 5.6).
    return Addiction(
      id: id,
      type: type,
      profile: profile,
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

/// Recovery opens after the first confirmed (paid) appointment (PRD 5); until
/// then the tab shows a locked state with a Book button.
class RecoveryLocked extends RecoveryUnavailable {
  const RecoveryLocked();
}
