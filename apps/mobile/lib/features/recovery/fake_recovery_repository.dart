import 'recovery_models.dart';
import 'recovery_repository.dart';

/// Demo data for the recovery home: one pregabalin counter at 9 days, the
/// six days before today checked, one habit, two doses today (the morning
/// one taken) and the Benmahdia practice. With [locked], every call answers
/// [RecoveryLocked], as before the first paid appointment.
class FakeRecoveryRepository implements RecoveryRepository {
  FakeRecoveryRepository({DateTime Function()? clock, this.locked = false})
    : _clock = clock ?? DateTime.now {
    final now = _clock();
    _addictions = [
      Addiction(
        id: 'a1',
        type: AddictionType.pills,
        profile: SubstanceProfile.pregabalin,
        start: now.subtract(const Duration(days: 9, hours: 3)),
        longestPastDays: 21,
        pastDays: 55,
        // Day 7 was celebrated already: opening the demo shows no pop-up.
        milestoneSeen: 7,
      ),
    ];
    _doses = [
      const Dose(
        id: 'd1',
        name: LocalizedText(ar: 'دواء الصباح', fr: 'Médicament du matin'),
        amount: LocalizedText(ar: 'قرص واحد', fr: '1 comprimé'),
        instruction: LocalizedText(
          ar: 'بعد الفطور',
          fr: 'après le petit-déjeuner',
        ),
        hour: 8,
        minute: 0,
        status: DoseStatus.taken,
      ),
      const Dose(
        id: 'd2',
        name: LocalizedText(ar: 'دواء المساء', fr: 'Médicament du soir'),
        amount: LocalizedText(ar: 'قرص واحد', fr: '1 comprimé'),
        instruction: LocalizedText(ar: 'قبل النوم', fr: 'avant le coucher'),
        hour: 21,
        minute: 0,
        status: DoseStatus.due,
      ),
    ];
  }

  final DateTime Function() _clock;
  bool locked;
  late List<Addiction> _addictions;

  /// Checks saved here, for tests; the six days before today come seeded.
  late final checks = <AddictionCheck>[
    for (var i = 1; i <= 6; i++)
      AddictionCheck(
        addictionId: 'a1',
        day: dayOf(_clock()).subtract(Duration(days: i)),
        used: false,
        craving: 2,
        signals: const {'anxiety': 2, 'sleep': 3},
      ),
  ];

  late List<Habit> _habits = [
    Habit(
      id: 'h1',
      kind: HabitKind.sport,
      reminder: (hour: 18, minute: 0),
      days: {dayOf(_clock()).subtract(const Duration(days: 1))},
    ),
  ];
  late List<Dose> _doses;

  /// The six days before today are ticked; today is not yet.
  late final Set<DateTime> _checkIns = {
    for (var i = 1; i <= 6; i++) dayOf(_clock()).subtract(Duration(days: i)),
  };
  DayTime? _reminder = (hour: 21, minute: 0);

  /// What is stored now, for tests (no delay, unlike the calls).
  List<Addiction> get storedAddictions => List.of(_addictions);
  List<Habit> get storedHabits => List.of(_habits);

  /// Relapses logged here, for tests.
  final relapses = <({String addictionId, String? note, DateTime at})>[];

  static const _wait = Duration(milliseconds: 200);

  Future<void> _call() async {
    await Future<void>.delayed(_wait);
    if (locked) throw const RecoveryLocked();
  }

  @override
  DateTime now() => _clock();

  @override
  Future<List<Addiction>> addictions() async {
    await _call();
    return List.of(_addictions);
  }

  @override
  Future<Addiction> addAddiction({
    AddictionType? type,
    SubstanceProfile? profile,
    required DateTime cleanSince,
    String? substance,
  }) async {
    await _call();
    final added = Addiction(
      id: 'a${_addictions.length + 1}',
      type: profile == null ? type! : _profileOf(profile).type,
      profile: profile,
      substance: substance,
      reviewed: false,
      start: cleanSince,
      longestPastDays: 0,
      pastDays: 0,
    );
    _addictions = [..._addictions, added];
    return added;
  }

