// QA recovery run 2026-10-26 (ux-clients). Widget tests of what the patient
// sees in Recovery (PRD 5, 5.1-5.6, 8.6, 12.3): the locked tab, the home
// (one circle per addiction, the quote, today's doses), the daily check per
// substance, the addiction form, habits, small goals and the relapse flow,
// each in Arabic (RTL) and French, on a 320 px phone; empty, waiting,
// loading and error states; 24-hour time pickers; double taps; screen
// readers. Sample data only, no real patients, no real drug names.
//
// A test that shows a real bug sits in a group skipped with its QA id; the
// skip message says what is wrong (the run's report was never committed, see
// qa/recovery/2026-10-26/ for its rules and baseline). Remove the skip once
// the bug is fixed.
// To run them too (each fails today): --dart-define=QA_RUN_BUGS=true.

import 'package:benmahdia_mobile/core/locale_provider.dart';
import 'package:benmahdia_mobile/core/notifications/local_notifications.dart';
import 'package:benmahdia_mobile/features/booking/booking_format.dart';
import 'package:benmahdia_mobile/features/booking/booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/booking_widgets.dart';
import 'package:benmahdia_mobile/features/booking/fake_booking_repository.dart';
import 'package:benmahdia_mobile/features/booking/my_appointments_screen.dart';
import 'package:benmahdia_mobile/features/booking/payment_launcher.dart';
import 'package:benmahdia_mobile/features/companion/companion_repository.dart';
import 'package:benmahdia_mobile/features/companion/fake_companion_repository.dart';
import 'package:benmahdia_mobile/features/home/home_shell.dart';
import 'package:benmahdia_mobile/features/recovery/addiction_form_screen.dart';
import 'package:benmahdia_mobile/features/recovery/daily_check_screen.dart';
import 'package:benmahdia_mobile/features/recovery/fake_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/milestone_screen.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_models.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_screen.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_widgets.dart';
import 'package:benmahdia_mobile/features/recovery/tracking_widgets.dart';
import 'package:benmahdia_mobile/l10n/app_localizations.dart';
import 'package:benmahdia_mobile/main.dart';
import 'package:benmahdia_mobile/widgets/sobriety_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'appointment_reminders_test.dart' show FakeNotifications;
import 'helpers.dart';

// Saturday 17 October 2026, 17:10 (the "now" of the other recovery tests).
final _now = DateTime(2026, 10, 17, 17, 10);
final _today = DateTime(2026, 10, 17);

final _ar = lookupAppLocalizations(const Locale('ar'));
final _fr = lookupAppLocalizations(const Locale('fr'));

/// Run the known-bug tests too: --dart-define=QA_RUN_BUGS=true.
const _runBugs = bool.fromEnvironment('QA_RUN_BUGS');

/// A widget test that shows a real bug: skipped with its QA id until fixed.
void _bug(String id, String why, String name, WidgetTesterCallback body) =>
    group(
      id,
      () => testWidgets(name, body),
      skip: _runBugs ? false : 'QA $id: $why',
    );

/// The same for a plain test.
void _bugTest(String id, String why, String name, void Function() body) =>
    group(id, () => test(name, body), skip: _runBugs ? false : 'QA $id: $why');

class _French extends LocaleNotifier {
  @override
  Locale build() => const Locale('fr');
}

ProfileSpec _spec(SubstanceProfile p) =>
    sampleProfiles.firstWhere((s) => s.profile == p);

/// An addiction [days] into its streak. Its milestones are already
/// celebrated unless [seen] says otherwise, so no celebration covers the home.
Addiction _addiction(
  String id, {
  SubstanceProfile? profile,
  AddictionType type = AddictionType.alcohol,
  int days = 9,
  int longestPast = 21,
  int past = 55,
  bool reviewed = true,
  int? seen,
  int? goal,
}) => Addiction(
  id: id,
  type: profile == null ? type : _spec(profile).type,
  profile: profile,
  start: _now.subtract(Duration(days: days, hours: 3)),
  longestPastDays: longestPast,
  pastDays: past,
  reviewed: reviewed,
  goalDays: goal,
  milestoneSeen: seen ?? reachedMilestone(days),
);

const _morning = Dose(
  id: 'd1',
  name: LocalizedText(ar: 'دواء الصباح', fr: 'Médicament du matin'),
  amount: LocalizedText(ar: 'قرص واحد', fr: '1 comprimé'),
  hour: 8,
  minute: 0,
  status: DoseStatus.taken,
);
const _evening = Dose(
  id: 'd2',
  name: LocalizedText(ar: 'دواء المساء', fr: 'Médicament du soir'),
  amount: LocalizedText(ar: 'قرص واحد', fr: '1 comprimé'),
  hour: 21,
  minute: 0,
  status: DoseStatus.due,
);
const _quote = Quote(
  text: LocalizedText(
    ar: 'خطوة صغيرة كل يوم.',
    fr: 'Un petit pas chaque jour.',
  ),
  source: LocalizedText(ar: '', fr: ''),
);

/// An in-memory recovery API that counts its calls (for double taps) and can
/// be locked, fail its first loads, or have no quote, dose, habit or
/// addiction. Each call takes 200 ms, like the sample repository.
class _Repo implements RecoveryRepository {
  _Repo({
    List<Addiction>? addictions,
    List<Dose>? doses,
    List<Habit>? habits,
    this.locked = false,
    this.quote = _quote,
    this.failLoads = 0,
    this.reminderTime = const (hour: 21, minute: 0),
  }) : addictionList =
           addictions ??
           [_addiction('a1', profile: SubstanceProfile.pregabalin)],
       doseList = doses ?? const [_morning, _evening],
       habitList =
           habits ??
           [
             const Habit(
               id: 'h1',
               kind: HabitKind.sport,
               reminder: (hour: 18, minute: 0),
             ),
           ];

  bool locked;
  Quote? quote;
  int failLoads;
  DayTime? reminderTime;
  List<Addiction> addictionList;
  List<Dose> doseList;
  List<Habit> habitList;
  final checks = <AddictionCheck>[];
  final checkInDays = <DateTime>{};
  final relapses = <({String id, String? note, DateTime at})>[];

  final _calls = <String, int>{};
  int count(String name) => _calls[name] ?? 0;

  Future<void> _call(String name) async {
    _calls[name] = count(name) + 1;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (locked) throw const RecoveryLocked();
  }

  void _put(Addiction a) =>
      addictionList = [for (final x in addictionList) x.id == a.id ? a : x];

  @override
  DateTime now() => _now;

