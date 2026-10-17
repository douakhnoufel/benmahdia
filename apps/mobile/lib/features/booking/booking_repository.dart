import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'booking_models.dart';
import 'fake_booking_repository.dart';

/// Everything the booking screens need from the clinic's agenda. The server
/// is the authority: it prevents double booking, holds and releases slots,
/// and confirms paid appointments from Chargily's webhook (PRD 4.3, 4.4).
abstract interface class BookingRepository {
  /// Current clinic time. Injected so tests control "now".
  DateTime now();

  /// Shortest notice to book or cancel (PRD 4.3: 24 h).
  Duration get notice;

  /// How far ahead a patient can book (PRD 4.3: 60 days).
  Duration get horizon;

  /// How long a slot stays held while the patient pays.
  Duration get holdFor;

  Future<List<Doctor>> doctors();

  /// The bookable days for [doctor], from today until [horizon].
  Future<List<DaySlots>> calendar(Doctor doctor);

  /// The suggested next visit, about 30 days after the latest one (PRD 4.3),
  /// or null when the patient has no visit yet.
  Future<FollowUp?> followUp();

  /// Reserves [start] for this patient. Throws [SlotUnavailable] if it was
  /// taken first.
  Future<Hold> hold(Doctor doctor, DateTime start);

  /// Gives a held slot back, e.g. when the patient leaves or time runs out.
  Future<void> release(Hold hold);

  /// Books the held slot with [method].
  Future<Appointment> confirm(Hold hold, PaymentMethod method);

  /// This patient's appointments, oldest first.
  Future<List<Appointment>> appointments();

  /// Cancels [appointment]. Throws [TooLateToCancel] inside the notice.
  Future<Appointment> cancel(Appointment appointment);
}

// TODO(booking): replace with the API client once the backend exists.
final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => FakeBookingRepository(),
);
