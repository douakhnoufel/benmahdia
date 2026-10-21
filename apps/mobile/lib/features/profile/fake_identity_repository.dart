import 'dart:typed_data';

import 'identity_models.dart';
import 'identity_repository.dart';

/// In-memory [IdentityRepository] for running without the API and for tests.
class FakeIdentityRepository implements IdentityRepository {
  FakeIdentityRepository({
    IdentityState initial = const IdentityState(status: IdStatus.none),
    this.autoApprove = false,
  }) : _state = initial;

  /// Stands in for the clinic: a declared patient is approved the next time
  /// the status is read.
  final bool autoApprove;

  /// What the patient sent, in order.
  final submitted = <({IdentityDraft draft, Uint8List selfie})>[];

  /// Thrown by the next [declare], then cleared.
  IdentityFailure? failNext;

  IdentityState _state;

  /// The clinic approving, for tests.
  void approve() => _state = const IdentityState(status: IdStatus.approved);

  @override
  Future<IdentityState> status() async {
    final now = _state;
    if (autoApprove && now.status == IdStatus.declared) approve();
    return now;
  }

  @override
  Future<IdentityState> declare(
    IdentityDraft draft,
    Uint8List selfieJpeg,
  ) async {
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    submitted.add((draft: draft, selfie: selfieJpeg));
    return _state = IdentityState(
      status: IdStatus.declared,
      submissionsLeft: _state.submissionsLeft - 1,
    );
  }
}
