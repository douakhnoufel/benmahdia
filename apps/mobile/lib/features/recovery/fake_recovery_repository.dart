import 'recovery_models.dart';
import 'recovery_repository.dart';

/// Demo data for the recovery home: one counter at 9 days, two doses today
/// (the morning one taken) and the Benmahdia practice.
class FakeRecoveryRepository implements RecoveryRepository {
  FakeRecoveryRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    final now = _clock();
    _addictions = [
      Addiction(
        id: 'a1',
        type: AddictionType.pills,
        start: now.subtract(const Duration(days: 9, hours: 3)),
        longestPastDays: 21,
        pastDays: 55,
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
  late List<Addiction> _addictions;
  late List<Dose> _doses;

  /// The six days before today are ticked; today is not yet.
  late final Set<DateTime> _checkIns = {
    for (var i = 1; i <= 6; i++) dayOf(_clock()).subtract(Duration(days: i)),
  };
  DayTime? _reminder = (hour: 21, minute: 0);

  /// Relapses logged here, for tests.
  final relapses = <({String addictionId, String? note, DateTime at})>[];

  static const _wait = Duration(milliseconds: 200);

  @override
  DateTime now() => _clock();

  @override
  Future<List<Addiction>> addictions() async {
    await Future<void>.delayed(_wait);
    return List.of(_addictions);
  }

  @override
  Future<Addiction> addAddiction({
    required AddictionType type,
    required DateTime cleanSince,
    String? substance,
  }) async {
    await Future<void>.delayed(_wait);
    final added = Addiction(
      id: 'a${_addictions.length + 1}',
      type: type,
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
    await Future<void>.delayed(_wait);
    final when = at ?? now();
    final updated = addiction.relapsed(when);
    _addictions = [
      for (final a in _addictions) a.id == addiction.id ? updated : a,
    ];
    relapses.add((addictionId: addiction.id, note: note, at: when));
    return updated;
  }

  @override
  Future<Set<DateTime>> checkIns() async {
    await Future<void>.delayed(_wait);
    return Set.of(_checkIns);
  }

  @override
  Future<void> checkIn(DateTime day) async {
    await Future<void>.delayed(_wait);
    _checkIns.add(dayOf(day));
  }

  @override
  Future<DayTime?> reminder() async {
    await Future<void>.delayed(_wait);
    return _reminder;
  }

  @override
  Future<void> setReminder(DayTime? time) async {
    await Future<void>.delayed(_wait);
    _reminder = time;
  }

  @override
  Future<Quote> quoteOfDay() async {
    await Future<void>.delayed(_wait);
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
    await Future<void>.delayed(_wait);
    return List.of(_doses);
  }

  @override
  Future<Dose> markDose(Dose dose, DoseStatus status) async {
    await Future<void>.delayed(_wait);
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
