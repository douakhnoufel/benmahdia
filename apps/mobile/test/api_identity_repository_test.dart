import 'dart:convert';
import 'dart:typed_data';

import 'package:benmahdia_mobile/features/profile/api_identity_repository.dart';
import 'package:benmahdia_mobile/features/profile/identity_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(int status, Object? body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _error(int status, String code) =>
    _json(status, {'detail': {'code': code}});

final _draft = IdentityDraft(
  idNumber: '123456789012345678',
  fullName: 'Karim Benali',
  birthDate: DateTime(1990, 5, 17),
);
final _selfie = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

ApiIdentityRepository _repo(
  MockClient client, {
  String? Function()? token,
  Future<bool> Function()? refresh,
}) => ApiIdentityRepository(
  baseUrl: Uri.parse('http://api.test/'),
  token: token ?? () => 'tok',
  refresh: refresh ?? () async => false,
  client: client,
);

void main() {
  test('reads the status with the bearer token', () async {
    late http.Request seen;
    final repo = _repo(
      MockClient((request) async {
        seen = request;
        return _json(200, {
          'status': 'rejected',
          'reject_reason': 'Photo floue',
          'submissions_left': 3,
        });
      }),
    );
    final state = await repo.status();
    expect(seen.method, 'GET');
    expect(seen.url.path, '/v1/me/identity');
    expect(seen.headers['authorization'], 'Bearer tok');
    expect(state.status, IdStatus.rejected);
    expect(state.rejectReason, 'Photo floue');
    expect(state.submissionsLeft, 3);
    expect(state.canSubmit, isTrue);
  });

  test('maps every status', () async {
    for (final (wire, status) in [
      ('none', IdStatus.none),
      ('declared', IdStatus.declared),
      ('approved', IdStatus.approved),
    ]) {
      final repo = _repo(
        MockClient(
          (_) async => _json(200, {'status': wire, 'submissions_left': 4}),
        ),
      );
      expect((await repo.status()).status, status);
    }
  });

  test('declares the three fields and the selfie, nothing else', () async {
    late Map<String, dynamic> body;
    final repo = _repo(
      MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/me/identity');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(201, {'status': 'declared', 'submissions_left': 3});
      }),
    );
    final state = await repo.declare(_draft, _selfie);
    expect(state.status, IdStatus.declared);
    expect(body.keys.toSet(), {
      'id_number',
      'full_name',
      'birth_date',
      'selfie_jpeg_base64',
    });
    expect(body['id_number'], '123456789012345678');
    expect(body['full_name'], 'Karim Benali');
    expect(body['birth_date'], '1990-05-17');
    expect(base64Decode(body['selfie_jpeg_base64'] as String), _selfie);
  });

  test('refreshes the token once after a 401', () async {
    var calls = 0;
    var token = 'old';
    final repo = _repo(
      MockClient((request) async {
        calls++;
        if (request.headers['authorization'] == 'Bearer old') {
          return _error(401, 'unauthorized');
        }
        return _json(200, {'status': 'none', 'submissions_left': 4});
      }),
      token: () => token,
      refresh: () async {
        token = 'new';
        return true;
      },
    );
    expect((await repo.status()).status, IdStatus.none);
    expect(calls, 2);
  });

  group('failures', () {
    Future<Object> failure(int status, String code) async {
      final repo = _repo(MockClient((_) async => _error(status, code)));
      try {
        await repo.declare(_draft, _selfie);
      } on IdentityFailure catch (f) {
        return f;
      }
      throw StateError('did not fail');
    }

    test('an ID linked to another account', () async {
      expect(await failure(409, 'id_already_linked'), isA<IdAlreadyLinked>());
    });

    test('too many submissions', () async {
      expect(
        await failure(403, 'too_many_submissions'),
        isA<TooManySubmissions>(),
      );
    });

    test('already sent or approved', () async {
      expect(await failure(409, 'already_declared'), isA<AlreadyDecided>());
      expect(await failure(409, 'already_approved'), isA<AlreadyDecided>());
    });

    test('a refused field says which one', () async {
      final cases = {
        'invalid_id_number': IdField.idNumber,
        'invalid_name': IdField.fullName,
        'invalid_birth_date': IdField.birthDate,
        'invalid_selfie': IdField.selfie,
      };
      for (final entry in cases.entries) {
        final f = await failure(422, entry.key);
        expect(f, isA<InvalidDetails>());
        expect((f as InvalidDetails).field, entry.value);
      }
    });

    test('anything else, or no network, reads as unavailable', () async {
      expect(await failure(500, 'boom'), isA<IdentityUnavailable>());
      final offline = _repo(
        MockClient((_) async => throw http.ClientException('down')),
      );
      expect(offline.status(), throwsA(isA<IdentityUnavailable>()));
    });
  });
}
