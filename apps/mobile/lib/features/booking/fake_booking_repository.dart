import 'booking_models.dart';
import 'booking_repository.dart';

/// In-memory stand-in for the booking API until the backend exists. It
/// follows the rules the server will enforce: 24 h notice, booking up to
/// 60 days ahead, 15-minute slots, a 15-minute hold, no double booking, no
/// consultations on Fridays, and a follow-up suggested 30 days after the
/// latest visit. The data is sample data, not real patients.
class FakeBookingRepository implements BookingRepository {
  /// Starts with sample [history], or with this one (e.g. `const []` for a
  /// new patient).
  FakeBookingRepository({
    DateTime Function()? clock,
    List<Appointment>? history,
  }) : _clock = clock ?? DateTime.now {
    if (history == null) {
      _seed();
    } else {
      _appointments.addAll(history);
      _reserved.addAll(
        history.where((a) => a.isUpcoming(now())).map((a) => a.start),
      );
    }
  }

  final DateTime Function() _clock;
  final _appointments = <Appointment>[];
  final _reserved = <DateTime>{};
  var _nextId = 1;

  /// The clinic's doctor in the sample data.
  static const sampleDoctor = Doctor(
    id: 'benmahdia',
    nameAr: 'د. بن مهدية حسين',
    nameFr: 'Dr Benmahdia Hocine',
    initialsAr: 'ب ح',
    initialsFr: 'BH',
    slotMinutes: 15,
    priceDzd: 2000,
  );

  /// Days from a visit to the suggested follow-up.
  static const _followUpDays = 30;

  /// Consultation hours, in minutes after midnight.
  static const _hours = [(9 * 60, 12 * 60), (14 * 60, 16 * 60)];

  @override
  DateTime now() => _clock();

  @override
  Duration get notice => const Duration(hours: 24);

  @override
  Duration get horizon => const Duration(days: 60);

  @override
  Duration get holdFor => const Duration(minutes: 15);

  @override
  Future<List<Doctor>> doctors() async => const [sampleDoctor];

  @override
  Future<List<DaySlots>> calendar(Doctor doctor) async {
    final today = now();
    return [
      for (var i = 0; i < horizon.inDays; i++)
        _day(doctor, DateTime(today.year, today.month, today.day + i)),
    ];
  }

  @override
  Future<FollowUp?> followUp() async {
    final visits = _appointments.where(
      (a) =>
          a.status == AppointmentStatus.completed ||
          a.status == AppointmentStatus.confirmed,
    );
    if (visits.isEmpty) return null;
    final last = visits.reduce((a, b) => b.start.isAfter(a.start) ? b : a);
    final s = last.start;
    return FollowUp(
      after: last,
      day: DateTime(s.year, s.month, s.day + _followUpDays),
      days: _followUpDays,
    );
  }

  DaySlots _day(Doctor doctor, DateTime day) {
    if (day.weekday == DateTime.friday) {
      return DaySlots(day: day, slots: const [], closure: DayClosure.closed);
    }
    final earliest = now().add(notice);
    final slots = <Slot>[];
    var index = 0;
    for (final (from, to) in _hours) {
      for (var m = from; m < to; m += doctor.slotMinutes) {
        final start = DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
        // Sample pattern standing in for other patients' bookings.
        final takenByOthers = (day.day * 7 + index * 3) % 5 == 0;
        slots.add(
          Slot(
            start: start,
            free:
                !takenByOthers &&
                !_reserved.contains(start) &&
                !start.isBefore(earliest),
          ),
        );
        index++;
      }
    }
    if (slots.every((s) => s.start.isBefore(earliest))) {
      return DaySlots(day: day, slots: const [], closure: DayClosure.tooSoon);
    }
    return DaySlots(day: day, slots: slots);
  }

  @override
  Future<Hold> hold(Doctor doctor, DateTime start) async {
    final day = _day(doctor, DateTime(start.year, start.month, start.day));
    final free = day.slots.any((s) => s.start == start && s.free);
    if (!free) throw const SlotUnavailable();
    _reserved.add(start);
    return Hold(
      id: 'h${_nextId++}',
      doctor: doctor,
      start: start,
      end: start.add(Duration(minutes: doctor.slotMinutes)),
      expiresAt: now().add(holdFor),
    );
  }

  @override
  Future<void> release(Hold hold) async {
    final booked = _appointments.any(
      (a) => a.start == hold.start && a.isUpcoming(now()),
    );
    if (!booked) _reserved.remove(hold.start);
  }

  @override
  Future<Appointment> confirm(Hold hold, PaymentMethod method) async {
    final appointment = Appointment(
      id: 'a${_nextId++}',
      doctor: hold.doctor,
      start: hold.start,
      end: hold.end,
      status: AppointmentStatus.confirmed,
      priceDzd: hold.doctor.priceDzd,
      method: method,
    );
    _appointments.add(appointment);
    return appointment;
  }

  @override
  Future<List<Appointment>> appointments() async =>
      [..._appointments]..sort((a, b) => a.start.compareTo(b.start));

  @override
  Future<Appointment> cancel(Appointment appointment) async {
    if (appointment.start.difference(now()) < notice) {
      throw const TooLateToCancel();
    }
    final cancelled = appointment.withStatus(AppointmentStatus.cancelled);
    final i = _appointments.indexWhere((a) => a.id == appointment.id);
    if (i >= 0) _appointments[i] = cancelled;
    _reserved.remove(appointment.start);
    return cancelled;
  }

  void _seed() {
    final t = now();
    Appointment at(int dayOffset, int hour, int minute, AppointmentStatus s) {
      final start = DateTime(t.year, t.month, t.day + dayOffset, hour, minute);
      return Appointment(
        id: 'a${_nextId++}',
        doctor: sampleDoctor,
        start: start,
        end: start.add(const Duration(minutes: 15)),
        status: s,
        priceDzd: sampleDoctor.priceDzd,
        method: PaymentMethod.edahabia,
      );
    }

    final upcoming = at(1, 9, 30, AppointmentStatus.confirmed);
    _reserved.add(upcoming.start);
    _appointments.addAll([
      at(-34, 11, 30, AppointmentStatus.completed),
      at(-27, 14, 0, AppointmentStatus.cancelled),
      at(-20, 9, 15, AppointmentStatus.noShow),
      at(-13, 10, 0, AppointmentStatus.completed),
      upcoming,
    ]);
  }
}
