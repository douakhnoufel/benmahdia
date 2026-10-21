import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_companion_repository.dart';

/// Shortcuts the patient can tap instead of typing.
enum QuickReply { craving, breathing, doctor }

/// The companion's answer to one message.
class CompanionReply {
  const CompanionReply({
    required this.text,
    this.suggestBooking = false,
    this.crisis = false,
  });

  final String text;

  /// Offer a button to book an appointment under the reply.
  final bool suggestBooking;

  /// A crisis signal: the app shows the crisis screen (PRD 6.3).
  final bool crisis;
}

/// The AI companion (PRD 6). On the server, every message goes through the
/// crisis classifier first; the reply never contains a diagnosis or
/// medication advice (PRD 6.2).
abstract interface class CompanionRepository {
  /// Sends [text] (or the [quick] shortcut) and returns the reply in
  /// [languageCode].
  Future<CompanionReply> send(
    String text, {
    required String languageCode,
    QuickReply? quick,
  });
}

/// Pre-written replies until the AI service exists (PRD 6.4).
// TODO(companion-api): call the companion API when `API_BASE_URL` is set.
final companionRepositoryProvider = Provider<CompanionRepository>(
  (ref) => FakeCompanionRepository(),
);

/// Whether the patient accepted the companion's terms (PRD 6.3: consent at
/// first use). Kept for the session.
// TODO(companion-consent): store the consent on the server with a date.
class CompanionConsent extends Notifier<bool> {
  @override
  bool build() => false;

  void accept() => state = true;
}

final companionConsentProvider = NotifierProvider<CompanionConsent, bool>(
  CompanionConsent.new,
);
