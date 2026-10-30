import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../booking/booking_widgets.dart';
import '../recovery/recovery_models.dart';
import '../recovery/recovery_repository.dart';
import 'article_models.dart';
import 'article_screen.dart';
import 'articles_repository.dart';

/// Opens the article library on top of the current tab.
void openArticles(BuildContext context) {
  unawaited(
    Navigator.of(context).push<void>(
      appRoute(const ArticlesScreen(), reduced: AppMotion.reduced(context)),
    ),
  );
}

String topicName(AppLocalizations l10n, ArticleTopic topic) => switch (topic) {
  ArticleTopic.addiction => l10n.articleTopicAddiction,
  ArticleTopic.cravings => l10n.articleTopicCravings,
  ArticleTopic.relapse => l10n.articleTopicRelapse,
  ArticleTopic.medication => l10n.articleTopicMedication,
  ArticleTopic.family => l10n.articleTopicFamily,
  ArticleTopic.motivation => l10n.articleTopicMotivation,
};

/// The clinic's articles in the app's language (PRD 5.5), by topic or by one
/// of the patient's own addictions, with the saved ones a tap away. Readable
/// at any time, even before the first visit.
class ArticlesScreen extends ConsumerStatefulWidget {
  const ArticlesScreen({super.key});

  @override
  ConsumerState<ArticlesScreen> createState() => _ArticlesScreenState();
}

class _ArticlesScreenState extends ConsumerState<ArticlesScreen> {
  ArticleTopic? _topic;
  AddictionType? _addiction;
  bool _saved = false;
  String? _language;
  Future<List<ArticleSummary>>? _articles;

  /// The patient's own addiction types, one chip each.
  List<AddictionType> _mine = const [];

  ArticlesRepository get _repo => ref.read(articlesRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadMine());
  }

  Future<void> _loadMine() async {
    try {
      final addictions = await ref
          .read(recoveryRepositoryProvider)
          .addictions();
      if (!mounted) return;
      setState(() {
        _mine = [
          for (final t in AddictionType.values)
            if (addictions.any((a) => a.type == t)) t,
        ];
      });
    } catch (_) {
      // Locked before the first visit, or offline: the library still opens,
      // without the addiction chips.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Articles follow the app's language, so switching it reloads the list.
    final language = Localizations.localeOf(context).languageCode;
    if (language != _language) {
      _language = language;
      _articles = _load();
    }
  }

  Future<List<ArticleSummary>> _load() => _repo.articles(
    language: _language!,
    topic: _topic,
    addictionType: _addiction,
    favouritesOnly: _saved,
  );

  void _reload() => setState(() {
    _articles = _load();
  });

  void _filter({
    ArticleTopic? topic,
    AddictionType? addiction,
    bool saved = false,
  }) {
    _topic = topic;
    _addiction = addiction;
    _saved = saved;
    _reload();
  }

  void _open(ArticleSummary summary) {
    unawaited(
      Navigator.of(context)
          .push<void>(
            appRoute(
              ArticleScreen(id: summary.id),
              reduced: AppMotion.reduced(context),
            ),
          )
          // A favourite may have changed while reading.
          .then((_) {
            if (mounted) _reload();
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.articlesTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.screenHorizontal,
                vertical: AppSpace.sm,
              ),
              child: Row(
                spacing: AppSpace.sm,
                children: [
                  ChoiceChip(
                    label: Text(l10n.articlesAll),
                    selected: _topic == null && _addiction == null && !_saved,
                    onSelected: (_) => _filter(),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.bookmark_rounded, size: 18),
                    label: Text(l10n.articlesSaved),
                    selected: _saved,
                    onSelected: (_) => _filter(saved: true),
                  ),
                  for (final a in _mine)
                    ChoiceChip(
                      label: Text(l10n.addictionType(a.name)),
                      selected: _addiction == a,
                      onSelected: (_) => _filter(addiction: a),
                    ),
                  for (final t in ArticleTopic.values)
                    ChoiceChip(
                      label: Text(topicName(l10n, t)),
                      selected: _topic == t,
                      onSelected: (_) => _filter(topic: t),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<ArticleSummary>>(
                future: _articles,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return LoadError(onRetry: _reload);
                  final list = snapshot.data;
                  if (list == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (list.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.xl),
                        child: Text(
                          _saved ? l10n.articlesNoneSaved : l10n.articlesNone,
                          textAlign: TextAlign.center,
                          style: text.bodyLarge?.copyWith(
                            color: AppColors.textBody,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.screenHorizontal,
                      AppSpace.sm,
                      AppSpace.screenHorizontal,
                      AppSpace.xl,
                    ),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) => _ArticleRow(
                      article: list[i],
                      onOpen: () => _open(list[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  const _ArticleRow({required this.article, required this.onOpen});

  final ArticleSummary article;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        child: Row(
          spacing: AppSpace.md,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpace.xs,
                children: [
                  Text(article.title, style: text.titleMedium),
                  Text(
                    topicName(l10n, article.topic),
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            if (article.favourite)
              Icon(
                Icons.bookmark_rounded,
                color: AppColors.teal700,
                semanticLabel: l10n.articleSavedLabel,
              ),
            // Mirrored in RTL by the icon itself.
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