  @override
  Future<Addiction> logRelapse(
    Addiction addiction, {
    String? note,
    DateTime? at,
  }) async {
    await _call();
    final when = at ?? now();
    final updated = addiction.relapsed(when);
    _addictions = [
      for (final a in _addictions) a.id == addiction.id ? updated : a,
    ];
    relapses.add((addictionId: addiction.id, note: note, at: when));
    return updated;
  }

  @override
  Future<Addiction> setGoal(Addiction addiction, int? days) async {
    await _call();
    final updated = addiction.withGoal(days);
    _addictions = [
      for (final a in _addictions) a.id == addiction.id ? updated : a,
    ];
    return updated;
  }

  @override
  Future<Addiction> markMilestoneSeen(Addiction addiction) async {
    await _call();
    final updated = addiction.withMilestoneSeen(
      addiction.milestone ?? reachedMilestone(addiction.days(now())),
    );
    _addictions = [
      for (final a in _addictions) a.id == addiction.id ? updated : a,
    ];
    return updated;
  }

  @override
  Future<List<ProfileSpec>> profiles() async {
    await _call();
    return sampleProfiles;
  }

  ProfileSpec _profileOf(SubstanceProfile p) =>
      sampleProfiles.firstWhere((s) => s.profile == p);

  @override
  Future<CheckHistory> addictionChecks() async {
    await _call();
    final done = <DateTime>{};
    for (final day in {for (final c in checks) c.day}) {
      final ids = {
        for (final c in checks)
          if (c.day == day) c.addictionId,
      };
      if (_addictions.every((a) => ids.contains(a.id))) done.add(day);
    }
    return (checks: List.of(checks), doneDays: done);
  }

  @override
  Future<void> saveCheck(AddictionCheck check) async {
    await _call();
    checks
      ..removeWhere(
        (c) => c.addictionId == check.addictionId && c.day == check.day,
      )
      ..add(check);
  }

  @override
  Future<Map<HabitKind, LocalizedText>> habitCatalog() async {
    await _call();
    return sampleHabits;
  }

  @override
  Future<List<Habit>> habits() async {
    await _call();
    return List.of(_habits);
  }

  @override
  Future<Habit> addHabit(
    HabitKind kind, {
    String? text,
    DayTime? reminder,
  }) async {
    await _call();
    final added = Habit(
      id: 'h${_habits.length + 1}',
      kind: kind,
      text: text,
      reminder: reminder,
    );
    _habits = [..._habits, added];
    return added;
  }

  @override
  Future<void> removeHabit(Habit habit) async {
    await _call();
    _habits = [
      for (final h in _habits)
        if (h.id != habit.id) h,
    ];
  }

  @override
  Future<Habit> setHabitReminder(Habit habit, DayTime? time) async {
    await _call();
    final updated = habit.copyWith(reminder: time, clearReminder: time == null);
    _habits = [for (final h in _habits) h.id == habit.id ? updated : h];
    return updated;
  }

