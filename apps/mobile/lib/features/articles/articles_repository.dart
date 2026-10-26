import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import 'api_articles_repository.dart';
import 'article_models.dart';
import 'fake_articles_repository.dart';

/// The clinic's article library (PRD 5.5): published articles, readable at
/// any time, filtered by language and topic, with the patient's favourites.
abstract interface class ArticlesRepository {
  /// Published articles in [language], newest first.
  Future<List<ArticleSummary>> articles({
    required String language,
    ArticleTopic? topic,
    bool favouritesOnly = false,
  });

  Future<Article> article(String id);

  Future<void> setFavourite(String id, {required bool favourite});
}

/// The articles API when `API_BASE_URL` is set, otherwise sample articles.
final articlesRepositoryProvider = Provider<ArticlesRepository>((ref) {
  if (apiBaseUrl.isEmpty) return FakeArticlesRepository();
  final auth = ref.read(authRepositoryProvider);
  return ApiArticlesRepository(
    baseUrl: Uri.parse(apiBaseUrl),
    token: () => ref.read(sessionProvider)?.accessToken,
    refresh: () async {
      final session = ref.read(sessionProvider);
      if (session == null) return false;
      try {
        final AuthSession fresh = await auth.refresh(session);
        ref.read(sessionProvider.notifier).set(fresh);
        return true;
      } on AuthFailure {
        return false;
      }
    },
  );
});
