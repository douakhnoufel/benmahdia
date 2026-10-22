import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'booking_models.dart';
import 'booking_repository.dart';

/// [BookingRepository] over the BenMahdia API (backend/README.md).
///
/// The server speaks UTC; the screens speak clinic time (Africa/Algiers,
/// UTC+1, no daylight saving), so every instant is converted here.
class ApiBookingRepository implements BookingRepository {
  ApiBookingRepository({
    required Uri baseUrl,
    required String? Function() token,
    required Future<bool> Function() refresh,
    http.Client? client,
    DateTime Function()? clock,
  }) : _base = baseUrl,
       _token = token,
       _refresh = refresh,
       _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final Uri _base;
  final String? Function() _token;
  final Future<bool> Function() _refresh;
  final http.Client _client;
  final DateTime Function() _clock;
  Future<bool>? _refreshing;

  static const _timeout = Duration(seconds: 15);
  static const _clinicOffset = Duration(hours: 1);

  // Defaults until the first doctor answer carries the doctor's settings.
  Duration _notice = const Duration(hours: 24);
  Duration _horizon = const Duration(days: 60);
  Duration _holdFor = const Duration(minutes: 15);

  @override
  DateTime now() => _toClinic(_clock().toUtc());

  @override
  Duration get notice => _notice;

  @override
  Duration get horizon => _horizon;

  @override
  Duration get holdFor => _holdFor;

  @override
  Set<PaymentMethod> get methods => PaymentMethod.values.toSet();

  /// Cards are confirmed only by Chargily's signed webhook (PRD 4.4).
  @override
  bool get cardsUseCheckout => true;

  // --- time -----------------------------------------------------------------

  /// A UTC instant as a plain clinic wall-clock time.
  static DateTime _toClinic(DateTime utc) {
    final c = utc.toUtc().add(_clinicOffset);
    return DateTime(c.year, c.month, c.day, c.hour, c.minute, c.second);
  }

  static DateTime _parse(String iso) => _toClinic(DateTime.parse(iso));

  /// A clinic wall-clock time as the UTC instant the server expects.
  static String _toUtcIso(DateTime clinic) => DateTime.utc(
    clinic.year,
    clinic.month,
    clinic.day,
    clinic.hour,
    clinic.minute,
    clinic.second,
  ).subtract(_clinicOffset).toIso8601String();

  static DateTime _day(String iso) {
    final p = iso.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  // --- http -----------------------------------------------------------------

  Future<Object?> _send(String method, String path, {Object? body}) async {
    var response = await _once(method, path, body);
    if (response.statusCode == 401 && await _refreshOnce()) {
      response = await _once(method, path, body);
    }
    Object? decoded;
    try {
      final text = utf8.decode(response.bodyBytes);
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      throw const BookingUnavailable();
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    throw _failure(response.statusCode, decoded);
  }

  /// A refresh token is single-use. Several expired requests must therefore
  /// await the same rotation instead of each spending the old token.
  Future<bool> _refreshOnce() {
    final active = _refreshing;
    if (active != null) return active;
    final refresh = _refresh();
    return _refreshing = refresh.whenComplete(() => _refreshing = null);
  }

  Future<http.Response> _once(String method, String path, Object? body) async {
    final request = http.Request(method, _base.resolve(path))
      ..headers['content-type'] = 'application/json'
      ..headers['accept'] = 'application/json';
    final token = _token();
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    try {
      return await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
    } on TimeoutException {
      throw const BookingUnavailable();
    } on http.ClientException {
      throw const BookingUnavailable();
    }
  }

  static Exception _failure(int status, Object? body) {
    final detail = body is Map ? body['detail'] : null;
    final code = detail is Map ? detail['code'] : null;
    return switch (code) {
      'slot_unavailable' || 'hold_expired' => const SlotUnavailable(),
      'too_late_to_cancel' => const TooLateToCancel(),
      'not_a_hold' || 'appointment_not_found' => const SlotUnavailable(),
      _ => const BookingUnavailable(),
    };
  }

  // --- parsing --------------------------------------------------------------

  /// The first letters of the last two words of [name] ("Dr Benmahdia
  /// Hocine" gives BH).
  static String _initials(String name, {required bool arabic}) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && w != 'Dr' && w != 'د.' && w != 'د')
        .toList();
    final last = words.length > 2 ? words.sublist(words.length - 2) : words;
    final letters = last.map((w) => String.fromCharCode(w.runes.first));
    return arabic ? letters.join(' ') : letters.join().toUpperCase();
  }

  Doctor _doctorFrom(Map<String, dynamic> json) {
    _notice = Duration(hours: json['notice_hours'] as int);
    _holdFor = Duration(minutes: json['hold_minutes'] as int);
    _horizon = Duration(days: json['horizon_days'] as int);
    final ar = json['name_ar'] as String;
    final fr = json['name_fr'] as String;
    return Doctor(
      id: json['id'] as String,
      nameAr: ar,
      nameFr: fr,
      initialsAr: _initials(ar, arabic: true),
      initialsFr: _initials(fr, arabic: false),
      slotMinutes: json['slot_minutes'] as int,
      priceDzd: json['price_dzd'] as int,
    );
  }

