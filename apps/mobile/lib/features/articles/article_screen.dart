import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../booking/booking_widgets.dart';
import 'article_models.dart';
import 'articles_repository.dart';
import 'articles_screen.dart';

/// One article to read, with a button to save it for later.
class ArticleScreen extends ConsumerStatefulWidget {
  const ArticleScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends ConsumerState<ArticleScreen> {
  late Future<Article> _article = _load();
  bool? _favourite;
  bool _saving = false;

  ArticlesRepository get _repo => ref.read(articlesRepositoryProvider);

  Future<Article> _load() => _repo.article(widget.id);

  /// A void seam: the tap never holds the Future (see async-safety).
  void _toggle(bool current) {
    unawaited(_setFavourite(!current));
  }

  Future<void> _setFavourite(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await _repo.setFavourite(widget.id, favourite: value);
      if (!mounted) return;
      setState(() => _favourite = value);
    } on ArticlesUnavailable {
      messenger.showSnackBar(SnackBar(content: Text(l10n.articleSaveFailed)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return FutureBuilder<Article>(
      future: _article,
      builder: (context, snapshot) {
        final article = snapshot.data;
        final favourite = _favourite ?? article?.summary.favourite ?? false;
        return Scaffold(
          appBar: AppBar(
            actions: [
              if (article != null)
                IconButton(
                  onPressed: _saving ? null : () => _toggle(favourite),
                  tooltip: favourite ? l10n.articleUnsave : l10n.articleSave,
                  icon: Icon(
                    favourite
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: AppColors.teal700,
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: switch (snapshot) {
              AsyncSnapshot(hasError: true) => LoadError(
                onRetry: () => setState(() {
                  _article = _load();
                }),
              ),
              AsyncSnapshot(data: null) => const Center(
                child: CircularProgressIndicator(),
              ),
              _ => ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.screenHorizontal,
                  AppSpace.sm,
                  AppSpace.screenHorizontal,
                  AppSpace.xxxl,
                ),
                children: [
                  Text(
                    topicName(l10n, article!.summary.topic),
                    style: text.labelLarge?.copyWith(color: AppColors.teal700),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Semantics(
                    header: true,
                    child: Text(
                      article.summary.title,
                      style: text.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  for (final p in article.paragraphs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.lg),
                      child: Text(p, style: text.bodyLarge),
                    ),
                ],
              ),
            },
          ),
        );
      },
    );
  }
}
