/// Where the patient stands with the ID declaration (PRD 4.2), mirrored from
/// `/v1/me`.
enum MeIdStatus { none, declared, approved, rejected }

/// The signed-in account as `/v1/me` returns it: what Profile & Settings shows.
class Me {
  const Me({
    required this.id,
    required this.phone,
    required this.email,
    required this.language,
    required this.hasPassword,
    required this.providers,
    required this.idStatus,
  });

  final String id;

  /// E.164, or null for a Google / Apple account with no number yet.
  final String? phone;

  /// Contact address (not a sign-in method, not verified), or null.
  final String? email;

  /// "ar" or "fr".
  final String language;

  /// Whether the account can sign in with a password.
  final bool hasPassword;

  /// Social sign-in methods linked: "google", "apple".
  final List<String> providers;

  final MeIdStatus idStatus;

  Me copyWith({String? Function()? email}) => Me(
    id: id,
    phone: phone,
    email: email != null ? email() : this.email,
    language: language,
    hasPassword: hasPassword,
    providers: providers,
    idStatus: idStatus,
  );

  static Me fromJson(Map<String, dynamic> json) => Me(
    id: json['id'] as String,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    language: json['language'] as String? ?? 'ar',
    hasPassword: json['has_password'] as bool? ?? false,
    providers: ((json['providers'] as List?) ?? const []).cast<String>(),
    idStatus: switch (json['id_status']) {
      'declared' => MeIdStatus.declared,
      'approved' => MeIdStatus.approved,
      'rejected' => MeIdStatus.rejected,
      _ => MeIdStatus.none,
    },
  );
}

/// Ways a Profile & Settings action can fail that a screen explains.
sealed class AccountFailure implements Exception {
  const AccountFailure();
}

/// The email was not a valid address.
final class InvalidEmail extends AccountFailure {
  const InvalidEmail();
}

/// Account deletion needs the password and it was wrong.
final class WrongPassword extends AccountFailure {
  const WrongPassword();
}

final class AccountUnavailable extends AccountFailure {
  const AccountUnavailable();
}