  @override
  Future<void> markHabit(
    Habit habit,
    DateTime day, {
    required bool done,
  }) async {
    await _call();
    _habits = [
      for (final h in _habits)
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
  Future<Set<DateTime>> checkIns() async {
    await _call();
    return Set.of(_checkIns);
  }

  @override
  Future<void> checkIn(DateTime day) async {
    await _call();
    _checkIns.add(dayOf(day));
  }

  @override
  Future<DayTime?> reminder() async {
    await _call();
    return _reminder;
  }

  @override
  Future<void> setReminder(DayTime? time) async {
    await _call();
    _reminder = time;
  }

  @override
  Future<Quote> quoteOfDay() async {
    await _call();
    return const Quote(
      text: LocalizedText(
        ar: 'لست مضطراً لأن تنتصر اليوم كله. يكفي أن تنتصر في هذه الساعة.',
        fr: "Vous n'avez pas à gagner toute la journée. Il suffit de gagner cette heure-ci.",
      ),
      source: LocalizedText(ar: 'من فريق العيادة', fr: "L'équipe du cabinet"),
    );
  }

  @override
  Future<List<Dose>> todaysDoses() async {
    await _call();
    return List.of(_doses);
  }

  @override
  Future<Dose> markDose(Dose dose, DoseStatus status) async {
    await _call();
    final updated = dose.withStatus(status);
    _doses = [for (final d in _doses) d.id == dose.id ? updated : d];
    return updated;
  }

  @override
  Future<ClinicInfo> clinic() async {
    await Future<void>.delayed(_wait);
    return benmahdiaClinic;
  }
}

/// The pilot practice. Hours are from its Google listing: confirm with the
/// clinic before launch.
final benmahdiaClinic = ClinicInfo(
  name: const LocalizedText(
    ar: 'عيادة د. بن مهدية حسين',
    fr: 'Cabinet du Dr Benmahdia Hocine',
  ),
  specialty: const LocalizedText(
    ar: 'الأمراض العصبية والنفسية',
    fr: 'Neuro-psychiatrie',
  ),
  address: const LocalizedText(
    ar: 'حي الموز 680 مسكن، العمارة 11 (الطابق الأرضي)، قرب الدرك الوطني، البليدة 09000',
    fr: 'Cité Bananiers 680 Logements, Bât. 11 (RDC), près de la gendarmerie, Blida 09000',
  ),
  phones: const ['+213 551 03 83 85', '+213 697 17 23 26'],
  maps: Uri.parse('https://share.google/gizHNbNpfRqdHfYmQ'),
  hours: const {
    DateTime.saturday: [_morning, _afternoon],
    DateTime.sunday: [_morning, _afternoon],
    DateTime.monday: [_morning],
    DateTime.tuesday: [_morning, _afternoon],
    DateTime.wednesday: [_morning, _afternoon],
    DateTime.thursday: [(from: 7 * 60, to: 14 * 60 + 30)],
    DateTime.friday: [],
  },
);

const OpenHours _morning = (from: 7 * 60, to: 12 * 60 + 30);
const OpenHours _afternoon = (from: 13 * 60 + 30, to: 14 * 60 + 30);

/// The server's substance catalog (backend/app/substances.py), for demo
/// mode and tests. The notes are placeholders the clinic replaces.
const sampleProfiles = [
  ProfileSpec(
    profile: SubstanceProfile.nicotine,
    type: AddictionType.tobacco,
    name: LocalizedText(ar: 'النيكوتين', fr: 'Nicotine'),
    signals: [_irritability, _restlessness],
    notes: [_day3, _day14, _day30],
  ),
  ProfileSpec(
    profile: SubstanceProfile.thc,
    type: AddictionType.cannabis,
    name: LocalizedText(ar: 'القنب (الحشيش)', fr: 'Cannabis (THC)'),
    signals: [_sleep, _irritability],
    notes: [_day3, _day14, _day30],
  ),
  ProfileSpec(
    profile: SubstanceProfile.pregabalin,
    type: AddictionType.pills,
    name: LocalizedText(ar: 'البريغابالين', fr: 'Prégabaline'),
    signals: [_anxiety, _sleep],
    notes: [_day3, _day7, _day30],
  ),
  ProfileSpec(
    profile: SubstanceProfile.buprenorphine,
    type: AddictionType.opioids,
    name: LocalizedText(ar: 'البوبرينورفين', fr: 'Buprénorphine'),
    signals: [_discomfort, _sleep],
    notes: [_day3, _day7, _day30],
  ),
  ProfileSpec(
    profile: SubstanceProfile.cocaine,
    type: AddictionType.stimulants,
    name: LocalizedText(ar: 'الكوكايين', fr: 'Cocaïne'),
    signals: [_lowMood, _lowEnergy],
    notes: [_day3, _day14, _day30],
  ),
  ProfileSpec(
    profile: SubstanceProfile.amphetamines,
    type: AddictionType.stimulants,
    name: LocalizedText(
      ar: 'الأمفيتامينات (أديرال)',
      fr: 'Amphétamines (Adderall)',
    ),
    signals: [_sleep, _lowAppetite],
    notes: [_day3, _day14, _day30],
  ),
];

const _irritability = SignalSpec(
  key: 'irritability',
  label: LocalizedText(ar: 'العصبية', fr: 'Irritabilité'),
);
const _restlessness = SignalSpec(
  key: 'restlessness',
  label: LocalizedText(ar: 'التململ', fr: 'Agitation'),
);
const _sleep = SignalSpec(
  key: 'sleep',
  label: LocalizedText(ar: 'صعوبة النوم', fr: 'Troubles du sommeil'),
);
const _anxiety = SignalSpec(
  key: 'anxiety',
  label: LocalizedText(ar: 'القلق', fr: 'Anxiété'),
);
const _discomfort = SignalSpec(
  key: 'discomfort',
  label: LocalizedText(
    ar: 'انزعاج جسدي (آلام، تعرق)',
    fr: 'Inconfort physique (douleurs, sueurs)',
  ),
);
const _lowMood = SignalSpec(
  key: 'low_mood',
  label: LocalizedText(ar: 'انخفاض المزاج', fr: 'Humeur basse'),
);
const _lowEnergy = SignalSpec(
  key: 'low_energy',
  label: LocalizedText(ar: 'قلة الطاقة', fr: "Manque d'énergie"),
);
const _lowAppetite = SignalSpec(
  key: 'low_appetite',
  label: LocalizedText(ar: 'قلة الشهية', fr: "Perte d'appétit"),
);

const _day3 = EarlyNote(
  day: 3,
  text: LocalizedText(
    ar: 'الأيام الأولى غالبًا ما تكون الأصعب. لقد تجاوزت مرحلة مهمة.',
    fr: 'Les premiers jours sont souvent les plus durs. Vous avez passé un cap.',
  ),
);
const _day7 = EarlyNote(
  day: 7,
  text: LocalizedText(
    ar: 'أسبوع كامل. كل يوم يقوّي عزيمتك.',
    fr: 'Une semaine entière. Chaque jour renforce votre élan.',
  ),
);
const _day14 = EarlyNote(
  day: 14,
  text: LocalizedText(
    ar: 'أسبوعان. كثيرون يلاحظون تحسنًا في يومهم في هذه المرحلة.',
    fr: "Deux semaines. Beaucoup remarquent que leurs journées s'améliorent à ce stade.",
  ),
);
const _day30 = EarlyNote(
  day: 30,
  text: LocalizedText(
    ar: 'شهر كامل. تحدث مع طبيبك عما تغيّر.',
    fr: 'Un mois entier. Parlez à votre médecin de ce qui a changé.',
  ),
);

/// The server's habit list (backend/app/habits.py).
const sampleHabits = {
  HabitKind.sport: LocalizedText(ar: 'الرياضة أو المشي', fr: 'Sport ou marche'),
  HabitKind.brushTeeth: LocalizedText(
    ar: 'تنظيف الأسنان',
    fr: 'Se brosser les dents',
  ),
  HabitKind.water: LocalizedText(ar: 'شرب الماء', fr: "Boire de l'eau"),
  HabitKind.reading: LocalizedText(ar: 'القراءة', fr: 'Lire'),
  HabitKind.callFamily: LocalizedText(
    ar: 'الاتصال بالعائلة',
    fr: 'Appeler la famille',
  ),
  HabitKind.sleep: LocalizedText(
    ar: 'النوم في الوقت',
    fr: "Se coucher à l'heure",
  ),
};
