import 'phone_number.dart';

/// Why a one-time SMS code is sent.
enum OtpPurpose {
  /// Confirms the number of a new phone + password account.
  signUp,

  /// Lets a patient who forgot their password choose a new one.
  resetPassword,

  /// Adds a confirmed number to an account opened with Google or Apple.
  attachPhone,
}

/// A code was sent; another can be asked for after [resendAfter].
class OtpTicket {
  const OtpTicket({required this.resendAfter});

  final Duration resendAfter;
}

class AuthUser {
  const AuthUser({required this.id, required this.verified, this.phone});

  final String id;

  /// Null until a Google / Apple account confirms a number.
  final PhoneNumber? phone;

  /// The clinic approved the identity check (PRD 4.2). Nothing clinical
  /// unlocks before.
  final bool verified;

  AuthUser withPhone(PhoneNumber phone) =>
      AuthUser(id: id, verified: verified, phone: phone);
}

/// Tokens for the API: a short-lived access token and a rotating refresh
/// token (PRD 4.1).
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  AuthSession withUser(AuthUser user) => AuthSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    user: user,
  );
}

/// Every way signing in or up can fail that a screen explains to the
/// patient.
sealed class AuthFailure implements Exception {
  const AuthFailure();
}

/// The number already has an account.
final class PhoneTaken extends AuthFailure {
  const PhoneTaken();
}

final class WrongCode extends AuthFailure {
  const WrongCode();
}

/// The code expired, was already used, or was never sent.
final class CodeExpired extends AuthFailure {
  const CodeExpired();
}

/// Five wrong codes: a new one must be requested.
final class TooManyAttempts extends AuthFailure {
  const TooManyAttempts();
}

final class WrongCredentials extends AuthFailure {
  const WrongCredentials();
}

/// Five wrong passwords lock the account for a while (PRD 4.1).
final class AccountLocked extends AuthFailure {
  const AccountLocked(this.retryAfter);

  final Duration retryAfter;
}

/// Too many codes or attempts in a short time.
final class RateLimited extends AuthFailure {
  const RateLimited(this.retryAfter);

  final Duration retryAfter;
}

final class NetworkFailure extends AuthFailure {
  const NetworkFailure();
}

/// The patient closed the Google / Apple sheet. Not an error to show.
final class SignInCancelled extends AuthFailure {
  const SignInCancelled();
}

/// Google / Apple sign-in is not configured in this build yet.
final class SocialUnavailable extends AuthFailure {
  const SocialUnavailable();
}
