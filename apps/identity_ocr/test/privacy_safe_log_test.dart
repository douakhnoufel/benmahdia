import 'package:flutter_test/flutter_test.dart';
import 'package:identity_ocr/models/identity_document.dart';
import 'package:identity_ocr/services/privacy_safe_log.dart';

void main() {
  test('operational logs cannot contain document fields or raw OCR values', () {
    const sentinel = 'SYNTHETIC_SENSITIVE_VALUE_123456789';
    final document = IdentityDocument(
      documentType: DocumentType.nationalId,
      documentNumber: sentinel,
      rawOcrText: sentinel,
    );
    final output = <String>[];
    final log = PrivacySafeLog(sink: output.add);

    log.ocrStarted();
    log.ocrCompleted();
    log.ocrFailed();

    expect(document.documentNumber, sentinel);
    expect(output, [
      'local_ocr_started',
      'local_ocr_completed',
      'local_ocr_failed',
    ]);
    expect(output.join(' '), isNot(contains(sentinel)));
  });
}
