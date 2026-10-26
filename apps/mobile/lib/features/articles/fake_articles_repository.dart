import 'article_models.dart';
import 'articles_repository.dart';

/// Sample articles for running without a server. Placeholder text: the
/// clinic's doctors write or approve the real ones (PRD 5.5).
class FakeArticlesRepository implements ArticlesRepository {
  FakeArticlesRepository({List<Article>? articles})
    : _articles = articles ?? _samples;

  final List<Article> _articles;
  final Set<String> _favourites = {};

  static final _samples = [
    _sample('s-1', 'fr', ArticleTopic.cravings, 'Passer le cap d’une envie', [
      'Une envie monte, atteint un pic puis redescend. Elle dure rarement plus de vingt minutes.',
      'Pendant ce temps : respirez lentement, buvez un verre d’eau, sortez marcher ou appelez quelqu’un.',
    ]),
    _sample('s-2', 'fr', ArticleTopic.family, 'En parler à ses proches', [
      'Choisissez un moment calme et une personne de confiance.',
      'Dites ce dont vous avez besoin : de l’écoute, de l’aide pour les rendez-vous, de la patience.',
    ]),
    _sample('s-3', 'ar', ArticleTopic.cravings, 'كيف تتجاوز لحظة الرغبة', [
      'الرغبة ترتفع ثم تبلغ ذروتها ثم تنخفض. نادرا ما تدوم أكثر من عشرين دقيقة.',
      'خلال هذه المدة: تنفّس ببطء، اشرب كأس ماء، اخرج للمشي أو اتصل بشخص تثق به.',
    ]),
    _sample('s-4', 'ar', ArticleTopic.motivation, 'كل يوم يُحسب', [
      'لا تنظر إلى الطريق كله. ركّز على اليوم فقط.',
      'كل يوم دون تعاطٍ خطوة حقيقية، حتى لو كان صعبا.',
    ]),
  ];

  static Article _sample(
    String id,
    String language,
    ArticleTopic topic,
    String title,
    List<String> paragraphs,
  ) => Article(
    summary: ArticleSummary(
      id: id,
      title: title,
      language: language,
      topic: topic,
      publishedAt: DateTime(2026, 10, 15),
    ),
    body: paragraphs.join('\n\n'),
  );

  ArticleSummary _withState(ArticleSummary s) =>
      s.withFavourite(_favourites.contains(s.id));

  @override
  Future<List<ArticleSummary>> articles({
    required String language,
    ArticleTopic? topic,
    bool favouritesOnly = false,
  }) async => [
    for (final a in _articles)
      if (a.summary.language == language &&
          (topic == null || a.summary.topic == topic) &&
          (!favouritesOnly || _favourites.contains(a.summary.id)))
        _withState(a.summary),
  ];

  @override
  Future<Article> article(String id) async {
    final a = _articles.firstWhere(
      (a) => a.summary.id == id,
      orElse: () => throw const ArticlesUnavailable(),
    );
    return Article(summary: _withState(a.summary), body: a.body);
  }

  @override
  Future<void> setFavourite(String id, {required bool favourite}) async {
    favourite ? _favourites.add(id) : _favourites.remove(id);
  }
}
