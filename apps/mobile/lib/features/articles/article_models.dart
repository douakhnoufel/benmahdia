import 'package:flutter/foundation.dart';

/// The library's sections (PRD 5.5).
enum ArticleTopic {
  addiction,
  cravings,
  relapse,
  medication,
  family,
  motivation,
}

/// An article in the list: no body until it is opened.
@immutable
class ArticleSummary {
  const ArticleSummary({
    required this.id,
    required this.title,
    required this.language,
    required this.topic,
    this.addictionType,
    this.publishedAt,
    this.favourite = false,
  });

  final String id;
  final String title;

  /// "ar" or "fr": an article is written in one language.
  final String language;
  final ArticleTopic topic;

  /// The addiction it was written for, as the API names it; null = everyone.
  final String? addictionType;
  final DateTime? publishedAt;
  final bool favourite;

  ArticleSummary withFavourite(bool value) => ArticleSummary(
    id: id,
    title: title,
    language: language,
    topic: topic,
    addictionType: addictionType,
    publishedAt: publishedAt,
    favourite: value,
  );
}

/// An opened article. [body] is plain text; blank lines split paragraphs.
@immutable
class Article {
  const Article({required this.summary, required this.body});

  final ArticleSummary summary;
  final String body;

  List<String> get paragraphs => body
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
}

/// The library could not be reached; the screen offers to try again.
class ArticlesUnavailable implements Exception {
  const ArticlesUnavailable();
}
