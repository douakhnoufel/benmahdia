import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'capture.dart';
import 'id_text_parser.dart';

Future<void> _forget(String path) async {
  try {
    await File(path).delete();
  } on FileSystemException {
    // Already gone.
  }
}

/// Reads the card with the phone camera and on-device text recognition
/// (Google ML Kit). Nothing is uploaded and the photo is deleted afterwards.
class MlKitIdReader implements IdReader {
  MlKitIdReader({ImagePicker? picker, DateTime Function()? clock})
    : _picker = picker ?? ImagePicker(),
      _clock = clock ?? DateTime.now;

  final ImagePicker _picker;
  final DateTime Function() _clock;

  @override
  Future<ScannedId?> scan() async {
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (shot == null) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(shot.path),
      );
      final scanned = parseIdText(result.text, today: _clock());
      if (scanned.isEmpty) throw const IdReadFailed();
      return scanned;
    } on IdReadFailed {
      rethrow;
    } on Exception {
      throw const IdReadFailed();
    } finally {
      await recognizer.close();
      await _forget(shot.path);
    }
  }
}

/// Front camera, small JPEG (the server accepts up to 2 MB).
class PhoneSelfieCamera implements SelfieCamera {
  PhoneSelfieCamera({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> take() async {
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (shot == null) return null;
    try {
      return await shot.readAsBytes();
    } finally {
      await _forget(shot.path);
    }
  }
}
