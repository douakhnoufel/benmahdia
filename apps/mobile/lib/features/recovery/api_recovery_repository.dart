import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'recovery_models.dart';
import 'recovery_repository.dart';

/// [RecoveryRepository] over the BenMahdia API (backend/app/routers/recovery.py).
///
/// Addictions, relapses, the daily check, the reminder time, today's doses
/// and the quote of the day live on the server. The clinic's card is local
/// data, answered by [_rest].
class ApiRecoveryRepository implements RecoveryRepository {
  ApiRecoveryRepository({
    required Uri baseUrl,
    required String? Function() token,
    required Future<bool> Function() refresh,
    required RecoveryRepository rest,
    http.Client? client,
    DateTime Function()? clock,
  }) : _base = baseUrl,
       _token = token,
       _refresh = refresh,
       _rest = rest,
       _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final Uri _base;
  final String? Function() _token;
  final Future<bool> Function() _refresh;
  final RecoveryRepository _rest;
  final http.Client _client;
  final DateTime Function() _clock;
  Future<bool>? _refreshing;

  static const _timeout = Duration(seconds: 15);

  @override
  DateTime now() => _clock();

  // --- http -----------------------------------------------------------------

  /// With [nullOn404], "not found" is an answer (null), not a failure.
  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    bool nullOn404 = false,
  }) async {
    var response = await _once(method, path, body);
    if (response.statusCode == 401 && await _refreshOnce()) {
      response = await _once(method, path, body);
    }
    if (nullOn404 && response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const RecoveryUnavailable();
    }
    try {
      final text = utf8.decode(response.bodyBytes);
      return text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      throw const RecoveryUnavailable();
    }
  }

  /// A refresh token is single-use, so several expired requests must await
  /// the same rotation instead of each spending the old token.
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
      throw const RecoveryUnavailable();
    } on http.ClientException {
      throw const RecoveryUnavailable();
    }
  }

  // --- parsing --------------------------------------------------------------

  /// A malformed answer is "unavailable", never a crash.
  static Addiction _addictionFrom(Object? json) {
    try {
      final m = json! as Map<String, dynamic>;
      return Addiction(
        id: m['id'] as String,
        type: AddictionType.values.byName(m['type'] as String),
        substance: m['substance'] as String?,
        reviewed: m['review_status'] == 'confirmed',
        start: DateTime.parse(m['clean_since'] as String).toLocal(),
        longestPastDays: m['longest_past_days'] as int,
        pastDays: m['past_days'] as int,
      );
    } on Object {
      throw const RecoveryUnavailable();
    }
  }

  static String _utc(DateTime t) => t.toUtc().toIso8601String();

  // --- addictions and relapses (on the server) -------------------------------

  @override
  Future<List<Addiction>> addictions() async {
    final json = await _send('GET', 'v1/me/addictions');
    if (json is! List) throw const RecoveryUnavailable();
    return json.map(_addictionFrom).toList();
  }

  @override
  Future<Addiction> addAddiction({
    required AddictionType type,
    required DateTime cleanSince,
    String? substance,
  }) async => _addictionFrom(
    await _send(
      'POST',
      'v1/me/addictions',
      body: {
        'type': type.name,
        'substance': substance,
        'clean_since': _utc(cleanSince),
      },
    ),
  );

  @override
  Future<Addiction> logRelapse(
    Addiction addiction, {
    String? note,
    DateTime? at,
  }) async => _addictionFrom(
    await _send(
      'POST',
      'v1/me/addictions/${addiction.id}/relapses',
      body: {
        if (at != null) 'at': _utc(at),
        'note': ?note,
      },
    ),
  );

  // --- daily check and reminder -------------------------------------------

  /// "2026-10-17" for the calendar day of [t] (the phone's own day).
  static String _ymd(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  static String _hhmm(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  Future<Set<DateTime>> checkIns() async {
    final json = await _send('GET', 'v1/me/checkins');
    if (json is! List) throw const RecoveryUnavailable();
    try {
      final days = <DateTime>{};
      for (final d in json) {
        final p = (d as String).split('-').map(int.parse).toList();
        days.add(DateTime(p[0], p[1], p[2]));
      }
      return days;
    } on Object {
      throw const RecoveryUnavailable();
    }
  }

  @override
  Future<void> checkIn(DateTime day) async {
    await _send('PUT', 'v1/me/checkins/${_ymd(day)}');
  }

  @override
  Future<DayTime?> reminder() async {
    final json = await _send('GET', 'v1/me/reminder');
    final time = json is Map ? json['time'] : null;
    if (time == null) return null;
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch('$time');
    if (match == null) throw const RecoveryUnavailable();
    return (hour: int.parse(match[1]!), minute: int.parse(match[2]!));
  }

  @override
  Future<void> setReminder(DayTime? time) async {
    await _send(
      'PUT',
      'v1/me/reminder',
      body: {'time': time == null ? null : _hhmm(time.hour, time.minute)},
    );
  }

  // --- doses ------------------------------------------------------------------

  /// A dose is a medicine at a time: the id carries both, "medicationId|HH:MM".
  static Dose _doseFrom(Object? json) {
    try {
      final m = json! as Map<String, dynamic>;
      final time = m['time'] as String;
      final name = m['name'] as String;
      final amount = m['amount'] as String;
      final instruction = m['instruction'] as String?;
      return Dose(
        id: '${m['medication_id']}|$time',
        // Drug names, doses and the doctor's note are written once by the
        // doctor; they show the same in both languages.
        name: LocalizedText(ar: name, fr: name),
        amount: LocalizedText(ar: amount, fr: amount),
        instruction: instruction == null
            ? null
            : LocalizedText(ar: instruction, fr: instruction),
        hour: int.parse(time.substring(0, 2)),
        minute: int.parse(time.substring(3, 5)),
        status: switch (m['status']) {
          'taken' => DoseStatus.taken,
          'skipped' => DoseStatus.skipped,
          _ => DoseStatus.due, // due, or missed on a past day
        },
      );
    } on Object {
      throw const RecoveryUnavailable();
    }
  }

  @override
  Future<List<Dose>> todaysDoses() async {
    final day = _ymd(now());
    final json = await _send('GET', 'v1/me/doses?day=$day');
    if (json is! List) throw const RecoveryUnavailable();
    return json.map(_doseFrom).toList();
  }

  @override
  Future<Dose> markDose(Dose dose, DoseStatus status) async {
    if (status == DoseStatus.due) return dose; // nothing to record
    final [medicationId, time] = dose.id.split('|');
    return _doseFrom(
      await _send(
        'PUT',
        'v1/me/doses',
        body: {
          'medication_id': medicationId,
          'day': _ymd(now()),
          'time': time,
          'status': status.name,
        },
      ),
    );
  }

  // --- quote ------------------------------------------------------------------

  @override
  Future<Quote?> quoteOfDay() async {
    final json = await _send('GET', 'v1/me/quote', nullOn404: true);
    if (json == null) return null;
    try {
      final m = json as Map<String, dynamic>;
      return Quote(
        text: LocalizedText(
          ar: m['text_ar'] as String,
          fr: m['text_fr'] as String,
        ),
        // The clinic's quotes carry no author line.
        source: const LocalizedText(ar: '', fr: ''),
      );
    } on Object {
      throw const RecoveryUnavailable();
    }
  }

  // --- local ------------------------------------------------------------------

  @override
  Future<ClinicInfo> clinic() => _rest.clinic();
}
