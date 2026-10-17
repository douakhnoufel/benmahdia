import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a payment page outside the app. Injected so tests never leave it.
typedef OpenUrl = Future<bool> Function(Uri url);

final openUrlProvider = Provider<OpenUrl>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);
