import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_capture.dart';
import 'id_text_parser.dart';

/// The card could not be read; the patient types the details instead.
class IdReadFailed implements Exception {
  const IdReadFailed();
}

/// Reads the ID card with the phone. The picture is read on the phone and
/// deleted right after: only the text it contained leaves this class.
abstract interface class IdReader {
  /// Null when the patient closed the camera. Throws [IdReadFailed].
  Future<ScannedId?> scan();
}

/// Takes the live selfie that goes to the doctor.
abstract interface class SelfieCamera {
  /// A JPEG, or null when the patient closed the camera.
  Future<Uint8List?> take();
}

final idReaderProvider = Provider<IdReader>((ref) => MlKitIdReader());
final selfieCameraProvider = Provider<SelfieCamera>(
  (ref) => PhoneSelfieCamera(),
);
