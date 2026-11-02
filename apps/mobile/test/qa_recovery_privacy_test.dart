// QA recovery 2026-10-26, alerts-privacy tester (prefix ALERT).
//
// Every notification the phone schedules for recovery stays neutral, in
// Arabic and in French (PRD 5.3, 5.4, 5.6 Good habits, 8.3): no substance,
// no drug, no answer and no words the patient typed. A habit from the
// clinic's list is named ("Time for: Sport"); one in the patient's own words
// shows only "Time for your habit". Every name below is a fake marker, never
// real patient data.
//
// Medication reminders are not built (the phone schedules none): that gap is
// the flow tester's UX-07, not repeated here. These tests only check that no
// scheduled text names the drug.

import 'package:benmahdia_mobile/core/locale_provider.dart';
import 'package:benmahdia_mobile/core/notifications/local_notifications.dart';
import 'package:benmahdia_mobile/features/booking/booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/fake_booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/payment_launcher.dart';
import 'package:benmahdia_mobile/features/companion/companion_repository.dart';
import 'package:benmahdia_mobile/features/companion/fake_companion_repository.dart';
import 'package:benmahdia_mobile/features/home/home_shell.dart';
import 'package:benmahdia_mobile/features/recovery/fake_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_models.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_reminders.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_repository.dart';
import 'package:benmahdia_mobile/l10n/app_localizations.dart';
import 'package:benmahdia_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// Saturday 17 October 2026, 17:10, clinic time.
final _now = DateTime(2026, 10, 17, 17, 10);

const _substance = 'QA-substance-zx';
const _ownWords = 'QA-own-habit-zx';
const _drug = 'QA-drugname-zx';
const _amount = 'QA-amount-zx';
const _instruction = 'QA-instructions-zx';
const _markers = [_substance, _ownWords, _drug, _amount, _instruction];

const _languages = ['ar', 'fr'];

/// What the phone was asked to show, by notification id.
class _Notifications implements LocalNotifications {
  final scheduled = <int, ({DateTime at, String title, String body})>{};

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async => scheduled[id] = (at: at, title: title, body: body);

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<Set<int>> pending() async => scheduled.keys.toSet();
}

/// Words that would tell whoever reads the lock screen what the patient is
/// treated for: profile names, signal labels and addiction types in both
/// languages, plus the fake markers.
List<String> _clinicalWords(AppLocalizations ar, AppLocalizations fr) => [
  for (final p in sampleProfiles) ...[
    p.name.ar,
    p.name.fr,
    for (final s in p.signals) ...[s.label.ar, s.label.fr],
  ],
  for (final t in AddictionType.values) ...[
    ar.addictionType(t.name),
    fr.addictionType(t.name),
  ],
  ..._markers,
];

void _expectNeutral(String text, List<String> words) {
  for (final w in words) {
    expect(
      text.toLowerCase().contains(w.toLowerCase()),
      isFalse,
      reason: '"$text" names "$w"',
    );
  }
}

class _French extends LocaleNotifier {
  @override
  Locale build() => const Locale('fr');
}

/// A patient with a substance in their own words, a prescription, a list
/// habit and a habit in their own words, both with a reminder, and the
/// daily-check reminder at 21:00 (from the fake).
class _Repo extends FakeRecoveryRepository {
  _Repo() : super(clock: () => _now);

  @override
  Future<List<Addiction>> addictions() async => [
    Addiction(
      id: 'a1',
      type: AddictionType.tobacco,
      profile: SubstanceProfile.nicotine,
      substance: _substance,
      start: _now.subtract(const Duration(days: 9)),
      longestPastDays: 0,
      pastDays: 0,
      milestoneSeen: 7,
    ),
  ];

  @override
  Future<List<Dose>> todaysDoses() async => const [
    Dose(
      id: 'd1',
      name: LocalizedText(ar: _drug, fr: _drug),
      amount: LocalizedText(ar: _amount, fr: _amount),
      instruction: LocalizedText(ar: _instruction, fr: _instruction),
      hour: 21,
      minute: 30,
      status: DoseStatus.due,
    ),
  ];

  @override
  Future<List<Habit>> habits() async => const [
    Habit(id: 'h1', kind: HabitKind.sport, reminder: (hour: 18, minute: 0)),
    Habit(
      id: 'h2',
      kind: HabitKind.custom,
      text: _ownWords,
      reminder: (hour: 20, minute: 0),
    ),
  ];
}

Future<_Notifications> _pumpHome(
  WidgetTester tester, {
  required bool french,
}) async {
  final notifications = _Notifications();
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recoveryRepositoryProvider.overrideWithValue(_Repo()),
        bookingRepositoryProvider.overrideWithValue(
          FakeBookingRepository(clock: () => _now),
        ),
        companionRepositoryProvider.overrideWithValue(
          FakeCompanionRepository(delay: Duration.zero),
        ),
        openUrlProvider.overrideWithValue((_) async => true),
        localNotificationsProvider.overrideWithValue(notifications),
        if (french) localeProvider.overrideWith(_French.new),
      ],
      child: const BenMahdiaApp(home: HomeShell()),
    ),
  );
  await pumpFor(tester, const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
  return notifications;
}

