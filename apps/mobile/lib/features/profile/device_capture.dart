import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'capture.dart';
import 'id_scan_screen.dart';
import 'id_text_parser.dart';
import 'identity_models.dart';
import 'selfie_screen.dart';

/// Opens the in-app scanner (live text recognition, nothing saved).
class LiveIdReader implements IdReader {
  @override
  Future<ScannedId?> scan(BuildContext context, IdDocType type) async {
    final result = await Navigator.of(context).push<IdScanResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => IdScanScreen(type: type),
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
