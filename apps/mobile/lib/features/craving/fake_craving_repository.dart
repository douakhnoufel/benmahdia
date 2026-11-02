import '../recovery/recovery_models.dart';
import 'craving_models.dart';
import 'craving_repository.dart';

/// Sample difficult moments for the demo app and for tests: nothing logged
/// yet, so the screen starts on a clean slate. With [locked], every call
/// answers [RecoveryLocked], as before the first paid appointment; with
/// [failing], every call answers [RecoveryUnavailable], to exercise the
/// error paths.
class FakeCravingRepository implements CravingRepository {
  FakeCravingRepository({
    DateTime Function()? clock,
    this.locked = false,
    this.failing = false,
    List<CravingLog> seed = const [],
  }) : _clock = clock ?? DateTime.now,
       logs = [...seed];

  final DateTime Function() _clock;
  bool locked;
  bool failing;

  /// Everything logged so far, oldest first; readable by tests.
  final List<CravingLog> logs;

  var _nextId = 1;

  void _guard() {
    if (locked) throw const RecoveryLocked();
    if (failing) throw const RecoveryUnavailable();
  }

  @override
  DateTime now() => _clock();

  @override
  Future<CravingLog> start({
    required int intensity,
    List<CravingTrigger> triggers = const [],
  }) async {
    _guard();
    final log = CravingLog(
      id: 'craving-${_nextId++}',
      startedAt: _clock(),
      intensityBefore: intensity,
      // Each trigger once, in the order the patient tapped them.
      triggers: {...triggers}.toList(),
    );
    logs.add(log);
    return log;
  }

  @override
  Future<CravingLog> markPassed(
    CravingLog log, {
    required int intensity,
  }) async {
    _guard();
    final at = logs.indexWhere((l) => l.id == log.id);
    if (at < 0) throw const RecoveryUnavailable();
    if (logs[at].passed) throw const CravingAlreadyPassed();
    return logs[at] = logs[at].copyWith(
      passedAt: _clock(),
      intensityAfter: intensity,
    );
  }

  @override
  Future<List<CravingLog>> recent({int days = 30}) async {
    _guard();
    final since = _clock().subtract(Duration(days: days));
    return [
      for (final log in logs.reversed)
        if (log.startedAt.isAfter(since)) log,
    ];
  }
}