void main() {
  late AppLocalizations ar;
  late AppLocalizations fr;

  setUpAll(() async {
    ar = await AppLocalizations.delegate.load(const Locale('ar'));
    fr = await AppLocalizations.delegate.load(const Locale('fr'));
  });

  AppLocalizations l10n(String lang) => lang == 'ar' ? ar : fr;

  group('RecoveryReminders text (R-42, R-61)', () {
    for (final lang in _languages) {
      test('the daily-check reminder names nothing · $lang', () async {
        final notifications = _Notifications();
        await RecoveryReminders(notifications).sync(
          checkReminder: (hour: 21, minute: 0),
          habits: const [],
          catalog: sampleHabits,
          now: _now,
          l10n: l10n(lang),
        );
        expect(notifications.scheduled, hasLength(RecoveryReminders.days));
        for (final r in notifications.scheduled.values) {
          expect(r.title, l10n(lang).reminderTitle);
          expect(r.body, l10n(lang).reminderDailyCheck);
          _expectNeutral('${r.title} ${r.body}', _clinicalWords(ar, fr));
        }
      });

      test('every list habit is named in its language, own words never '
          '· $lang', () async {
        final notifications = _Notifications();
        final listed = [
          for (final k in HabitKind.values)
            if (k != HabitKind.custom) k,
        ];
        await RecoveryReminders(notifications).sync(
          checkReminder: null,
          habits: [
            for (final (i, k) in listed.indexed)
              Habit(
                id: 'h-${k.name}',
                kind: k,
                reminder: (hour: 7 + i, minute: 0),
              ),
            const Habit(
              id: 'h-own',
              kind: HabitKind.custom,
              text: _ownWords,
              reminder: (hour: 22, minute: 15),
            ),
          ],
          catalog: sampleHabits,
          now: _now,
          l10n: l10n(lang),
        );
        final l = l10n(lang);
        final other = lang == 'ar' ? 'fr' : 'ar';
        expect(
          notifications.scheduled,
          hasLength((listed.length + 1) * RecoveryReminders.days),
        );
        expect(
          {for (final r in notifications.scheduled.values) r.body},
          {
            for (final k in listed) l.reminderHabit(sampleHabits[k]!.of(lang)),
            l.reminderHabitOwn,
          },
        );
        for (final r in notifications.scheduled.values) {
          expect(r.title, l.reminderTitle);
          expect(r.body.contains(_ownWords), isFalse);
          for (final k in listed) {
            // Never the other language's label.
            expect(r.body.contains(sampleHabits[k]!.of(other)), isFalse);
          }
        }
        // The own-words text itself names nothing.
        _expectNeutral(l.reminderHabitOwn, _clinicalWords(ar, fr));
      });

      test('own words stay hidden even if the catalog has a "custom" entry '
          '· $lang', () async {
        final notifications = _Notifications();
        await RecoveryReminders(notifications).sync(
          checkReminder: null,
          habits: const [
            Habit(
              id: 'h-own',
              kind: HabitKind.custom,
              text: _ownWords,
              reminder: (hour: 20, minute: 0),
            ),
          ],
          catalog: {
            ...sampleHabits,
            HabitKind.custom: const LocalizedText(ar: _ownWords, fr: _ownWords),
          },
          now: _now,
          l10n: l10n(lang),
        );
        expect(
          {for (final r in notifications.scheduled.values) r.body},
          {l10n(lang).reminderHabitOwn},
        );
      });

      test('a list habit the catalog lacks falls back to the neutral text '
          '· $lang', () async {
        final notifications = _Notifications();
        await RecoveryReminders(notifications).sync(
          checkReminder: null,
          habits: const [
            Habit(
              id: 'h1',
              kind: HabitKind.water,
              reminder: (hour: 9, minute: 0),
            ),
          ],
          catalog: const {},
          now: _now,
          l10n: l10n(lang),
        );
        expect(
          {for (final r in notifications.scheduled.values) r.body},
          {l10n(lang).reminderHabitOwn},
        );
      });
    }
  });

  group('what the recovery home schedules (R-42, R-61, R-72, R-98)', () {
    for (final lang in _languages) {
      testWidgets('only neutral reminders, nothing about the substance, the '
          'drug or the own words · $lang', (tester) async {
        final notifications = await _pumpHome(tester, french: lang == 'fr');
        final l = l10n(lang);
        final recovery = [
          for (final MapEntry(key: id, value: r)
              in notifications.scheduled.entries)
            if (id >= RecoveryReminders.base) r,
        ];
        expect({for (final r in recovery) r.title}, {l.reminderTitle});
        expect(
          {for (final r in recovery) r.body},
          {
            l.reminderDailyCheck,
            l.reminderHabit(sampleHabits[HabitKind.sport]!.of(lang)),
            l.reminderHabitOwn,
          },
        );
        // The daily check, one list habit and one own-words habit, each for
        // the next seven days. No dose reminder (UX-07).
        expect(recovery, hasLength(3 * RecoveryReminders.days));
        // Nothing the phone holds, the appointment reminders of the shared
        // service included, names the substance, the drug or the words.
        for (final r in notifications.scheduled.values) {
          _expectNeutral('${r.title} ${r.body}', _clinicalWords(ar, fr));
        }
      });
    }
  });
}
