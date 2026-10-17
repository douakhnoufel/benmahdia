/// Liveness checks the selfie camera asks for, in order (PRD 4.2).
enum LivenessStep { lookAtCamera, turnHead, blink }

/// Sides of the national ID card, captured front first.
enum CardSide { front, back }

/// On-device photo checks on the ID card, run before it can be submitted
/// (PRD 4.2: blur, glare, whole card visible).
class IdQuality {
  const IdQuality({
    required this.sharp,
    required this.noGlare,
    required this.wholeCard,
  });

  final bool sharp;
  final bool noGlare;
  final bool wholeCard;

  /// Whether every check passed, so the photos may be submitted.
  bool get passed => sharp && noGlare && wholeCard;
}
