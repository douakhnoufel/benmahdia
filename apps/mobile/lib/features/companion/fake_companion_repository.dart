import 'companion_repository.dart';

/// Demo companion: fixed, safe replies, and a keyword check for crisis words
/// standing in for the server's classifier.
class FakeCompanionRepository implements CompanionRepository {
  FakeCompanionRepository({this.delay = const Duration(milliseconds: 900)});

  final Duration delay;

  /// Words that open the crisis screen (Arabic, Darja, French). The real
  /// check runs on the server (PRD 6.3); this one only keeps the demo safe.
  static const crisisWords = [
    'انتحار',
    'انتحر',
    'أنتحر',
    'اقتل نفسي',
    'أقتل نفسي',
    'نقتل روحي',
    'أؤذي نفسي',
    'اوذي نفسي',
    'جرعة زائدة',
    'أريد أن أموت',
    'نحب نموت',
    'suicide',
    'suicider',
    'me tuer',
    'mourir',
    'me faire du mal',
    'overdose',
    'surdose',
  ];

  static bool isCrisis(String text) {
    final t = text.toLowerCase();
    return crisisWords.any(t.contains);
  }

  @override
  Future<CompanionReply> send(
    String text, {
    required String languageCode,
    QuickReply? quick,
  }) async {
    await Future<void>.delayed(delay);
    final ar = languageCode == 'ar';
    if (isCrisis(text)) {
      return CompanionReply(
        crisis: true,
        text: ar
            ? 'أنا قلق عليك. سلامتك أهم شيء الآن. اتصل بالعيادة أو بالطوارئ فوراً، ولست وحدك.'
            : "Je m'inquiète pour vous. Votre sécurité passe avant tout : appelez le cabinet ou les urgences maintenant. Vous n'êtes pas seul(e).",
      );
    }
    return switch (quick) {
      QuickReply.craving => CompanionReply(
        text: ar
            ? 'شكراً لأنك قلتها بصراحة، هذا بحد ذاته خطوة. الرغبة تأتي كموجة ثم تهدأ. هل نجرّب معاً تمرين تنفّس لدقيقتين؟'
            : "Merci de me le dire, c'est déjà un pas. L'envie monte comme une vague, puis redescend. On essaie ensemble un exercice de respiration de deux minutes ?",
      ),
      QuickReply.breathing => CompanionReply(
        text: ar
            ? 'لنبدأ: شهيق من الأنف وأنت تعدّ إلى أربعة، احبس نفسك أربعاً، ثم زفير بطيء من الفم إلى ستة. كرّرها خمس مرات، ثم أخبرني كيف تشعر.'
            : "Commençons : inspirez par le nez en comptant jusqu'à quatre, retenez quatre secondes, puis expirez lentement par la bouche jusqu'à six. Répétez cinq fois, puis dites-moi comment vous vous sentez.",
      ),
      QuickReply.doctor => CompanionReply(
        suggestBooking: true,
        text: ar
            ? 'فكرة جيدة. طبيبك هو أفضل من يساعدك في هذا. يمكنك حجز أقرب موعد الآن.'
            : "Bonne idée. Votre médecin est le mieux placé pour vous aider. Vous pouvez réserver le prochain créneau dès maintenant.",
      ),
      null => CompanionReply(
        text: ar
            ? 'شكراً لأنك شاركتني. أنا هنا معك. هل تريد أن نجرّب تمرين التنفّس، أم أن تحجز موعداً مع طبيبك؟'
            : 'Merci de partager cela avec moi. Je suis là. Voulez-vous essayer un exercice de respiration, ou prendre rendez-vous avec votre médecin ?',
      ),
    };
  }
}
