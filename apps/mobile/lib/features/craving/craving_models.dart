/// The four states behind many cravings: hungry, angry, lonely, tired.
/// Naming one is optional and never free text.
enum Halt { hungry, angry, lonely, tired }

/// One difficult moment: how strong the craving was when the patient opened
/// the screen, which [Halt] states they named, and how strong it was once it
/// passed. The doctor reads these numbers; there is no note.
class CravingLog {
  const CravingLog({
    required this.id,
    required this.before,
    required this.halt,
    required this.startedAt,
    this.after,
    this.passedAt,
  });

  final String id;

  /// 1-10 when the moment started.
  final int before;

  /// 1-10 once it passed; null while it is still going.
  final int? after;
  final Set<Halt> halt;
  final DateTime startedAt;
  final DateTime? passedAt;

  bool get isPassed => passedAt != null;

  CravingLog passed(int intensity, DateTime at) => CravingLog(
    id: id,
    before: before,
    halt: halt,
    startedAt: startedAt,
    after: intensity,
    passedAt: at,
  );
}

/// The patient's own "if X, then I will Y" plan. It stays on the phone.
class IfThenPlan {
  const IfThenPlan({required this.ifText, required this.thenText});

  /// Longest text for each half.
  static const maxLength = 120;

  final String ifText;
  final String thenText;

  bool get isEmpty => ifText.trim().isEmpty || thenText.trim().isEmpty;
}

/// The craving server could not be reached or answered badly. The screen
/// keeps what the patient entered and offers a retry.
class CravingUnavailable implements Exception {
  const CravingUnavailable();
}
