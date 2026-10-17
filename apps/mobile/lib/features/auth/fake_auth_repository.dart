import 'auth_models.dart';
import 'auth_repository.dart';
import 'phone_number.dart';

/// In-memory stand-in for the auth API. It follows the server's rules: a
/// 60 s wait between codes, codes valid 5 minutes with 5 tries, and 5 wrong
/// passwords locking the account for 15 minutes. Every code is [devCode].
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _accounts[samplePhone] = _Account(id: 'u1', password: samplePassword)
      ..verified = true;
  }

  /// The code every "SMS" carries.
  static const devCode = '123456';

  /// A sample account that already exists, already verified by the clinic.
  static final samplePhone = PhoneNumber.tryParse('0550123456')!;
  static const samplePassword = 'sobre2026';

  static const resendAfter = Duration(seconds: 60);
  static const codeLife = Duration(minutes: 5);
  static const maxAttempts = 5;
  static const lockFor = Duration(minutes: 15);

  final DateTime Function() _clock;
  final _accounts = <PhoneNumber, _Account>{};
  final _codes = <(PhoneNumber, OtpPurpose), _Code>{};
  final _proofs = <String, (PhoneNumber, OtpPurpose)>{};
  var _next = 2;

  @override
  Future<OtpTicket> requestCode(PhoneNumber phone, OtpPurpose purpose) async {
    final exists = _accounts.containsKey(phone);
    if (exists && purpose != OtpPurpose.resetPassword) throw const PhoneTaken();
    final previous = _codes[(phone, purpose)];
    final now = _clock();
    if (previous != null) {
      final wait = previous.sentAt.add(resendAfter).difference(now);
      if (wait > Duration.zero) throw RateLimited(wait);
    }
    // A reset for an unknown number looks the same but sends nothing, so
    // the screen never reveals who has an account.
    if (exists || purpose != OtpPurpose.resetPassword) {
      _codes[(phone, purpose)] = _Code(now);
    }
    return const OtpTicket(resendAfter: resendAfter);
  }

  @override
  Future<String> verifyCode(
    PhoneNumber phone,
    OtpPurpose purpose,
    String code,
  ) async {
    final sent = _codes[(phone, purpose)];
    if (sent == null || _clock().isAfter(sent.sentAt.add(codeLife))) {
      throw const CodeExpired();
    }
    if (sent.attempts >= maxAttempts) throw const TooManyAttempts();
    if (code != devCode) {
      sent.attempts++;
      throw sent.attempts >= maxAttempts
          ? const TooManyAttempts()
          : const WrongCode();
    }
    _codes.remove((phone, purpose));
    final proof = 'proof-${_next++}';
    _proofs[proof] = (phone, purpose);
    return proof;
  }

  PhoneNumber _use(String proof, OtpPurpose purpose) {
    final entry = _proofs.remove(proof);
    if (entry == null || entry.$2 != purpose) throw const CodeExpired();
    return entry.$1;
  }

  AuthSession _session(_Account account, PhoneNumber? phone) => AuthSession(
    accessToken: 'access-${account.id}',
    refreshToken: 'refresh-${account.id}',
    user: AuthUser(id: account.id, verified: account.verified, phone: phone),
  );

  @override
  Future<AuthSession> register({
    required String phoneProof,
    required String password,
    required String language,
  }) async {
    final phone = _use(phoneProof, OtpPurpose.signUp);
    if (_accounts.containsKey(phone)) throw const PhoneTaken();
    final account = _Account(id: 'u${_next++}', password: password);
    _accounts[phone] = account;
    return _session(account, phone);
  }

  @override
  Future<AuthSession> logIn(PhoneNumber phone, String password) async {
    final account = _accounts[phone];
    if (account == null || account.password == null) {
      throw const WrongCredentials();
    }
    final now = _clock();
    final locked = account.lockedUntil;
    if (locked != null && locked.isAfter(now)) {
      throw AccountLocked(locked.difference(now));
    }
    if (account.password != password) {
      account.failures++;
      if (account.failures >= maxAttempts) {
        account
          ..failures = 0
          ..lockedUntil = now.add(lockFor);
        throw const AccountLocked(lockFor);
      }
      throw const WrongCredentials();
    }
    account
      ..failures = 0
      ..lockedUntil = null;
    return _session(account, phone);
  }

  @override
  Future<AuthSession> resetPassword({
    required String phoneProof,
    required String password,
  }) async {
    final phone = _use(phoneProof, OtpPurpose.resetPassword);
    final account = _accounts[phone];
    if (account == null) throw const CodeExpired();
    account
      ..password = password
      ..failures = 0
      ..lockedUntil = null;
    return _session(account, phone);
  }

  @override
  Future<AuthSession> signInWithGoogle({required String language}) async =>
      _session(_Account(id: 'u${_next++}'), null);

  @override
  Future<AuthSession> signInWithApple({required String language}) async =>
      _session(_Account(id: 'u${_next++}'), null);

  @override
  Future<AuthSession> attachPhone(
    AuthSession session,
    String phoneProof,
  ) async {
    final phone = _use(phoneProof, OtpPurpose.attachPhone);
    if (_accounts.containsKey(phone)) throw const PhoneTaken();
    _accounts[phone] = _Account(id: session.user.id);
    return session.withUser(session.user.withPhone(phone));
  }
}

class _Account {
  _Account({required this.id, this.password});

  final String id;
  String? password;
  int failures = 0;
  DateTime? lockedUntil;
  bool verified = false;
}

class _Code {
  _Code(this.sentAt);

  final DateTime sentAt;
  int attempts = 0;
}
