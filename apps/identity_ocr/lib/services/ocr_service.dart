import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'privacy_safe_log.dart';

class OcrService {
  OcrService({PrivacySafeLog? log}) : _log = log ?? PrivacySafeLog();

  final PrivacySafeLog _log;

  Future<String> recognizeFile(String path) async {
    _log.ocrStarted();
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      _log.ocrCompleted();
      return result.text;
    } catch (_) {
      _log.ocrFailed();
      rethrow;
    } finally {
      await recognizer.close();
    }
  }
}
