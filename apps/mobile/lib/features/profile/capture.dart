import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_capture.dart';
import 'id_text_parser.dart';
import 'identity_models.dart';

/// The card could not be read; the patient types the details instead.
class IdReadFailed implements Exception {
  const IdReadFailed();
}

/// Reads the ID card or passport with the phone's camera. Frames are read in
/// memory on the phone: no picture is saved or uploaded, only the text found
/// leaves this class (PRD 4.2).
abstract interface class IdReader {
  /// Null when the patient closed the scanner or chose to type instead.
  /// Throws [IdReadFailed] when the camera can't be used.
  Future<ScannedId?> scan(BuildContext context, IdDocType type);
}

/// Takes the selfie that goes to the doctor.
abstract interface class SelfieCamera {
  /// A JPEG, or null when the patient closed the camera.
  Future<Uint8List?> take(BuildContext context);
}

final idReaderProvider = Provider<IdReader>((ref) => LiveIdReader());
final selfieCameraProvider = Provider<SelfieCamera>(
  (ref) => InAppSelfieCamera(),
);
