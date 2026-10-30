import 'dart:convert';

import 'package:benmahdia_mobile/features/articles/api_articles_repository.dart';
import 'package:benmahdia_mobile/features/articles/article_models.dart';
import 'package:benmahdia_mobile/features/articles/article_screen.dart';
import 'package:benmahdia_mobile/features/articles/articles_repository.dart';
import 'package:benmahdia_mobile/features/articles/articles_screen.dart';
import 'package:benmahdia_mobile/features/articles/fake_articles_repository.dart';
import 'package:benmahdia_mobile/features/recovery/fake_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_models.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

// The article library (PRD 5.5; backend/app/routers/articles.py).

http.Response _json(int status, Object? body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _summary({bool favourite = false}) => {
  'id': 'a-1',
  'title': 'Gérer une envie',
  'language': 'fr',
  'topic': 'cravings',
  'addiction_type': null,
  'published_at': '2026-10-17T10:00:00Z',
  'favourite': favourite,
};

Article _article(
  String id,
  String language,
  ArticleTopic topic,
  String title, {
  AddictionType? addiction,
}) => Article(
  summary: ArticleSummary(
    id: id,
    title: title,
    language: language,
    topic: topic,
    addictionType: addiction?.name,
  ),
  body: 'Premier paragraphe.\n\nDeuxième paragraphe.',
);

final _library = [
  _article('f-1', 'fr', ArticleTopic.cravings, 'Passer le cap d’une envie'),
  _article('f-2', 'fr', ArticleTopic.family, 'En parler à ses proches'),
  _article('a-1', 'ar', ArticleTopic.cravings, 'كيف تتجاوز لحظة الرغبة'),
  _article(
    'f-3',
    'fr',
    ArticleTopic.medication,
    'Arrêter les comprimés avec son médecin',
    addiction: AddictionType.pills,
  ),
  _article(
    'f-4',
    'fr',
    ArticleTopic.cravings,
    'Une journée sans tabac',
    addiction: AddictionType.tobacco,
  ),
  _article(
    'a-2',
    'ar',
    ArticleTopic.medication,
    'التوقف عن الأقراص مع طبيبك',
    addiction: AddictionType.pills,
  ),
  _article(
    'a-3',
    'ar',
    ArticleTopic.cravings,
    'يوم بلا تبغ',
    addiction: AddictionType.tobacco,
  ),
];

void main() {
  group('ApiArticlesRepository', () {
    late List<http.Request> sent;

    ApiArticlesRepository repo(http.Response Function(http.Request) answer) {
      sent = [];
      return ApiArticlesRepository(
        baseUrl: Uri.parse('https://api.test/'),
        token: () => 'token',
        refresh: () async => false,
        client: MockClient((r) async {
          sent.add(r);
          return answer(r);
        }),
      );
    }

    test(
      'lists in a language and topic, with favourites only on request',
      () async {
        final r = repo((_) => _json(200, [_summary(favourite: true)]));
        final list = await r.articles(
          language: 'fr',
          topic: ArticleTopic.cravings,
          favouritesOnly: true,
        );
        expect(sent.single.url.path, '/v1/me/articles');
        expect(sent.single.url.queryParameters, {
          'language': 'fr',
          'topic': 'cravings',
          'favourites': 'true',
        });
        expect(sent.single.headers['authorization'], 'Bearer token');
        expect(list.single.title, 'Gérer une envie');
        expect(list.single.topic, ArticleTopic.cravings);
        expect(list.single.favourite, isTrue);
      },
    );

    test('sends the addiction filter the API knows', () async {
      final r = repo((_) => _json(200, [_summary()]));
      await r.articles(language: 'ar', addictionType: AddictionType.tobacco);
      expect(sent.single.url.queryParameters, {
        'language': 'ar',
        'addiction_type': 'tobacco',
      });
    });

    test('reads an article and splits its paragraphs', () async {
      final r = repo(
        (_) => _json(200, {..._summary(), 'body': 'Un.\n\n  Deux.  \n\n\n'}),
      );
      final a = await r.article('a-1');
      expect(sent.single.url.path, '/v1/me/articles/a-1');
      expect(a.paragraphs, ['Un.', 'Deux.']);
    });

    test('saves and unsaves', () async {
      final r = repo((_) => http.Response('', 204));
      await r.setFavourite('a-1', favourite: true);
      await r.setFavourite('a-1', favourite: false);
      expect(sent.map((s) => '${s.method} ${s.url.path}'), [
        'PUT /v1/me/articles/a-1/favourite',
        'DELETE /v1/me/articles/a-1/favourite',
      ]);
    });

    test('a refusal or a malformed answer is "unavailable"', () async {
      expect(
        repo((_) => _json(404, {})).article('x'),
        throwsA(isA<ArticlesUnavailable>()),
      );
      expect(
        repo(
          (_) => _json(200, [
            {'id': 1},
          ]),
        ).articles(language: 'ar'),
        throwsA(isA<ArticlesUnavailable>()),
      );
    });
  });

  group('articles screens', () {
    // The sample patient tracks one addiction: pills (pregabalin).
    Future<FakeArticlesRepository> open(
      WidgetTester tester, {
      bool locked = false,
    }) async {
      final repo = FakeArticlesRepository(articles: _library);
      await pumpApp(
        tester,
        const ArticlesScreen(),
        overrides: [
          articlesRepositoryProvider.overrideWithValue(repo),
          recoveryRepositoryProvider.overrideWithValue(
            FakeRecoveryRepository(locked: locked),
          ),
        ],
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('Arabic shows the Arabic articles, right to left', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('مقالات'), findsOneWidget);
      expect(find.text('كيف تتجاوز لحظة الرغبة'), findsOneWidget);
      expect(find.text('Passer le cap d’une envie'), findsNothing);
      expect(directionOf(tester, ArticlesScreen), TextDirection.rtl);
    });

    testWidgets('switching to French shows the French ones, by topic', (
      tester,
    ) async {
      await open(tester);
      await useFrench(tester);
      await tester.pumpAndSettle();
      expect(find.text('Passer le cap d’une envie'), findsOneWidget);
      expect(find.text('En parler à ses proches'), findsOneWidget);

      final family = find.widgetWithText(ChoiceChip, 'Famille et soutien');
      await tester.ensureVisible(family);
      await tester.pumpAndSettle();
      await tester.tap(family);
      await tester.pumpAndSettle();
      expect(find.text('En parler à ses proches'), findsOneWidget);
      expect(find.text('Passer le cap d’une envie'), findsNothing);
    });

    testWidgets('reads an article, saves it and finds it in Saved', (
      tester,
    ) async {
      await open(tester);
      await useFrench(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Enregistrés'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Aucun article enregistré. Touchez le marque-page dans un article pour le garder.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Tous'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Passer le cap d’une envie'));
      await tester.pumpAndSettle();
      expect(find.byType(ArticleScreen), findsOneWidget);
      expect(find.text('Premier paragraphe.'), findsOneWidget);
      expect(find.text('Deuxième paragraphe.'), findsOneWidget);

      await tester.tap(find.byTooltip("Enregistrer l'article"));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Retirer des enregistrés'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Enregistrés'));
      await tester.pumpAndSettle();
      expect(find.text('Passer le cap d’une envie'), findsOneWidget);
      expect(find.text('En parler à ses proches'), findsNothing);
    });

    testWidgets('filters by the patient\'s own addiction, in French', (
      tester,
    ) async {
      await open(tester);
      await useFrench(tester);
      await tester.pumpAndSettle();
      expect(find.text('Une journée sans tabac'), findsOneWidget);
      // Only the patient's own addiction gets a chip.
      expect(find.widgetWithText(ChoiceChip, 'Tabac'), findsNothing);

      final pills = find.widgetWithText(ChoiceChip, 'Psychotropes (comprimés)');
      await tester.ensureVisible(pills);
      await tester.pumpAndSettle();
      await tester.tap(pills);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(pills).selected, isTrue);
      expect(
        find.text('Arrêter les comprimés avec son médecin'),
        findsOneWidget,
      );
      // Articles written for everyone stay in the list.
      expect(find.text('Passer le cap d’une envie'), findsOneWidget);
      expect(find.text('Une journée sans tabac'), findsNothing);

      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Tous'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tous'));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(pills).selected, isFalse);
      expect(find.text('Une journée sans tabac'), findsOneWidget);
    });

    testWidgets('filters by the patient\'s own addiction, in Arabic', (
      tester,
    ) async {
      await open(tester);
      expect(find.widgetWithText(ChoiceChip, 'التبغ'), findsNothing);
      final pills = find.widgetWithText(ChoiceChip, 'الأقراص المهلوسة');
      expect(Directionality.of(tester.element(pills)), TextDirection.rtl);

      await tester.ensureVisible(pills);
      await tester.pumpAndSettle();
      await tester.tap(pills);
      await tester.pumpAndSettle();
      expect(find.text('التوقف عن الأقراص مع طبيبك'), findsOneWidget);
      expect(find.text('كيف تتجاوز لحظة الرغبة'), findsOneWidget);
      expect(find.text('يوم بلا تبغ'), findsNothing);
    });

    testWidgets('before the first visit, the library opens without them', (
      tester,
    ) async {
      await open(tester, locked: true);
      expect(find.widgetWithText(ChoiceChip, 'الأقراص المهلوسة'), findsNothing);
      expect(find.text('كيف تتجاوز لحظة الرغبة'), findsOneWidget);
      expect(find.text('يوم بلا تبغ'), findsOneWidget);
    });
  });
}
