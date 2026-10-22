import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../auth/auth_widgets.dart';
import 'capture.dart';
import 'id_text_parser.dart';
import 'identity_models.dart';
import 'identity_repository.dart';

/// Scan the ID card (read on the phone, never saved), check the three
/// fields, take a selfie, send. The patient can always type the details
/// instead of scanning.
class ProfileFormScreen extends ConsumerStatefulWidget {
  const ProfileFormScreen({super.key, required this.onSent});

  /// The clinic has the details; it will review them.
  final VoidCallback onSent;

  @override
  ConsumerState<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends ConsumerState<ProfileFormScreen> {
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _birth = TextEditingController();
  final _errors = <IdField, String>{};
  Uint8List? _selfie;
  IdDocType _type = IdDocType.nationalId;
  bool _scanned = false;
  bool _scanning = false;
  bool _sending = false;
  String? _failure;

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _birth.dispose();
    super.dispose();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _scan() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _scanning = true;
      _failure = null;
    });
    try {
      final scanned = await ref.read(idReaderProvider).scan(context, _type);
      if (!mounted || scanned == null) return;
      setState(() {
        _scanned = true;
        final number = scanned.idNumber;
        final birth = scanned.birthDate;
        final name = scanned.fullName;
        if (number != null) _id.text = number;
        if (birth != null) _birth.text = _iso(birth);
        if (name != null && _name.text.trim().isEmpty) {
          _name.text = name;
          _errors.remove(IdField.fullName);
        }
        _errors.remove(IdField.idNumber);
        _errors.remove(IdField.birthDate);
      });
    } on IdReadFailed {
      if (mounted) setState(() => _failure = l10n.profileScanFailed);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _selfieShot() async {
    final bytes = await ref.read(selfieCameraProvider).take(context);
    if (!mounted || bytes == null) return;
    setState(() {
      _selfie = bytes;
      _errors.remove(IdField.selfie);
    });
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final number = normalizeIdNumber(_id.text);
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final birth = parseDate(_birth.text, today: DateTime.now());
    final selfie = _selfie;
    final errors = <IdField, String>{
      if (!RegExp(r'^[A-Z0-9]{6,30}$').hasMatch(number))
        IdField.idNumber: l10n.profileErrIdNumber,
      if (name.length < 2 || !RegExp(r'\p{L}', unicode: true).hasMatch(name))
        IdField.fullName: l10n.profileErrName,
      if (birth == null) IdField.birthDate: l10n.profileErrBirth,
      if (selfie == null) IdField.selfie: l10n.profileErrSelfie,
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _failure = null;
    });
    if (errors.isNotEmpty || birth == null || selfie == null) return;

    setState(() => _sending = true);
    try {
      await ref
          .read(identityRepositoryProvider)
          .declare(
            IdentityDraft(
              idType: _type,
              idNumber: number,
              fullName: name,
              birthDate: birth,
            ),
            selfie,
          );
      ref.invalidate(identityStateProvider);
      if (mounted) widget.onSent();
    } on AlreadyDecided {
      ref.invalidate(identityStateProvider);
      if (mounted) widget.onSent();
    } on InvalidDetails catch (f) {
      if (mounted) {
        setState(() {
          if (f.field == IdField.selfie) {
            _selfie = null;
            _failure = l10n.profileErrSelfieInvalid;
          } else {
            _failure = l10n.profileErrInvalid;
          }
        });
      }
    } on IdentityFailure catch (f) {
      if (mounted) setState(() => _failure = identityFailureText(l10n, f));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = _scanning || _sending;
    return AuthPage(
      title: l10n.profileFormTitle,
      body: l10n.profileFormBody,
      children: [
        SegmentedButton<IdDocType>(
          key: const ValueKey('profile-doc-type'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: IdDocType.nationalId,
              icon: const Icon(Icons.badge_outlined),
              label: Text(l10n.profileDocNationalId),
            ),
            ButtonSegment(
              value: IdDocType.passport,
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(l10n.profileDocPassport),
            ),
          ],
          selected: {_type},
          onSelectionChanged: busy
              ? null
              : (picked) => setState(() {
                  // A different document: its number must be read again.
                  _type = picked.single;
                  _id.clear();
                  _scanned = false;
                  _errors.remove(IdField.idNumber);
                }),
        ),
        OutlinedButton.icon(
          key: const ValueKey('profile-scan'),
          onPressed: busy ? null : _scan,
          icon: _scanning
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.document_scanner_outlined),
          label: Text(
            _scanned
                ? l10n.profileScanAgain
                : _type == IdDocType.passport
                ? l10n.profileScanPassport
                : l10n.profileScan,
          ),
        ),
        TextField(
          key: const ValueKey('profile-id'),
          controller: _id,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 \-]')),
          ],
          decoration: InputDecoration(
            labelText: _type == IdDocType.passport
                ? l10n.profilePassportNumber
                : l10n.profileIdNumber,
            errorText: _errors[IdField.idNumber],
          ),
        ),
        TextField(
          key: const ValueKey('profile-name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.profileFullName,
            errorText: _errors[IdField.fullName],
          ),
        ),
        TextField(
          key: const ValueKey('profile-birth'),
          controller: _birth,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.datetime,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9\-/.]')),
          ],
          decoration: InputDecoration(
            labelText: l10n.profileBirthDate,
            hintText: '1990-05-17',
            errorText: _errors[IdField.birthDate],
          ),
        ),
        OutlinedButton.icon(
          key: const ValueKey('profile-selfie'),
          onPressed: busy ? null : _selfieShot,
          icon: Icon(
            _selfie == null ? Icons.photo_camera_front_outlined : Icons.check,
          ),
          label: Text(
            _selfie == null
                ? l10n.profileSelfie
                : '${l10n.profileSelfieReady} · ${l10n.profileSelfieRetake}',
          ),
        ),
        if (_errors[IdField.selfie] case final message?)
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.danger),
          ),
        FailureNote(message: _failure),
        BusyButton(
          key: const ValueKey('profile-submit'),
          label: l10n.profileSubmit,
          busy: _sending,
          onPressed: busy ? null : _send,
        ),
      ],
    );
  }
}

/// The words for each way sending can fail, or null when nothing is shown.
String? identityFailureText(AppLocalizations l10n, IdentityFailure failure) =>
    switch (failure) {
      IdAlreadyLinked() => l10n.profileErrLinked,
      TooManySubmissions() => l10n.profileErrTooMany,
      InvalidDetails(:final field) =>
        field == IdField.selfie
            ? l10n.profileErrSelfieInvalid
            : l10n.profileErrInvalid,
      AlreadyDecided() => null,
      IdentityUnavailable() => l10n.authNetwork,
    };
