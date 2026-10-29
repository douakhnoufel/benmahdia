import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'article_models.dart';
import 'articles_repository.dart';

/// [ArticlesRepository] over the BenMahdia API (backend/app/routers/articles.py).
class ApiArticlesRepository implements ArticlesRepository {
  ApiArticlesRepository({
    required Uri baseUrl,
    required String? Function() token,
    required Future<bool> Function() refresh,
    http.Client? client,
  }) : _base = baseUrl,
       _token = token,
       _refresh = refresh,
       _client = client ?? http.Client();

  final Uri _base;
  final String? Function() _token;
  final Future<bool> Function() _refresh;
  final http.Client _client;
  Future<bool>? _refreshing;

  static const _timeout = Duration(seconds: 15);

  Future<Object?> _send(String method, String path) async {
    var response = await _once(method, path);
    if (response.statusCode == 401 && await _refreshOnce()) {
      response = await _once(method, path);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const ArticlesUnavailable();
    }
    try {
      final text = utf8.decode(response.bodyBytes);
      return text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      throw const ArticlesUnavailable();
    }
  }

  /// A refresh token is single-use, so several expired requests must await
  /// the same rotation instead of each spending the old token.
  Future<bool> _refreshOnce() {
    final active = _refreshing;
    if (active != null) return active;
    final refresh = _refresh();
    return _refreshing = refresh.whenComplete(() => _refreshing = null);
  }

  Future<http.Response> _once(String method, String path) async {
    final request = http.Request(method, _base.resolve(path))
      ..headers['accept'] = 'application/json';
    final token = _token();
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    try {
      return await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
    } on TimeoutException {
      throw const ArticlesUnavailable();
    } on http.ClientException {
      throw const ArticlesUnavailable();
    }
  }

  /// A malformed answer is "unavailable", never a crash.
  static ArticleSummary _summaryFrom(Object? json) {
    try {
      final m = json! as Map<String, dynamic>;
      return ArticleSummary(
        id: m['id'] as String,
        title: m['title'] as String,
        language: m['language'] as String,
        topic: ArticleTopic.values.byName(m['topic'] as String),
        addictionType: m['addiction_type'] as String?,
        publishedAt: switch (m['published_at']) {
          final String at => DateTime.parse(at).toLocal(),
          _ => null,
        },
        favourite: m['favourite'] as bool? ?? false,
      );
    } on Object {
      throw const ArticlesUnavailable();
    }
  }

  @override
  Future<List<ArticleSummary>> articles({
    required String language,
    ArticleTopic? topic,
    bool favouritesOnly = false,
  }) async {
    final query = Uri(
      queryParameters: {
        'language': language,
        if (topic != null) 'topic': topic.name,
        if (favouritesOnly) 'favourites': 'true',
      },
    ).query;
    final json = await _send('GET', 'v1/me/articles?$query');
    if (json is! List) throw const ArticlesUnavailable();
    return json.map(_summaryFrom).toList();
  }

  @override
  Future<Article> article(String id) async {
    final json = await _send('GET', 'v1/me/articles/$id');
    final body = json is Map ? json['body'] : null;
    if (body is! String) throw const ArticlesUnavailable();
    return Article(summary: _summaryFrom(json), body: body);
  }

  @override
  Future<void> setFavourite(String id, {required bool favourite}) async {
    await _send(favourite ? 'PUT' : 'DELETE', 'v1/me/articles/$id/favourite');
  }
}
