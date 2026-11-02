import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_store.dart';

/// App language. Arabic (RTL) by default; French switches the app to LTR.
/// The language the patient chose last time is restored at launch.
class LocaleNotifier extends Notifier<Locale> {
  LocaleNotifier([this._initial = const Locale('ar')]);

  final Locale _initial;

  @override
  Locale build() => _initial;

  void set(Locale locale) {
    state = locale;
    unawaited(LocalStore.writeLocale(locale));
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);
