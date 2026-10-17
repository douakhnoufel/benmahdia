import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_auth_repository.dart';
import 'auth_models.dart';
import 'fake_auth_repository.dart';
import 'phone_number.dart';

/// Accounts and sessions. The server is the authority: it sends the SMS
/// codes, counts attempts, locks accounts and checks Google / Apple tokens
/// (PRD 4.1). Methods throw [AuthFailure].
abstract interface class AuthRepository {
  /// Sends a 6-digit code to [phone]. For [OtpPurpose.signUp] and
  /// [OtpPurpose.attachPhone] throws [PhoneTaken] if the number has an
  /// account.
  Future<OtpTicket> requestCode(PhoneNumber phone, OtpPurpose purpose);

  /// Checks [code] and returns a short-lived proof that [phone] received it.
  Future<String> verifyCode(PhoneNumber phone, OtpPurpose purpose, String code);

  /// Creates a phone + password account from a sign-up proof.
  Future<AuthSession> register({
    required String phoneProof,
    required String password,
    required String language,
  });

  Future<AuthSession> logIn(PhoneNumber phone, String password);

  /// Sets a new password from a reset proof and signs in.
  Future<AuthSession> resetPassword({
    required String phoneProof,
    required String password,
  });

  Future<AuthSession> signInWithGoogle({required String language});

  Future<AuthSession> signInWithApple({required String language});

  /// Adds the confirmed number to a Google / Apple account.
  Future<AuthSession> attachPhone(AuthSession session, String phoneProof);

  /// Swaps the refresh token for a new pair when the access token ran out.
  /// Throws [AuthFailure] if the login is no longer valid.
  Future<AuthSession> refresh(AuthSession session);
}

/// The API's address, e.g.
/// `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/`
/// (Android emulator → this computer). Without it the app uses
/// [FakeAuthRepository], where every SMS code is 123456.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => apiBaseUrl.isEmpty
      ? FakeAuthRepository()
      : ApiAuthRepository(baseUrl: Uri.parse(apiBaseUrl)),
);

/// The signed-in patient, or null.
// TODO(auth): keep the refresh token in secure storage across launches.
class SessionNotifier extends Notifier<AuthSession?> {
  @override
  AuthSession? build() => null;

  void set(AuthSession session) => state = session;

  void clear() => state = null;
}

final sessionProvider = NotifierProvider<SessionNotifier, AuthSession?>(
  SessionNotifier.new,
);
