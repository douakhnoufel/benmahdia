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
    if (response.statusCode == 403 && _code(response) == 'recovery_locked') {
      throw const RecoveryLocked();
    }
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

  /// The API's error code, e.g. "recovery_locked"; null when there is none.
  static String? _code(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final detail = body is Map ? body['detail'] : null;
      final code = detail is Map ? detail['code'] : null;
      return code is String ? code : null;
    } on FormatException {
      return null;
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
        profile: switch (m['profile']) {
          final String p => SubstanceProfile.values.byName(p),
          _ => null,
        },
        goalDays: m['goal_days'] as int?,
        milestoneSeen: m['milestone_seen'] as int? ?? 0,
        milestone: m['milestone'] as int?,
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
    AddictionType? type,
    SubstanceProfile? profile,
    required DateTime cleanSince,
    String? substance,
  }) async => _addictionFrom(
    await _send(
      'POST',
      'v1/me/addictions',
      body: {
        'type': ?type?.name,
        'profile': ?profile?.name,
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
      body: {if (at != null) 'at': _utc(at), 'note': ?note},
    ),
  );

  @override
  Future<Addiction> setGoal(Addiction addiction, int? days) async =>
      _addictionFrom(
        await _send(
          'PUT',
          'v1/me/addictions/${addiction.id}/goal',
          body: {'days': days},
        ),
      );

  @override
  Future<Addiction> markMilestoneSeen(Addiction addiction) async =>
      _addictionFrom(
        await _send('POST', 'v1/me/addictions/${addiction.id}/milestone/seen'),
      );

  // --- per-substance tracking (PRD 5.6) -------------------------------------

  static LocalizedText _text(Object? json) {
    final m = json! as Map<String, dynamic>;
    return LocalizedText(ar: m['ar'] as String, fr: m['fr'] as String);
  }

  static DateTime _day(String ymd) {
    final p = ymd.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  @override
  Future<List<ProfileSpec>> profiles() async {
    final json = await _send('GET', 'v1/me/recovery/profiles');
    try {
      return [
        for (final p in json! as List)
          ProfileSpec(
            profile: SubstanceProfile.values.byName(p['key'] as String),
            type: AddictionType.values.byName(p['type'] as String),
            name: _text(p['name']),
            signals: [
              for (final sig in p['signals'] as List)
                SignalSpec(
                  key: sig['key'] as String,
                  label: _text(sig['label']),
                ),
            ],
            notes: [
              for (final n in p['notes'] as List)
                EarlyNote(day: n['day'] as int, text: _text(n['text'])),
            ],
          ),
      ];
    } on Object {
      throw const RecoveryUnavailable();
    }
  }

  @override
  Future<CheckHistory> addictionChecks() async {
    final json = await _send('GET', 'v1/me/addiction-checks');
    try {
      final m = json! as Map<String, dynamic>;
      return (
        checks: [
          for (final c in m['checks'] as List)
            AddictionCheck(
              addictionId: c['addiction_id'] as String,
              day: _day(c['day'] as String),
              used: c['used'] as bool,
              craving: c['craving'] as int,
              signals: (c['signals'] as Map).cast<String, int>(),
            ),
        ],
        doneDays: {for (final d in m['done_days'] as List) _day(d as String)},
      );
    } on Object {
      throw const RecoveryUnavailable();
    }
  }

  @override
  Future<void> saveCheck(AddictionCheck check) async {
    await _send(
      'PUT',
      'v1/me/addictions/${check.addictionId}/checks/${_ymd(check.day)}',
      body: {
        'used': check.used,
        'craving': check.craving,
        'signals': check.signals,
      },
    );
  }

  // --- good habits (PRD 5.6) ------------------------------------------------

  static const _habitWire = {
    HabitKind.sport: 'sport',
    HabitKind.brushTeeth: 'brush_teeth',
    HabitKind.water: 'water',
    HabitKind.reading: 'reading',
    HabitKind.callFamily: 'call_family',
    HabitKind.sleep: 'sleep',
    HabitKind.custom: 'custom',
  };

  static HabitKind _habitKind(Object? wire) {
    for (final e in _habitWire.entries) {
      if (e.value == wire) return e.key;
    }
    throw const RecoveryUnavailable();
  }

  static DayTime? _time(Object? hhmm) {
    if (hhmm == null) return null;
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch('$hhmm');
    if (match == null) throw const RecoveryUnavailable();
    return (hour: int.parse(match[1]!), minute: int.parse(match[2]!));
  }

  static Habit _habitFrom(Object? json) {
    try {
      final m = json! as Map<String, dynamic>;
      return Habit(
        id: m['id'] as String,
        kind: _habitKind(m['kind']),
        text: m['text'] as String?,
        reminder: _time(m['reminder_time']),
        days: {for (final d in m['days'] as List) _day(d as String)},
      );
    } on Object {
      throw const RecoveryUnavailable();
    }
  }

  @override
  Future<Map<HabitKind, LocalizedText>> habitCatalog() async {
    final json = await _send('GET', 'v1/me/habits/catalog');
    try {
      return {
        for (final item in json! as List)
          _habitKind(item['kind']): _text(item['label']),
      };
    } on Object {
      throw const RecoveryUnavailable();
    }
  }

  @override
  Future<List<Habit>> habits() async {
    final json = await _send('GET', 'v1/me/habits');
    if (json is! List) throw const RecoveryUnavailable();
    return json.map(_habitFrom).toList();
  }

  @override
  Future<Habit> addHabit(
    HabitKind kind, {
    String? text,
    DayTime? reminder,
  }) async => _habitFrom(
    await _send(
      'POST',
      'v1/me/habits',
      body: {
        'kind': _habitWire[kind],
        'text': ?text,
        if (reminder != null)
          'reminder_time': _hhmm(reminder.hour, reminder.minute),
      },
    ),
  );

  @override
  Future<void> removeHabit(Habit habit) async {
    await _send('DELETE', 'v1/me/habits/${habit.id}');
  }

  @override
  Future<Habit> setHabitReminder(Habit habit, DayTime? time) async =>
      _habitFrom(
        await _send(
          'PUT',
          'v1/me/habits/${habit.id}/reminder',
          body: {'time': time == null ? null : _hhmm(time.hour, time.minute)},
        ),
      );

  @override
  Future<void> markHabit(
    Habit habit,
    DateTime day, {
    required bool done,
  }) async {
    await _send(
      done ? 'PUT' : 'DELETE',
      'v1/me/habits/${habit.id}/days/${_ymd(day)}',
    );
  }

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
