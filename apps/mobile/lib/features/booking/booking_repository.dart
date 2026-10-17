import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import 'api_booking_repository.dart';
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

  /// The ways a patient can pay for this clinic's appointments right now.
  Set<PaymentMethod> get methods;

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

  /// Books the held slot with [method]. With [cardsUseCheckout], only for
  /// payment at the clinic: cards go through [checkout].
  Future<Appointment> confirm(Hold hold, PaymentMethod method);

  /// Whether card payments open the Chargily checkout and wait for the
  /// server's confirmation (PRD 4.4) instead of [confirm].
  bool get cardsUseCheckout;

  /// Opens a Chargily checkout for [hold] and returns the page to show.
  Future<Uri> checkout(Hold hold, PaymentMethod method);

  /// The booked appointment once the server confirmed the payment, or null
  /// while it is still waiting. Throws [SlotUnavailable] if the slot was
  /// given back (payment failed or time ran out).
  Future<Appointment?> paid(Hold hold);

  /// This patient's appointments, oldest first.
  Future<List<Appointment>> appointments();

  /// Cancels [appointment]. Throws [TooLateToCancel] inside the notice.
  Future<Appointment> cancel(Appointment appointment);
}

/// The booking API when `API_BASE_URL` is set, otherwise sample data.
final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  if (apiBaseUrl.isEmpty) return FakeBookingRepository();
  final auth = ref.read(authRepositoryProvider);
  return ApiBookingRepository(
    baseUrl: Uri.parse(apiBaseUrl),
    token: () => ref.read(sessionProvider)?.accessToken,
    refresh: () async {
      final session = ref.read(sessionProvider);
      if (session == null) return false;
      try {
        final AuthSession fresh = await auth.refresh(session);
        ref.read(sessionProvider.notifier).set(fresh);
        return true;
      } on AuthFailure {
        return false;
      }
    },
  );
});
