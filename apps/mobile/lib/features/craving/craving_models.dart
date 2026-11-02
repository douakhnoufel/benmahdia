import '../recovery/recovery_models.dart';

/// The HALT triggers behind a craving: hungry, angry, lonely, tired, other.
/// The names match the API (backend/app/routers/cravings.py).
enum CravingTrigger { hungry, angry, lonely, tired, other }

/// How strong a craving is, 1 (light) to 10 (strong).
const cravingIntensityMin = 1;
const cravingIntensityMax = 10;

/// One difficult moment: how strong the craving was when it started, what
/// was behind it (HALT), and how strong it was once it had passed. The
/// doctor sees these logs (PRD 3), so the screen says so; no free text is
/// ever sent.
class CravingLog {
  const CravingLog({
    required this.id,
    required this.startedAt,
    required this.intensityBefore,
    this.triggers = const [],
    this.passedAt,
    this.intensityAfter,
  });

  final String id;
  final DateTime startedAt;

  /// 1-10 when the craving started.
  final int intensityBefore;
  final List<CravingTrigger> triggers;

  /// When the patient said the craving had passed; null while it lasts.
  final DateTime? passedAt;

  /// 1-10 once it had passed; null while it lasts.
  final int? intensityAfter;

  bool get passed => passedAt != null;

  /// How much the craving came down; 0 when it did not come down at all.
  int get relief => intensityAfter == null
      ? 0
      : (intensityBefore - intensityAfter!).clamp(0, cravingIntensityMax);

  CravingLog copyWith({DateTime? passedAt, int? intensityAfter}) => CravingLog(
    id: id,
    startedAt: startedAt,
    intensityBefore: intensityBefore,
    triggers: triggers,
    passedAt: passedAt ?? this.passedAt,
    intensityAfter: intensityAfter ?? this.intensityAfter,
  );
}

/// The patient's own plan, "When ___, I will ___". It stays on the phone
/// ("Only you"); the doctor's support plan comes later.
class IfThenPlan {
  const IfThenPlan({required this.when, required this.then});

  const IfThenPlan.empty() : when = '', then = '';

  final String when;
  final String then;

  /// A plan is only worth showing once both halves are filled in.
  bool get isEmpty => when.trim().isEmpty || then.trim().isEmpty;
}

/// A craving can be marked passed once only (the API answers 409
/// `craving_already_passed`). It extends [RecoveryUnavailable] so callers
/// that only need to know the call did not go through keep working.
class CravingAlreadyPassed extends RecoveryUnavailable {
  const CravingAlreadyPassed();
}
