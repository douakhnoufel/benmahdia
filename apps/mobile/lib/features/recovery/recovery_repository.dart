import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_recovery_repository.dart';
import 'recovery_models.dart';

/// What the recovery home needs (PRD 5): day counters, the quote of the day,
/// today's doses and the clinic's details.
abstract interface class RecoveryRepository {
  /// Current time. Injected so tests control "now".
  DateTime now();

  /// The addictions the patient tracks, one counter each.
  Future<List<Addiction>> addictions();

  /// Adds an addiction the patient entered; the doctor reviews it.
  Future<Addiction> addAddiction({
    required AddictionType type,
    required DateTime cleanSince,
    String? substance,
  });

  /// Restarts [addiction]'s counter from [at] (default now); the doctor is
  /// told (PRD 5.1).
  Future<Addiction> logRelapse(
    Addiction addiction, {
    String? note,
    DateTime? at,
  });

  Future<Quote> quoteOfDay();

  /// Today's doses, earliest first.
  Future<List<Dose>> todaysDoses();

  Future<Dose> markDose(Dose dose, DoseStatus status);

  Future<ClinicInfo> clinic();

  /// Days the patient ticked "today without use", as [dayOf] dates.
  Future<Set<DateTime>> checkIns();

  /// Ticks [day] (today) as a day without use.
  Future<void> checkIn(DateTime day);

  /// When the app reminds the patient to tick the day; null = no reminder.
  Future<DayTime?> reminder();

  Future<void> setReminder(DayTime? time);
}

/// Sample data until the recovery API exists (PRD 9: Addiction, Relapse,
/// Medication, DoseLog, Quote).
// TODO(recovery-api): use the API when `API_BASE_URL` is set, like booking.
final recoveryRepositoryProvider = Provider<RecoveryRepository>(
  (ref) => FakeRecoveryRepository(),
);