  static AppointmentStatus _status(String s) => switch (s) {
    'awaiting_payment' => AppointmentStatus.awaitingPayment,
    'confirmed' => AppointmentStatus.confirmed,
    'completed' => AppointmentStatus.completed,
    'cancelled' => AppointmentStatus.cancelled,
    'no_show' => AppointmentStatus.noShow,
    _ => throw const BookingUnavailable(),
  };

  static PaymentMethod _method(String? m) => switch (m) {
    'edahabia' => PaymentMethod.edahabia,
    'cib' => PaymentMethod.cib,
    _ => PaymentMethod.clinic,
  };

  Appointment _appointmentFrom(Map<String, dynamic> json) => Appointment(
    id: json['id'] as String,
    doctor: _doctorFrom(json['doctor'] as Map<String, dynamic>),
    start: _parse(json['start'] as String),
    end: _parse(json['end'] as String),
    status: _status(json['status'] as String),
    priceDzd: json['price_dzd'] as int,
    method: _method(json['method'] as String?),
  );

  // --- repository -----------------------------------------------------------

  @override
  Future<List<Doctor>> doctors() async {
    final json = await _send('GET', 'v1/doctors') as List<dynamic>;
    return [for (final d in json) _doctorFrom(d as Map<String, dynamic>)];
  }

  @override
  Future<List<DaySlots>> calendar(Doctor doctor) async {
    final json =
        await _send('GET', 'v1/doctors/${doctor.id}/calendar')
            as Map<String, dynamic>;
    return [
      for (final d in json['days'] as List<dynamic>)
        _dayFrom(d as Map<String, dynamic>),
    ];
  }

  DaySlots _dayFrom(Map<String, dynamic> json) => DaySlots(
    day: _day(json['day'] as String),
    closure: switch (json['closure']) {
      'too_soon' => DayClosure.tooSoon,
      'closed' => DayClosure.closed,
      _ => DayClosure.none,
    },
    slots: [
      for (final s in json['slots'] as List<dynamic>)
        Slot(
          start: _parse((s as Map<String, dynamic>)['start'] as String),
          free: s['free'] as bool,
        ),
    ],
  );

  @override
  Future<FollowUp?> followUp() async {
    final json = await _send('GET', 'v1/appointments/follow-up');
    if (json == null) return null;
    final map = json as Map<String, dynamic>;
    return FollowUp(
      after: _appointmentFrom(map['after'] as Map<String, dynamic>),
      day: _day(map['day'] as String),
      days: map['days'] as int,
    );
  }

  @override
  Future<Hold> hold(Doctor doctor, DateTime start) async {
    final json =
        await _send(
              'POST',
              'v1/appointments/holds',
              body: {'doctor_id': doctor.id, 'start': _toUtcIso(start)},
            )
            as Map<String, dynamic>;
    final a = _appointmentFrom(json);
    return Hold(
      id: a.id,
      doctor: a.doctor,
      start: a.start,
      end: a.end,
      expiresAt: _parse(json['hold_expires_at'] as String),
    );
  }

  @override
  Future<void> release(Hold hold) async {
    try {
      await _send('DELETE', 'v1/appointments/${hold.id}/hold');
    } on BookingUnavailable {
      // Best effort: the server also gives the slot back when the hold runs out.
    }
  }

  @override
  Future<Appointment> confirm(Hold hold, PaymentMethod method) async =>
      _appointmentFrom(
        await _send(
              'POST',
              'v1/appointments/${hold.id}/confirm',
              body: {'method': method.name},
            )
            as Map<String, dynamic>,
      );

  @override
  Future<Uri> checkout(Hold hold, PaymentMethod method) async {
    final json =
        await _send(
              'POST',
              'v1/appointments/${hold.id}/checkout',
              body: {'method': method.name},
            )
            as Map<String, dynamic>;
    return Uri.parse(json['checkout_url'] as String);
  }

  @override
  Future<Appointment?> paid(Hold hold) async {
    final mine = await appointments();
    for (final a in mine) {
      if (a.id != hold.id) continue;
      return switch (a.status) {
        AppointmentStatus.confirmed => a,
        AppointmentStatus.awaitingPayment => null,
        _ => throw const SlotUnavailable(),
      };
    }
    // The server dropped the hold: payment failed or time ran out.
    throw const SlotUnavailable();
  }

  @override
  Future<List<Appointment>> appointments() async {
    final json = await _send('GET', 'v1/appointments') as List<dynamic>;
    return [for (final a in json) _appointmentFrom(a as Map<String, dynamic>)];
  }

  @override
  Future<Appointment> cancel(Appointment appointment) async => _appointmentFrom(
    await _send('POST', 'v1/appointments/${appointment.id}/cancel')
        as Map<String, dynamic>,
  );
}
