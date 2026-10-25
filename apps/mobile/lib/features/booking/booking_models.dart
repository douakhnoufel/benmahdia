/// A clinic doctor patients can book. Price and slot length are set per
/// doctor by the super admin (PRD 4.3, 4.4).
class Doctor {
  const Doctor({
    required this.id,
    required this.nameAr,
    required this.nameFr,
    required this.initialsAr,
    required this.initialsFr,
    required this.slotMinutes,
    required this.priceDzd,
  });

  final String id;
  final String nameAr;
  final String nameFr;
  final String initialsAr;
  final String initialsFr;

  /// Length of one appointment, 10–15 minutes.
  final int slotMinutes;

  /// Price of one appointment in Algerian dinars.
  final int priceDzd;

  String name(String languageCode) => languageCode == 'ar' ? nameAr : nameFr;

  String initials(String languageCode) =>
      languageCode == 'ar' ? initialsAr : initialsFr;
}

/// One time on a doctor's agenda, in clinic time (Africa/Algiers).
class Slot {
  const Slot({required this.start, required this.free});

  final DateTime start;

  /// Whether this patient can book it: not taken, held, or too soon.
  final bool free;
}

/// Why a day offers no slots.
enum DayClosure { none, tooSoon, closed }

/// The slots of one day, or the reason there are none.
class DaySlots {
  const DaySlots({
    required this.day,
    required this.slots,
    this.closure = DayClosure.none,
  });

  final DateTime day;
  final List<Slot> slots;
  final DayClosure closure;

  bool get open => closure == DayClosure.none;

  bool get hasFree => slots.any((s) => s.free);
}

/// A slot reserved for this patient while they pay; released at
/// [expiresAt] if the payment is not completed (PRD 4.3).
class Hold {
  const Hold({
    required this.id,
    required this.doctor,
    required this.start,
    required this.end,
    required this.expiresAt,
  });

  final String id;
  final Doctor doctor;
  final DateTime start;
  final DateTime end;
  final DateTime expiresAt;
}

enum PaymentMethod {
  /// Edahabia card through Chargily Pay.
  edahabia,

  /// CIB card through Chargily Pay.
  cib,

  /// Paid at the clinic on the day; pilot only, confirmed by the doctor.
  clinic;

  bool get online => this != PaymentMethod.clinic;
}

/// PRD 4.3 statuses, as the patient sees them.
enum AppointmentStatus {
  awaitingPayment,
  confirmed,
  completed,
  cancelled,
  noShow,
}

class Appointment {
  const Appointment({
    required this.id,
    required this.doctor,
    required this.start,
    required this.end,
    required this.status,
    required this.priceDzd,
    required this.method,
    this.checkinCode,
  });

  final String id;
  final Doctor doctor;
  final DateTime start;
  final DateTime end;
  final AppointmentStatus status;
  final int priceDzd;
  final PaymentMethod method;

  /// The 6-character booking code the patient gives at the front desk
  /// (PRD 4.3). The server sends it only once the appointment is confirmed.
  final String? checkinCode;

  /// Whether it still lies ahead and is not cancelled.
  bool isUpcoming(DateTime now) =>
      start.isAfter(now) &&
      (status == AppointmentStatus.confirmed ||
          status == AppointmentStatus.awaitingPayment);

  Appointment withStatus(AppointmentStatus status) => Appointment(
    id: id,
    doctor: doctor,
    start: start,
    end: end,
    status: status,
    priceDzd: priceDzd,
    method: method,
    checkinCode: checkinCode,
  );
}

/// The next visit the app suggests: [days] days after the patient's latest
/// visit. The patient may still book an earlier or later day, and it costs
/// the same as any appointment.
class FollowUp {
  const FollowUp({required this.after, required this.day, required this.days});

  /// The visit the follow-up counts from.
  final Appointment after;

  /// The suggested day, at midnight clinic time.
  final DateTime day;

  /// Days between [after] and [day].
  final int days;

  /// Whether the suggested day has already gone by on [now].
  bool overdueOn(DateTime now) =>
      day.isBefore(DateTime(now.year, now.month, now.day));
}

/// Someone else took the slot first.
class SlotUnavailable implements Exception {
  const SlotUnavailable();
}

/// The appointment is too close to be cancelled from the app.
class TooLateToCancel implements Exception {
  const TooLateToCancel();
}

/// The booking server could not be reached or answered unexpectedly.
class BookingUnavailable implements Exception {
  const BookingUnavailable();
}

/// Why the server refused a booking or payment action (its error `code`).
enum BookingRefusal {
  /// `not_verified`: the ID is not approved yet.
  notVerified,

  /// `token_invalid`, `not_authenticated`: the session ran out.
  signedOut,

  /// `forbidden`: this account may not do this.
  forbidden,

  /// `doctor_not_found`.
  doctorNotFound,

  /// `payment_method_unavailable`.
  paymentMethodUnavailable,

  /// `payments_unavailable`: Chargily could not be reached.
  paymentsUnavailable,

  /// `not_cancellable`: only a confirmed appointment can be cancelled.
  notCancellable,
}

/// The server answered and refused, for [reason]. It is a
/// [BookingUnavailable] so every caller still handles it, but the screens
/// say why instead of "check your connection".
class BookingRefused extends BookingUnavailable {
  const BookingRefused(this.reason);

  final BookingRefusal reason;
}
