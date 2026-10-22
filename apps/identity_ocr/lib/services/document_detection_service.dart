import '../models/identity_document.dart';
import 'algerian_id_parser.dart';
import 'passport_mrz_parser.dart';

/// Parsing is selected from the user's document choice. This intentionally
/// does not claim to authenticate or auto-classify an identity document.
class DocumentDetectionService {
  const DocumentDetectionService({
    this.idParser = const AlgerianIdParser(),
    this.passportParser = const PassportMrzParser(),
  });

  final AlgerianIdParser idParser;
  final PassportMrzParser passportParser;

  IdentityDocument parse(DocumentType type, String rawOcrText) {
    return switch (type) {
      DocumentType.nationalId => idParser.parse(rawOcrText),
      DocumentType.passport => passportParser.parse(rawOcrText),
    };
  }
}
