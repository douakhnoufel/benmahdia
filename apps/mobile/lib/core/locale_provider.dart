import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App language. Arabic (RTL) by default; French switches the app to LTR.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale('ar');

  void set(Locale locale) => state = locale;
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);
