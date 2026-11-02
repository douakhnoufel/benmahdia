import 'craving_models.dart';
import 'craving_repository.dart';

/// Sample data kept in memory, for running the app without a server.
class FakeCravingRepository implements CravingRepository {
  FakeCravingRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _logs = <CravingLog>[];

  @override
  DateTime now() => _clock();

  @override
  Future<CravingLog> start({
    required int intensity,
    required Set<Halt> halt,
  }) async {
    final log = CravingLog(
      id: 'c${_logs.length + 1}',
      before: intensity,
      halt: Set.of(halt),
      startedAt: now(),
    );
    _logs.insert(0, log);
    return log;
  }

  @override
  Future<CravingLog> markPassed(CravingLog log, int intensity) async {
    final done = log.passed(intensity, now());
    final i = _logs.indexWhere((l) => l.id == log.id);
    if (i >= 0) _logs[i] = done;
    return done;
  }

  @override
  Future<List<CravingLog>> recent() async => List.of(_logs);
}

/// An in-memory [IfThenPlanStore], for tests and the sample app.
class MemoryIfThenPlanStore implements IfThenPlanStore {
  MemoryIfThenPlanStore([this.plan]);

  IfThenPlan? plan;

  @override
  Future<IfThenPlan?> read() async => plan;

  @override
  Future<void> write(IfThenPlan? value) async => plan = value;
}
