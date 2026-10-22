import 'package:flutter/foundation.dart';

/// The API accepts no document values, paths, OCR text, or exception objects.
/// This keeps operational logging useful without creating a PII log channel.
class PrivacySafeLog {
  PrivacySafeLog({void Function(String message)? sink})
    : _sink = sink ?? debugPrint;

  final void Function(String message) _sink;

  void ocrStarted() => _sink('local_ocr_started');
  void ocrCompleted() => _sink('local_ocr_completed');
  void ocrFailed() => _sink('local_ocr_failed');
}
