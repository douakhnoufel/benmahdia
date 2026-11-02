import 'craving_models.dart';
import 'craving_repository.dart';

/// Sample data: logs live in memory only.
class FakeCravingRepository implements CravingRepository {
  FakeCravingRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _logs = <CravingLog>[];

  @override
  Future<CravingLog> start(int intensity, List<HaltTrigger> triggers) async {
    final log = CravingLog(
      id: 'craving-${_logs.length + 1}',
      startedAt: _clock(),
      before: intensity,
      triggers: triggers.toSet().toList(),
    );
    _logs.insert(0, log);
    return log;
  }

  @override
  Future<CravingLog> passed(String id, int intensity) async {
    final i = _logs.indexWhere((l) => l.id == id);
    if (i < 0 || _logs[i].passed) throw const CravingUnavailable();
    final old = _logs[i];
    return _logs[i] = CravingLog(
      id: old.id,
      startedAt: old.startedAt,
      before: old.before,
      triggers: old.triggers,
      passedAt: _clock(),
      after: intensity,
    );
  }

  @override
  Future<List<CravingLog>> recent({int days = 30}) async {
    final since = _clock().subtract(Duration(days: days));
    return [
      for (final l in _logs)
        if (!l.startedAt.isBefore(since)) l,
    ];
  }
}
