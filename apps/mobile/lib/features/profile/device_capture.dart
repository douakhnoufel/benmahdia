import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'capture.dart';
import 'id_scan_screen.dart';
import 'id_text_parser.dart';
import 'identity_models.dart';
import 'scan_logic.dart';
import 'selfie_screen.dart';

/// Opens the in-app scanner (live text recognition, nothing saved).
class LiveIdReader implements IdReader {
  @override
  Future<ScannedId?> scan(BuildContext context, IdDocType type) async {
    // The national ID card is read on both sides: the front for the number and
    // birth date, then the back's machine-readable zone for the Latin name.
    // The passport has a single machine-readable page.
    if (type == IdDocType.passport) {
      return _one(context, type, IdSide.front);
    }
    final front = await _one(context, type, IdSide.front);
    if (front == null || !context.mounted) return front;
    final back = await _one(context, type, IdSide.back);
    if (back == null) return front;
    return front.mergeBack(back);
  }

  Future<ScannedId?> _one(BuildContext context, IdDocType type, IdSide side) async {
    final result = await Navigator.of(context).push<IdScanResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => IdScanScreen(type: type, side: side),
      ),
    );
    return switch (result) {
      IdScanRead(:final id) => id,
      IdScanCameraUnavailable() => throw const IdReadFailed(),
      null => null,
    };
  }
}

/// Opens the in-app front camera with the face check.
class InAppSelfieCamera implements SelfieCamera {
  @override
  Future<Uint8List?> take(BuildContext context) =>
      Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => const SelfieScreen(),
        ),
      );
}
