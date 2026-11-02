/// What is behind a craving (HALT, habit-tracking design). No free text.
enum HaltTrigger { hungry, angry, lonely, tired, other }

/// One difficult moment: how strong the craving was when it started and,
/// once it passed, how strong it was then (both 1-10).
class CravingLog {
  const CravingLog({
    required this.id,
    required this.startedAt,
    required this.before,
    required this.triggers,
    this.passedAt,
    this.after,
  });

  final String id;
  final DateTime startedAt;
  final int before;
  final List<HaltTrigger> triggers;
  final DateTime? passedAt;
  final int? after;

  bool get passed => passedAt != null;
}

/// The craving server could not be reached or answered badly.
class CravingUnavailable implements Exception {
  const CravingUnavailable();
}
