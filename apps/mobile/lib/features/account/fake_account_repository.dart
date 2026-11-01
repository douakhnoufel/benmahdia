import '../auth/fake_auth_repository.dart';
import 'account_models.dart';
import 'account_repository.dart';

/// In-memory account for running without the API and for tests.
class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({
    Me? initial,
    String password = FakeAuthRepository.samplePassword,
  }) : _me =
           initial ??
           Me(
             id: 'u1',
             phone: FakeAuthRepository.samplePhone.e164,
             email: null,
             language: 'ar',
             hasPassword: true,
             providers: const [],
             idStatus: MeIdStatus.approved,
           ),
       _password = password;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Me? _me;
  final String _password;

  @override
  Future<Me> me() async => _me ?? (throw const AccountUnavailable());

  @override
  Future<Me> setEmail(String? email) async {
    final account = await me();
    final value = email?.trim().toLowerCase();
    if (value != null &&
        value.isNotEmpty &&
        (value.length > 320 || !_emailPattern.hasMatch(value))) {
      throw const InvalidEmail();
    }
    final updated = account.copyWith(
      email: () => value == null || value.isEmpty ? null : value,
    );
    _me = updated;
    return updated;
  }

  @override
  Future<void> deleteAccount({String? password}) async {
    final account = await me();
    if (account.hasPassword && password != _password) {
      throw const WrongPassword();
    }
    _me = null;
  }
}