  @override
  Future<List<Addiction>> addictions() async {
    await _call('addictions');
    if (failLoads > 0) {
      failLoads--;
      throw const RecoveryUnavailable();
    }
    return List.of(addictionList);
  }

  @override
  Future<Addiction> addAddiction({
    AddictionType? type,
    SubstanceProfile? profile,
    required DateTime cleanSince,
    String? substance,
  }) async {
    await _call('addAddiction');
    final added = Addiction(
      id: 'new${addictionList.length + 1}',
      type: profile == null ? type! : _spec(profile).type,
      profile: profile,
      substance: substance,
      reviewed: false,
      start: cleanSince,
      longestPastDays: 0,
      pastDays: 0,
    );
    addictionList = [...addictionList, added];
    return added;
  }

  @override
  Future<Addiction> setGoal(Addiction addiction, int? days) async {
    await _call('setGoal');
    final updated = addiction.withGoal(days);
    _put(updated);
    return updated;
  }

  @override
  Future<Addiction> markMilestoneSeen(Addiction addiction) async {
    await _call('markMilestoneSeen');
    final updated = addiction.withMilestoneSeen(
      reachedMilestone(addiction.days(_now)),
    );
    _put(updated);
    return updated;
  }

  @override
  Future<List<ProfileSpec>> profiles() async {
    await _call('profiles');
    return sampleProfiles;
  }

  @override
  Future<CheckHistory> addictionChecks() async {
    await _call('addictionChecks');
    final done = <DateTime>{};
    for (final day in {for (final c in checks) c.day}) {
      final ids = {
        for (final c in checks)
          if (c.day == day) c.addictionId,
      };
      if (addictionList.every((a) => ids.contains(a.id))) done.add(day);
    }
    return (checks: List.of(checks), doneDays: done);
  }

  @override
  Future<void> saveCheck(AddictionCheck check) async {
    await _call('saveCheck');
    checks
      ..removeWhere(
        (c) => c.addictionId == check.addictionId && c.day == check.day,
      )
      ..add(check);
  }

  @override
  Future<Map<HabitKind, LocalizedText>> habitCatalog() async {
    await _call('habitCatalog');
    return sampleHabits;
  }

  @override
  Future<List<Habit>> habits() async {
    await _call('habits');
    return List.of(habitList);
  }

  @override
  Future<Habit> addHabit(
    HabitKind kind, {
    String? text,
    DayTime? reminder,
  }) async {
    await _call('addHabit');
    final added = Habit(
      id: 'h${habitList.length + 1}',
      kind: kind,
      text: text,
      reminder: reminder,
    );
    habitList = [...habitList, added];
    return added;
  }

  @override
  Future<void> removeHabit(Habit habit) async {
    await _call('removeHabit');
    habitList = [
      for (final h in habitList)
        if (h.id != habit.id) h,
    ];
  }

  @override
  Future<Habit> setHabitReminder(Habit habit, DayTime? time) async {
    await _call('setHabitReminder');
    final updated = habit.copyWith(reminder: time, clearReminder: time == null);
    habitList = [for (final h in habitList) h.id == habit.id ? updated : h];
    return updated;
  }

  @override
  Future<void> markHabit(
    Habit habit,
    DateTime day, {
    required bool done,
  }) async {
    await _call('markHabit');
    habitList = [
      for (final h in habitList)
        if (h.id != habit.id)
          h
        else
          h.copyWith(
            days: done
                ? {...h.days, dayOf(day)}
                : ({...h.days}..remove(dayOf(day))),
          ),
    ];
  }

  @override
  Future<Addiction> logRelapse(
    Addiction addiction, {
    String? note,
    DateTime? at,
  }) async {
    await _call('logRelapse');
    final when = at ?? _now;
    final updated = addiction.relapsed(when);
    _put(updated);
    relapses.add((id: addiction.id, note: note, at: when));
    return updated;
  }

  @override
  Future<Quote?> quoteOfDay() async {
    await _call('quoteOfDay');
    return quote;
  }

  @override
  Future<List<Dose>> todaysDoses() async {
    await _call('todaysDoses');
    return List.of(doseList);
  }

  @override
  Future<Dose> markDose(Dose dose, DoseStatus status) async {
    await _call('markDose');
    final updated = dose.withStatus(status);
    doseList = [for (final d in doseList) d.id == dose.id ? updated : d];
    return updated;
  }

  @override
  Future<ClinicInfo> clinic() async {
    await _call('clinic');
    return benmahdiaClinic;
  }

  @override
  Future<Set<DateTime>> checkIns() async {
    await _call('checkIns');
    return Set.of(checkInDays);
  }

  @override
  Future<void> checkIn(DateTime day) async {
    await _call('checkIn');
    checkInDays.add(dayOf(day));
  }

  @override
  Future<DayTime?> reminder() async {
    await _call('reminder');
    return reminderTime;
  }

  @override
  Future<void> setReminder(DayTime? time) async {
    await _call('setReminder');
    reminderTime = time;
  }
}

/// Pumps [home] in the real app at [size] (logical px), in Arabic or
/// French, with an optional system text scale.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required RecoveryRepository repo,
  bool french = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool settle = true,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recoveryRepositoryProvider.overrideWithValue(repo),
        bookingRepositoryProvider.overrideWithValue(
          FakeBookingRepository(clock: () => _now),
        ),
        companionRepositoryProvider.overrideWithValue(
          FakeCompanionRepository(delay: Duration.zero),
        ),
        openUrlProvider.overrideWithValue((_) async => true),
        if (french) localeProvider.overrideWith(_French.new),
        ...extra,
      ],
      child: BenMahdiaApp(home: home),
    ),
  );
  if (settle) await _settle(tester);
}

