/// Where the patient stands with the ID declaration (PRD 4.2). The clinic
/// approves what the patient declared; the app never says "verified".
enum IdStatus { none, declared, approved, rejected }

class IdentityState {
  const IdentityState({
    required this.status,
    this.rejectReason,
    this.submissionsLeft = 4,
  });

  final IdStatus status;

  /// Why the clinic refused, when it said.
  final String? rejectReason;

  /// How many more times the patient may send the details.
  final int submissionsLeft;

  /// Booking and everything clinical open only after approval.
  bool get approved => status == IdStatus.approved;

  bool get canSubmit =>
      (status == IdStatus.none || status == IdStatus.rejected) &&
      submissionsLeft > 0;
}

/// The three fields the patient confirmed. The card image is never kept.
class IdentityDraft {
  const IdentityDraft({
    required this.idNumber,
    required this.fullName,
    required this.birthDate,
  });

  final String idNumber;
  final String fullName;
  final DateTime birthDate;

  /// `YYYY-MM-DD`, as the API expects.
  String get birthIso =>
      '${birthDate.year.toString().padLeft(4, '0')}-'
      '${birthDate.month.toString().padLeft(2, '0')}-'
      '${birthDate.day.toString().padLeft(2, '0')}';
}

enum IdField { idNumber, fullName, birthDate, selfie }

/// Every way sending the declaration can fail that a screen explains.
sealed class IdentityFailure implements Exception {
  const IdentityFailure();
}

/// The ID belongs to another account. The patient is not told whose.
final class IdAlreadyLinked extends IdentityFailure {
  const IdAlreadyLinked();
}

final class TooManySubmissions extends IdentityFailure {
  const TooManySubmissions();
}

/// The server refused one of the fields.
final class InvalidDetails extends IdentityFailure {
  const InvalidDetails(this.field);

  final IdField field;
}

/// Already sent or already approved: reload the status instead.
final class AlreadyDecided extends IdentityFailure {
  const AlreadyDecided();
}

final class IdentityUnavailable extends IdentityFailure {
  const IdentityUnavailable();
}