/// Lets the 200 ms calls answer, then the animations end.
Future<void> _settle(WidgetTester tester) async {
  await pumpFor(tester, const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

Finder get _list => find
    .descendant(
      of: find.byType(RecoveryScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: _list);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

TextDirection _dir(WidgetTester tester, Finder finder) =>
    Directionality.of(tester.element(finder.first));

/// Every piece of text on screen (icons excluded).
List<String> _texts(WidgetTester tester, [Finder? within]) => tester
    .widgetList<RichText>(
      within == null
          ? find.byType(RichText)
          : find.descendant(of: within, matching: find.byType(RichText)),
    )
    .map((w) => w.text.toPlainText().trim())
    .where((s) => s.isNotEmpty && !s.runes.every(_isIconGlyph))
    .toList();

/// Icon fonts use the private-use areas of Unicode.
bool _isIconGlyph(int r) =>
    (r >= 0xE000 && r <= 0xF8FF) || r >= 0xF0000 || r == 0x20;

final _rawCode = RegExp(r'\b[a-z]+_[a-z_]+\b');
final _arabic = RegExp(r'[؀-ۿ]');
// Brand names that stay in Latin letters inside Arabic text.
const _latinAllowedInArabic = {'Google'};

/// No raw API code; no Latin word left in Arabic, no Arabic left in French.
void _expectTranslated(WidgetTester tester, {required bool french}) {
  for (final t in _texts(tester)) {
    expect(_rawCode.hasMatch(t), isFalse, reason: 'raw code on screen: "$t"');
    if (french) {
      expect(_arabic.hasMatch(t), isFalse, reason: 'Arabic in French: "$t"');
    } else {
      final latin = RegExp(r'[A-Za-z]{2,}')
          .allMatches(t)
          .map((m) => m.group(0)!)
          .where((w) => !_latinAllowedInArabic.contains(w));
      expect(latin, isEmpty, reason: 'untranslated words in Arabic: "$t"');
    }
  }
}

// Words that judge, blame or diagnose; none belongs in the relapse flow.
const _harsh = {
  'fr': [
    'honte',
    'faute',
    'coupable',
    'raté',
    'échoué',
    'mauvais',
    'faible',
    'déçu',
    'décevant',
    'perdu',
    'interdit',
    'diagnostic',
    'maladie',
    'pathologie',
    'sévère',
    'grave',
  ],
  'ar': [
    'عار',
    'ذنب',
    'فشلت',
    'خطأك',
    'ضعيف',
    'مخيب',
    'خسرت',
    'للأسف',
    'ممنوع',
    'تشخيص',
    'مرض',
    'اضطراب',
    'خطير',
  ],
};

void _expectGentle(Iterable<String> texts, String lang) {
  for (final t in texts) {
    for (final w in _harsh[lang]!) {
      expect(t.toLowerCase().contains(w), isFalse, reason: '"$w" in "$t"');
    }
  }
}

String? _snack(WidgetTester tester) {
  final f = find.descendant(
    of: find.byType(SnackBar),
    matching: find.byType(Text),
  );
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f.first).data;
}

/// Answers every card of the open daily check with "yes, without" and 1s.
Future<void> _answerAll(
  WidgetTester tester,
  AppLocalizations l,
  String lang,
  List<Addiction> addictions,
) async {
  for (var i = 0; i < addictions.length; i++) {
    final a = addictions[i];
    await _tapVisible(tester, find.text(l.dailyCheckYes).at(i));
    await _tapVisible(
      tester,
      find.byKey(ValueKey('rating-${l.dailyCheckCraving}-1')).at(i),
    );
    if (a.profile case final p?) {
      for (final s in _spec(p).signals) {
        final f = find.byKey(ValueKey('rating-${s.label.of(lang)}-1'));
        await _tapVisible(tester, f.evaluate().length > 1 ? f.at(i) : f);
      }
    }
  }
  await tester.pump();
}

void main() {
  test('the profile catalog the app knows matches the PRD 5.6 table', () {
    const signals = {
      SubstanceProfile.nicotine: ['irritability', 'restlessness'],
      SubstanceProfile.thc: ['sleep', 'irritability'],
      SubstanceProfile.pregabalin: ['anxiety', 'sleep'],
      SubstanceProfile.buprenorphine: ['discomfort', 'sleep'],
      SubstanceProfile.cocaine: ['low_mood', 'low_energy'],
      SubstanceProfile.amphetamines: ['sleep', 'low_appetite'],
    };
    const types = {
      SubstanceProfile.nicotine: AddictionType.tobacco,
      SubstanceProfile.thc: AddictionType.cannabis,
      SubstanceProfile.pregabalin: AddictionType.pills,
      SubstanceProfile.buprenorphine: AddictionType.opioids,
      SubstanceProfile.cocaine: AddictionType.stimulants,
      SubstanceProfile.amphetamines: AddictionType.stimulants,
    };
    expect({for (final s in sampleProfiles) s.profile}, signals.keys.toSet());
    for (final s in sampleProfiles) {
      expect([for (final x in s.signals) x.key], signals[s.profile]);
      expect(s.type, types[s.profile]);
      expect(s.notes.length, inInclusiveRange(2, 3));
      for (final text in [
        s.name,
        for (final x in s.signals) x.label,
        for (final n in s.notes) n.text,
      ]) {
        expect(text.ar.trim(), isNotEmpty);
        expect(text.fr.trim(), isNotEmpty);
      }
    }
  });

  for (final french in [false, true]) {
    final lang = french ? 'fr' : 'ar';
    final l = french ? _fr : _ar;
    final dir = french ? TextDirection.ltr : TextDirection.rtl;

    group('locked before the first paid visit (PRD 5 unlock) · $lang', () {
      testWidgets('a lock, why, and a Book button that opens booking', (
        tester,
      ) async {
        final repo = _Repo(locked: true);
        await _pump(tester, const HomeShell(), repo: repo, french: french);
        expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
        expect(find.text(l.recoveryLockedTitle), findsOneWidget);
        expect(find.text(l.recoveryLockedBody), findsOneWidget);
        expect(find.byType(SobrietyRing), findsNothing);
        expect(find.text(l.recoveryMedsTitle), findsNothing);
        expect(find.text(l.habitsTitle), findsNothing);
        expect(find.byType(LoadError), findsNothing);
        expect(_dir(tester, find.byType(RecoveryLockedView)), dir);
        _expectTranslated(tester, french: french);
        // Nothing else is asked once the server says "locked".
        expect(repo.count('todaysDoses'), 0);

        await tester.tap(find.text(l.recoveryLockedBook));
        await _settle(tester);
        expect(find.byType(MyAppointmentsScreen), findsOneWidget);
      });

      testWidgets('320 wide: nothing overflows', (tester) async {
        await _pump(
          tester,
          const HomeShell(),
          repo: _Repo(locked: true),
          french: french,
          size: const Size(320, 568),
        );
        expect(tester.takeException(), isNull);
        expect(find.text(l.recoveryLockedBook), findsOneWidget);
      });
    });

    group('recovery home (PRD 5, 12.3) · $lang', () {
      List<Addiction> two() => [
        _addiction('a1', profile: SubstanceProfile.pregabalin),
        _addiction('a2', days: 40, longestPast: 10, past: 5),
      ];

      testWidgets("one circle per addiction, the quote and today's doses", (
        tester,
      ) async {
        await _pump(
          tester,
          const HomeShell(),
          repo: _Repo(addictions: two()),
          french: french,
          size: const Size(390, 3200),
        );
        expect(find.byType(SobrietyRing), findsNWidgets(2));
        expect(
          find.text(_spec(SubstanceProfile.pregabalin).name.of(lang)),
          findsOneWidget,
        );
        expect(find.text(l.addictionType('alcohol')), findsOneWidget);
        // Each circle fills toward that addiction's current small goal.
        final rings = tester.widgetList<SobrietyRing>(
          find.byType(SobrietyRing),
        );
        expect([for (final r in rings) (r.days, r.goal)], [(9, 14), (40, 60)]);
        expect(find.text(l.recoveryQuoteTitle), findsOneWidget);
        expect(find.text(_quote.text.of(lang)), findsOneWidget);
        expect(find.text(l.recoveryMedsTitle), findsOneWidget);
        expect(find.textContaining(_evening.name.of(lang)), findsOneWidget);
        expect(find.text(l.recoveryMedsCount(1, 2)), findsOneWidget);
        expect(find.text(l.recoveryDoseTake), findsOneWidget);
        expect(find.text(l.recoveryDoseSkip), findsOneWidget);
        expect(find.text(l.recoveryDoseTaken), findsOneWidget);
        expect(find.text(l.recoveryLongest), findsNWidgets(2));
        expect(find.text(l.recoveryTotal), findsNWidgets(2));
        expect(_dir(tester, find.byType(RecoveryScreen)), dir);
        _expectTranslated(tester, french: french);
      });

      testWidgets('320 wide: nothing overflows', (tester) async {
        await _pump(
          tester,
          const HomeShell(),
          repo: _Repo(addictions: two()),
          french: french,
          size: const Size(320, 3600),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(SobrietyRing), findsNWidgets(2));
      });

      testWidgets('1.3× text, 360 wide: nothing overflows', (tester) async {
        await _pump(
          tester,
          const HomeShell(),
          repo: _Repo(addictions: two()),
          french: french,
          size: const Size(360, 4400),
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('an entry not reviewed yet says it waits for the doctor', (
        tester,
      ) async {
        await _pump(
          tester,
          const HomeShell(),
          repo: _Repo(
            addictions: [
              _addiction('a1', profile: SubstanceProfile.thc, reviewed: false),
            ],
          ),
          french: french,
        );
        expect(find.text(l.addictionPending), findsOneWidget);
        expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      });
    });

    group('empty, loading and error states (PRD 8.6, 12.3) · $lang', () {
      testWidgets('no addiction yet: an invitation to add one, the day tick', (
        tester,
      ) async {
        await _pump(
          tester,
          const HomeShell(),
          repo: _Repo(addictions: []),
          french: french,
          size: const Size(390, 3000),
        );
        expect(find.byType(SobrietyRing), findsNothing);
        expect(find.text(l.addictionEmpty), findsOneWidget);
        expect(find.text(l.addictionAdd), findsOneWidget);
        expect(find.text(l.checkInAction), findsOneWidget);
        expect(find.text(l.dailyCheckAction), findsNothing);
        _expectTranslated(tester, french: french);
      });

      testWidgets('no dose today', (tester) async {
        await _pump(
          tester,
          const HomeShell(),
          repo: _Repo(doses: []),
          french: french,
          size: const Size(390, 3000),
        );
        expect(find.text(l.recoveryNoMeds), findsOneWidget);
        expect(find.text(l.recoveryDoseTake), findsNothing);
      });

      testWidgets('no habit yet', (tester) async {
        await _pump(
          tester,
          const HomeShell(),
          repo: _Repo(habits: []),
          french: french,
          size: const Size(390, 3000),
        );
        expect(find.text(l.habitsEmpty), findsOneWidget);
        expect(find.text(l.habitsAdd), findsOneWidget);
      });

      testWidgets('five habits: the limit is said instead of Add', (
        tester,
      ) async {
        await _pump(
          tester,
          const HomeShell(),
          repo: _Repo(
            habits: [
              for (final (i, k) in HabitKind.values.take(5).indexed)
                Habit(id: 'h$i', kind: k),
            ],
          ),
          french: french,
          size: const Size(390, 3000),
        );
        expect(find.text(l.habitsMax), findsOneWidget);
        expect(find.text(l.habitsAdd), findsNothing);
      });

      testWidgets('no quote today: no quote card and no error', (tester) async {
        await _pump(
          tester,
          const HomeShell(),
          repo: _Repo(quote: null),
          french: french,
          size: const Size(390, 3000),
        );
        expect(find.text(l.recoveryQuoteTitle), findsNothing);
        expect(find.byType(LoadError), findsNothing);
        expect(find.byType(SobrietyRing), findsOneWidget);
      });

      testWidgets('loading shows progress, then the counters', (tester) async {
        await _pump(
          tester,
          const HomeShell(),
          repo: _Repo(),
          french: french,
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 100));
        final spinner = find.descendant(
          of: find.byType(RecoveryScreen),
          matching: find.byType(CircularProgressIndicator),
        );
        expect(spinner, findsOneWidget);
        expect(find.byType(SobrietyRing), findsNothing);
        await _settle(tester);
        expect(spinner, findsNothing);
        expect(find.byType(SobrietyRing), findsOneWidget);
      });

      testWidgets('a failed load says so, and Retry loads the tab', (
        tester,
      ) async {
        await _pump(
          tester,
          const HomeShell(),
          repo: _Repo(failLoads: 1),
          french: french,
        );
        expect(find.byType(LoadError), findsOneWidget);
        expect(find.text(l.bookLoadError), findsOneWidget);
        await tester.tap(find.text(l.bookRetry));
        await _settle(tester);
        expect(find.byType(LoadError), findsNothing);
        expect(find.byType(SobrietyRing), findsOneWidget);
      });
    });

    group('daily check per addiction (PRD 5.4, 5.6) · $lang', () {
      final all = [
        for (final (i, p) in SubstanceProfile.values.indexed)
          _addiction('p$i', profile: p),
        _addiction('g'),
      ];

      Future<void> pumpCheck(
        WidgetTester tester, {
        Size size = const Size(390, 6000),
        List<Addiction>? addictions,
        List<Habit> habits = const [],
      }) => _pump(
        tester,
        DailyCheckScreen(
          today: _today,
          addictions: addictions ?? all,
          profiles: sampleProfiles,
          previous: const [],
          habits: habits,
          catalog: sampleHabits,
          onSave: (checks, done) async {},
        ),
        repo: _Repo(),
        french: french,
        size: size,
      );

      testWidgets(
        'each profile asks craving and its two signals; generic asks craving only',
        (tester) async {
          await pumpCheck(tester);
          for (final a in all) {
            final name = a.profile == null
                ? l.addictionType(a.type.name)
                : _spec(a.profile!).name.of(lang);
            final card = find.widgetWithText(Card, name);
            expect(card, findsOneWidget, reason: name);
            expect(
              find.descendant(
                of: card,
                matching: find.text(l.dailyCheckWithout(name)),
              ),
              findsOneWidget,
              reason: name,
            );
            final labels = [
              for (final r in tester.widgetList<RatingRow>(
                find.descendant(of: card, matching: find.byType(RatingRow)),
              ))
                r.label,
            ];
            expect(labels, [
              l.dailyCheckCraving,
              if (a.profile case final p?)
                for (final s in _spec(p).signals) s.label.of(lang),
            ], reason: name);
          }
        },
      );

      testWidgets(
        'direction follows the language; 320 wide nothing overflows',
        (tester) async {
          await pumpCheck(
            tester,
            size: const Size(320, 7000),
            habits: [
              const Habit(id: 'h1', kind: HabitKind.callFamily),
              Habit(
                id: 'h2',
                kind: HabitKind.custom,
                text: french ? 'Jardiner le soir' : 'البستنة في المساء',
              ),
            ],
          );
          expect(tester.takeException(), isNull);
          expect(_dir(tester, find.byType(DailyCheckScreen)), dir);
          expect(find.text(l.habitsTitle), findsOneWidget);
          _expectTranslated(tester, french: french);
        },
      );

      testWidgets(
        'Save stays off until every question is answered, and says why',
        (tester) async {
          await pumpCheck(
            tester,
            addictions: [_addiction('c', profile: SubstanceProfile.cocaine)],
          );
          final save = find.widgetWithText(FilledButton, l.addictionSave);
          expect(tester.widget<FilledButton>(save).onPressed, isNull);
          expect(find.text(l.dailyCheckNeedAnswers), findsOneWidget);
          await tester.tap(find.text(l.dailyCheckYes));
          await tester.tap(
            find.byKey(ValueKey('rating-${l.dailyCheckCraving}-2')),
          );
          await tester.pump();
          // The two signals are still missing.
          expect(tester.widget<FilledButton>(save).onPressed, isNull);
          for (final s in _spec(SubstanceProfile.cocaine).signals) {
            await tester.tap(
              find.byKey(ValueKey('rating-${s.label.of(lang)}-3')),
            );
          }
          await tester.pump();
          expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
          expect(find.text(l.dailyCheckNeedAnswers), findsNothing);
        },
      );

      testWidgets('saving every addiction marks today done on the week strip', (
        tester,
      ) async {
        final repo = _Repo();
        await _pump(tester, const HomeShell(), repo: repo, french: french);
        await _scrollTo(tester, find.text(l.dailyCheckAction));
        await tester.tap(find.text(l.dailyCheckAction));
        await _settle(tester);
        await _answerAll(tester, l, lang, repo.addictionList);
        await _tapVisible(
          tester,
          find.widgetWithText(FilledButton, l.addictionSave),
        );
        await _settle(tester);
        expect(repo.checks.where((c) => c.day == _today), hasLength(1));
        expect(find.byType(DailyCheckScreen), findsNothing);
        expect(find.text(l.dailyCheckAction), findsNothing);
        expect(find.text(l.checkInDone), findsWidgets);
      });
    });

    group('addiction form (PRD 3) · $lang', () {
      Future<_Repo> openForm(
        WidgetTester tester, {
        Size size = const Size(390, 844),
      }) async {
        final repo = _Repo();
        await _pump(
          tester,
          const HomeShell(),
          repo: repo,
          french: french,
          size: size,
        );
        await _scrollTo(tester, find.text(l.addictionAddAnother));
        await tester.tap(find.text(l.addictionAddAnother));
        await _settle(tester);
        return repo;
      }

      testWidgets(
        'profiles, another substance and its types, the date; 320 wide',
        (tester) async {
          await openForm(tester, size: const Size(320, 2400));
          expect(find.byType(AddictionFormScreen), findsOneWidget);
          for (final s in sampleProfiles) {
            expect(
              find.widgetWithText(ChoiceChip, s.name.of(lang)),
              findsOneWidget,
            );
          }
          await tester.tap(find.widgetWithText(ChoiceChip, l.substanceOther));
          await tester.pumpAndSettle();
          for (final t in AddictionType.values) {
            expect(
              find.widgetWithText(ChoiceChip, l.addictionType(t.name)),
              findsOneWidget,
            );
          }
          expect(find.text(l.addictionCleanSince), findsOneWidget);
          expect(find.text(l.longDate(_today)), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(_dir(tester, find.byType(AddictionFormScreen)), dir);
          _expectTranslated(tester, french: french);
        },
      );

      testWidgets("a saved entry waits for the doctor's review", (
        tester,
      ) async {
        final repo = await openForm(tester);
        await tester.tap(
          find.widgetWithText(
            ChoiceChip,
            _spec(SubstanceProfile.nicotine).name.of(lang),
          ),
        );
        await tester.pumpAndSettle();
        await _tapVisible(
          tester,
          find.widgetWithText(FilledButton, l.addictionSave),
        );
        await _settle(tester);
        expect(repo.addictionList, hasLength(2));
        expect(find.byType(AddictionFormScreen), findsNothing);
        expect(find.text(l.addictionSaved), findsOneWidget);
        await _scrollTo(tester, find.text(l.addictionPending));
        expect(find.text(l.addictionPending), findsOneWidget);
      });
    });

    group('habits and small goals (PRD 5.6) · $lang', () {
      testWidgets(
        'add a habit: the clinic list, own words, a reminder; 320 wide',
        (tester) async {
          await _pump(
            tester,
            const HomeShell(),
            repo: _Repo(),
            french: french,
            size: const Size(320, 2400),
          );
          await _scrollTo(tester, find.text(l.habitsAdd));
          await tester.tap(find.text(l.habitsAdd));
          await _settle(tester);
          // The habit already kept (sport) is not offered twice.
          expect(
            find.widgetWithText(
              ChoiceChip,
              sampleHabits[HabitKind.sport]!.of(lang),
            ),
            findsNothing,
          );
          for (final k in [
            HabitKind.brushTeeth,
            HabitKind.water,
            HabitKind.reading,
            HabitKind.callFamily,
            HabitKind.sleep,
          ]) {
            expect(
              find.widgetWithText(ChoiceChip, sampleHabits[k]!.of(lang)),
              findsOneWidget,
            );
          }
          final save = find.widgetWithText(FilledButton, l.addictionSave);
          expect(tester.widget<FilledButton>(save).onPressed, isNull);
          await tester.tap(find.widgetWithText(ChoiceChip, l.habitsOwn));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byType(TextField)).maxLength,
            60,
          );
          expect(find.text(l.checkInReminderOff), findsWidgets);
          expect(tester.takeException(), isNull);
          _expectTranslated(tester, french: french);
        },
      );

      testWidgets(
        'the goal sheet: steps not reached yet, and automatic; 320 wide',
        (tester) async {
          await _pump(
            tester,
            const HomeShell(),
            repo: _Repo(),
            french: french,
            size: const Size(320, 2400),
          );
          await _scrollTo(tester, find.text(l.goalChange));
          await tester.tap(find.text(l.goalChange));
          await _settle(tester);
          expect(find.text(l.goalTitle), findsOneWidget);
          expect(
            find.widgetWithText(
              ChoiceChip,
              '${l.goalAuto} · ${l.bookDays(14)}',
            ),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(ChoiceChip, l.bookDays(14)),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(ChoiceChip, l.bookDays(28)),
            findsOneWidget,
          );
          expect(find.widgetWithText(ChoiceChip, l.bookDays(7)), findsNothing);
          expect(tester.takeException(), isNull);
          _expectTranslated(tester, french: french);
        },
      );
    });

    group('relapse (PRD 5.1, 5.6) · $lang', () {
      final relapseWords = [
        l.recoveryRelapse,
        l.recoveryRelapseTitle,
        l.recoveryRelapseBody,
        l.recoveryRelapseNote,
        l.recoveryRelapseConfirm,
        l.recoveryRelapseCancel,
        l.recoveryRelapseDone,
        l.relapseWhen,
      ];

      Future<_Repo> openSheet(
        WidgetTester tester, {
        List<Addiction>? addictions,
        Size size = const Size(390, 844),
      }) async {
        final repo = _Repo(addictions: addictions);
        await _pump(
          tester,
          const HomeShell(),
          repo: repo,
          french: french,
          size: size,
        );
        await _scrollTo(tester, find.text(l.recoveryRelapse));
        await tester.tap(find.text(l.recoveryRelapse));
        await _settle(tester);
        return repo;
      }

      test(
        'the wording is supportive, never judgmental, never a diagnosis',
        () {
          _expectGentle(relapseWords, lang);
        },
      );

      testWidgets('the sheet keeps the past and names the doctor as support', (
        tester,
      ) async {
        await openSheet(tester);
        expect(find.text(l.recoveryRelapseTitle), findsOneWidget);
        expect(find.text(l.recoveryRelapseBody), findsOneWidget);
        expect(find.text(l.recoveryRelapseCancel), findsOneWidget);
        _expectTranslated(tester, french: french);
      });

      testWidgets(
        'after a relapse: the counter restarts, longest and total stay',
        (tester) async {
          // 9 days now; 21 days was the longest; 55 days before this streak.
          final repo = _Repo(
            addictions: [
              _addiction('a1', profile: SubstanceProfile.pregabalin),
            ],
          );
          await _pump(tester, const HomeShell(), repo: repo, french: french);
          expect(find.text(l.bookDays(21)), findsWidgets);
          expect(find.text(l.bookDays(64)), findsWidgets);
          await _scrollTo(tester, find.text(l.recoveryRelapse));
          await tester.tap(find.text(l.recoveryRelapse));
          await _settle(tester);
          await tester.tap(find.text(l.recoveryRelapseConfirm));
          await _settle(tester);

          expect(repo.relapses, hasLength(1));
          expect(_snack(tester), l.recoveryRelapseDone);
          _expectGentle([_snack(tester)!], lang);
          expect(
            tester.widget<SobrietyRing>(find.byType(SobrietyRing)).days,
            0,
          );
          // The small goal goes back to one day (PRD 5.6).
          expect(find.text(l.recoveryNextGoal(l.bookDays(1))), findsOneWidget);
          expect(find.text(l.bookDays(21)), findsWidgets); // longest
          expect(find.text(l.bookDays(64)), findsWidgets); // total
        },
      );

      testWidgets('the streak that ends becomes the longest when it was', (
        tester,
      ) async {
        final repo = _Repo(
          addictions: [_addiction('a1', days: 40, longestPast: 10, past: 5)],
        );
        await _pump(tester, const HomeShell(), repo: repo, french: french);
        await _scrollTo(tester, find.text(l.recoveryRelapse));
        await tester.tap(find.text(l.recoveryRelapse));
        await _settle(tester);
        await tester.tap(find.text(l.recoveryRelapseConfirm));
        await _settle(tester);
        expect(repo.addictionList.single.longestPastDays, 40);
        expect(find.text(l.bookDays(40)), findsWidgets); // longest
        expect(find.text(l.bookDays(45)), findsWidgets); // total
      });

      testWidgets('320 wide: the relapse sheet fits', (tester) async {
        await openSheet(tester, size: const Size(320, 640));
        expect(tester.takeException(), isNull);
        expect(find.text(l.recoveryRelapseConfirm), findsOneWidget);
      });
    });

    group('24-hour time pickers (PRD 5.4, 5.6) · $lang', () {
      void expect24h(WidgetTester tester) {
        final dialog = find.byType(TimePickerDialog);
        expect(dialog, findsOneWidget);
        expect(
          MediaQuery.alwaysUse24HourFormatOf(tester.element(dialog)),
          isTrue,
        );
        final texts = _texts(tester, dialog);
        for (final dayPeriod in ['AM', 'PM', 'ص', 'م']) {
          expect(texts, isNot(contains(dayPeriod)));
        }
      }

      testWidgets('the daily reminder', (tester) async {
        await _pump(tester, const HomeShell(), repo: _Repo(), french: french);
        final time = find.descendant(
          of: find.byType(WeekCheckCard),
          matching: find.text('21:00'),
        );
        await _scrollTo(tester, time);
        await tester.tap(time);
        await tester.pumpAndSettle();
        expect24h(tester);
      });

      testWidgets("a habit's reminder", (tester) async {
        await _pump(tester, const HomeShell(), repo: _Repo(), french: french);
        final time = find.descendant(
          of: find.byType(HabitsCard),
          matching: find.text('18:00'),
        );
        await _scrollTo(tester, time);
        await tester.tap(time);
        await tester.pumpAndSettle();
        expect24h(tester);
      });

      testWidgets('the reminder of a new habit', (tester) async {
        await _pump(tester, const HomeShell(), repo: _Repo(), french: french);
        await _scrollTo(tester, find.text(l.habitsAdd));
        await tester.tap(find.text(l.habitsAdd));
        await _settle(tester);
        await tester.tap(find.text(l.checkInReminderOff).last);
        await tester.pumpAndSettle();
        expect24h(tester);
      });

      testWidgets('when the relapse happened, shown 24-hour', (tester) async {
        await _pump(tester, const HomeShell(), repo: _Repo(), french: french);
        await _scrollTo(tester, find.text(l.recoveryRelapse));
        await tester.tap(find.text(l.recoveryRelapse));
        await _settle(tester);
        expect(find.text('17:10'), findsOneWidget);
        await tester.tap(find.text('17:10'));
        await tester.pumpAndSettle();
        expect24h(tester);
      });
    });
  }

  group('a double tap sends one request', () {
    Future<void> doubleTap(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 60));
      if (finder.evaluate().isNotEmpty) {
        await tester.tap(finder, warnIfMissed: false);
      }
      await _settle(tester);
    }

    _bug(
      'UX-04',
      'double tap on Taken sends two dose answers',
      'Taken on a dose',
      (tester) async {
        final repo = _Repo();
        await _pump(tester, const HomeShell(), repo: repo);
        await _scrollTo(tester, find.text(_ar.recoveryDoseTake));
        await doubleTap(tester, find.text(_ar.recoveryDoseTake));
        expect(repo.count('markDose'), 1);
      },
    );

    _bug(
      'UX-04',
      'double tap on "day without use" sends two ticks',
      '"day without use" tick',
      (tester) async {
        final repo = _Repo(addictions: []);
        await _pump(tester, const HomeShell(), repo: repo);
        await _scrollTo(tester, find.text(_ar.checkInAction));
        await doubleTap(tester, find.text(_ar.checkInAction));
        expect(repo.count('checkIn'), 1);
      },
    );

    _bug(
      'UX-04',
      'double tap on a habit tick sends two requests',
      'habit done today',
      (tester) async {
        final repo = _Repo();
        await _pump(tester, const HomeShell(), repo: repo);
        final box = find.descendant(
          of: find.byType(HabitsCard),
          matching: find.byType(Checkbox),
        );
        await _scrollTo(tester, box);
        await doubleTap(tester, box);
        expect(repo.count('markHabit'), 1);
      },
    );

    _bug('UX-04', 'double tap on Remove sends two deletes', 'remove a habit', (
      tester,
    ) async {
      final repo = _Repo();
      await _pump(tester, const HomeShell(), repo: repo);
      final remove = find.byTooltip(
        _ar.habitsRemove(sampleHabits[HabitKind.sport]!.ar),
      );
      await _scrollTo(tester, remove);
      await doubleTap(tester, remove);
      expect(repo.count('removeHabit'), 1);
    });

    _bug(
      'UX-04',
      'double tap on "stop reminder" sends two requests',
      'stop the daily reminder',
      (tester) async {
        final repo = _Repo();
        await _pump(tester, const HomeShell(), repo: repo);
        final stop = find.byTooltip(_ar.checkInReminderStop);
        await _scrollTo(tester, stop);
        await doubleTap(tester, stop);
        expect(repo.count('setReminder'), 1);
      },
    );

    testWidgets('Save on the daily check', (tester) async {
      final repo = _Repo();
      await _pump(tester, const HomeShell(), repo: repo);
      await _scrollTo(tester, find.text(_ar.dailyCheckAction));
      await tester.tap(find.text(_ar.dailyCheckAction));
      await _settle(tester);
      await _answerAll(tester, _ar, 'ar', repo.addictionList);
      final save = find.widgetWithText(FilledButton, _ar.addictionSave);
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await doubleTap(tester, save);
      expect(repo.count('saveCheck'), 1);
    });

    testWidgets('Save on the addiction form', (tester) async {
      final repo = _Repo();
      await _pump(tester, const HomeShell(), repo: repo);
      await _scrollTo(tester, find.text(_ar.addictionAddAnother));
      await tester.tap(find.text(_ar.addictionAddAnother));
      await _settle(tester);
      await tester.tap(
        find.widgetWithText(
          ChoiceChip,
          _spec(SubstanceProfile.nicotine).name.ar,
        ),
      );
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, _ar.addictionSave);
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await doubleTap(tester, save);
      expect(repo.count('addAddiction'), 1);
    });

    testWidgets('Restart my counter on the relapse sheet', (tester) async {
      final repo = _Repo();
      await _pump(tester, const HomeShell(), repo: repo);
      await _scrollTo(tester, find.text(_ar.recoveryRelapse));
      await tester.tap(find.text(_ar.recoveryRelapse));
      await _settle(tester);
      await doubleTap(tester, find.text(_ar.recoveryRelapseConfirm));
      expect(repo.count('logRelapse'), 1);
    });

    testWidgets('Save on the add-habit sheet', (tester) async {
      final repo = _Repo();
      await _pump(tester, const HomeShell(), repo: repo);
      await _scrollTo(tester, find.text(_ar.habitsAdd));
      await tester.tap(find.text(_ar.habitsAdd));
      await _settle(tester);
      await tester.tap(
        find.widgetWithText(ChoiceChip, sampleHabits[HabitKind.water]!.ar),
      );
      await tester.pumpAndSettle();
      await doubleTap(
        tester,
        find.widgetWithText(FilledButton, _ar.addictionSave),
      );
      expect(repo.count('addHabit'), 1);
    });

    testWidgets('a step on the goal sheet', (tester) async {
      final repo = _Repo();
      await _pump(tester, const HomeShell(), repo: repo);
      await _scrollTo(tester, find.text(_ar.goalChange));
      await tester.tap(find.text(_ar.goalChange));
      await _settle(tester);
      await doubleTap(
        tester,
        find.widgetWithText(ChoiceChip, _ar.bookDays(28)),
      );
      expect(repo.count('setGoal'), 1);
    });

    testWidgets('Continue on a milestone celebration', (tester) async {
      // Day 9, day 7 not celebrated yet.
      final repo = _Repo(
        addictions: [
          _addiction('a1', profile: SubstanceProfile.pregabalin, seen: 3),
        ],
      );
      await _pump(tester, const HomeShell(), repo: repo);
      expect(find.byType(MilestoneScreen), findsOneWidget);
      await doubleTap(tester, find.text(_ar.milestoneContinue));
      expect(find.byType(MilestoneScreen), findsNothing);
      expect(find.byType(RecoveryScreen), findsOneWidget);
      expect(repo.count('markMilestoneSeen'), 1);
    });
  });

  group('the milestone celebration on a small phone', () {
    for (final french in [false, true]) {
      testWidgets('two years of badges, 320×568 · ${french ? 'fr' : 'ar'}', (
        tester,
      ) async {
        await _pump(
          tester,
          MilestoneScreen(
            days: 730,
            name: french ? 'Prégabaline' : 'البريغابالين',
          ),
          repo: _Repo(),
          french: french,
          size: const Size(320, 568),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('screen readers and tap targets (PRD 8.6)', () {
    final screens = <String, Widget>{
      'home': const HomeShell(),
      'daily check': DailyCheckScreen(
        today: _today,
        addictions: [_addiction('a1', profile: SubstanceProfile.pregabalin)],
        profiles: sampleProfiles,
        previous: const [],
        habits: const [Habit(id: 'h1', kind: HabitKind.sport)],
        catalog: sampleHabits,
        onSave: (checks, done) async {},
      ),
      'addiction form': AddictionFormScreen(
        today: _now,
        profiles: sampleProfiles,
        onSave: (_) async {},
      ),
    };

    for (final MapEntry(key: name, value: screen) in screens.entries) {
      testWidgets('$name: every tap target has a label', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, screen, repo: _Repo());
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }

    testWidgets('locked: every tap target has a label, 48×48', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const HomeShell(), repo: _Repo(locked: true));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('home: tap targets at least 48×48', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const HomeShell(), repo: _Repo());
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('addiction form: tap targets at least 48×48', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, screens['addiction form']!, repo: _Repo());
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    _bug(
      'UX-09',
      'rating circles are 44 px high (41 px wide at 320)',
      'daily check: tap targets at least 48×48 (320 wide)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(
          tester,
          screens['daily check']!,
          repo: _Repo(),
          size: const Size(320, 1400),
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      },
    );

    _bug(
      'UX-08',
      'excludeSemantics drops the rating tap action',
      'a rating answer can be activated by a screen reader',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, screens['daily check']!, repo: _Repo());
        expect(
          tester.getSemantics(
            find.byKey(ValueKey('rating-${_ar.dailyCheckCraving}-3')),
          ),
          isSemantics(isButton: true, hasTapAction: true),
        );
        handle.dispose();
      },
    );

    _bug(
      'UX-08',
      "excludeSemantics drops the habit checkbox's state and tap action",
      'a habit tick is a checkbox a screen reader can toggle',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, const HomeShell(), repo: _Repo());
        final box = find.descendant(
          of: find.byType(HabitsCard),
          matching: find.byType(Checkbox),
        );
        await _scrollTo(tester, box);
        expect(
          tester.getSemantics(box),
          isSemantics(hasCheckedState: true, hasTapAction: true),
        );
        handle.dispose();
      },
    );

    _bug(
      'UX-08',
      'excludeSemantics drops the date button tap action',
      'the clean-since date can be changed with a screen reader',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, screens['addiction form']!, repo: _Repo());
        expect(
          tester.getSemantics(find.byIcon(Icons.event_rounded)),
          isSemantics(isButton: true, hasTapAction: true),
        );
        handle.dispose();
      },
    );
  });

  group('PRD rules the screens do not meet yet', () {
    for (final french in [false, true]) {
      final lang = french ? 'fr' : 'ar';
      final l = french ? _fr : _ar;

      _bug(
        'UX-05',
        'the counter shows days only, not hours',
        'the counter shows days and hours (PRD 5.1) · $lang',
        (tester) async {
          // 9 days and 3 hours since the start.
          await _pump(tester, const HomeShell(), repo: _Repo(), french: french);
          final texts = _texts(tester, find.byType(CounterCard));
          final hours = french
              ? RegExp(r'\b3\s*(h|heures?)\b')
              : RegExp(r'3\s*(ساعات|ساعة)');
          expect(texts.any(hours.hasMatch), isTrue, reason: '$texts');
        },
      );

      _bug(
        'UX-06',
        'reaching a small goal that is not a milestone is not celebrated',
        'reaching the 4-week goal is celebrated (PRD 5.6) · $lang',
        (tester) async {
          // Day 28 reaches the last small step; the milestone before is 14.
          await _pump(
            tester,
            const HomeShell(),
            repo: _Repo(
              addictions: [
                _addiction('a1', profile: SubstanceProfile.thc, days: 28),
              ],
            ),
            french: french,
          );
          expect(find.text(l.milestoneTitle), findsOneWidget);
        },
      );

      _bug(
        'UX-07',
        'a due dose offers Taken and Not taken, no Snooze',
        'a due dose offers Taken, Skipped and Snooze (PRD 5.3) · $lang',
        (tester) async {
          await _pump(
            tester,
            const HomeShell(),
            repo: _Repo(),
            french: french,
            size: const Size(390, 3000),
          );
          final answers = find.descendant(
            of: find.byType(DosesCard),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          );
          expect(answers, findsNWidgets(3));
        },
      );

      _bug(
        'UX-07',
        'no dose reminder is scheduled on the phone',
        "today's due dose gets a neutral local reminder (PRD 5.3) · $lang",
        (tester) async {
          final notifications = FakeNotifications();
          await _pump(
            tester,
            const HomeShell(),
            repo: _Repo(
              habits: const [Habit(id: 'h1', kind: HabitKind.sport)],
              reminderTime: null,
            ),
            french: french,
            extra: [
              localNotificationsProvider.overrideWithValue(notifications),
            ],
          );
          final at21 = [
            for (final r in notifications.scheduled.values)
              if (r.at == DateTime(2026, 10, 17, 21)) r,
          ];
          expect(at21, isNotEmpty);
          for (final r in at21) {
            expect(r.body, isNot(contains(_evening.name.of(lang))));
          }
        },
      );

      _bug(
        'UX-02',
        'the relapse note has no 500-character limit',
        'the relapse note stops at the 500 characters the server takes · $lang',
        (tester) async {
          await _pump(tester, const HomeShell(), repo: _Repo(), french: french);
          await _scrollTo(tester, find.text(l.recoveryRelapse));
          await tester.tap(find.text(l.recoveryRelapse));
          await _settle(tester);
          expect(
            tester.widget<TextField>(find.byType(TextField)).maxLength,
            500,
          );
        },
      );

      _bug(
        'UX-02',
        'the exact substance has no 100-character limit',
        'the exact substance stops at the 100 characters the server takes · $lang',
        (tester) async {
          await _pump(
            tester,
            AddictionFormScreen(
              today: _now,
              profiles: sampleProfiles,
              onSave: (_) async {},
            ),
            repo: _Repo(),
            french: french,
          );
          expect(
            tester.widget<TextField>(find.byType(TextField)).maxLength,
            100,
          );
        },
      );
    }

    _bugTest(
      'UX-10',
      'Arabic calls the pills type "hallucinogenic"',
      'the Arabic name of the pills type is not "hallucinogenic" (PRD 3)',
      () {
        expect(_ar.addictionType('pills'), isNot(contains('مهلوس')));
      },
    );
  });
}
