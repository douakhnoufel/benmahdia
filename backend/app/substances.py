"""What each substance profile tracks (PRD 5.6): its base addiction type, the
two signals its daily check rates 1-5, and the short "what to expect" notes
on early days. The apps render from this catalog (GET .../recovery/profiles),
so a question changes here and nowhere else.

The notes are development placeholders: the clinic's doctors write or approve
the real text before launch. They stay supportive and never name a diagnosis."""

from dataclasses import dataclass

from .models import AddictionType, SubstanceProfile


@dataclass(frozen=True)
class Text:
    ar: str
    fr: str


@dataclass(frozen=True)
class Note:
    day: int
    text: Text


@dataclass(frozen=True)
class Profile:
    key: SubstanceProfile
    type: AddictionType
    name: Text
    signals: tuple[str, str]
    notes: tuple[Note, ...]


# Each rated 1-5, higher = harder.
SIGNALS: dict[str, Text] = {
    "irritability": Text("العصبية", "Irritabilité"),
    "restlessness": Text("التململ", "Agitation"),
    "sleep": Text("صعوبة النوم", "Troubles du sommeil"),
    "anxiety": Text("القلق", "Anxiété"),
    "discomfort": Text("انزعاج جسدي (آلام، تعرق)", "Inconfort physique (douleurs, sueurs)"),
    "low_mood": Text("انخفاض المزاج", "Humeur basse"),
    "low_energy": Text("قلة الطاقة", "Manque d'énergie"),
    "low_appetite": Text("قلة الشهية", "Perte d'appétit"),
}

# Placeholders, shared by every profile until the clinic writes its own.
_DAY_3 = Note(3, Text(
    "الأيام الأولى غالبًا ما تكون الأصعب. لقد تجاوزت مرحلة مهمة.",
    "Les premiers jours sont souvent les plus durs. Vous avez passé un cap.",
))
_DAY_7 = Note(7, Text(
    "أسبوع كامل. كل يوم يقوّي عزيمتك.",
    "Une semaine entière. Chaque jour renforce votre élan.",
))
_DAY_14 = Note(14, Text(
    "أسبوعان. كثيرون يلاحظون تحسنًا في يومهم في هذه المرحلة.",
    "Deux semaines. Beaucoup remarquent que leurs journées s'améliorent à ce stade.",
))
_DAY_30 = Note(30, Text(
    "شهر كامل. تحدث مع طبيبك عما تغيّر.",
    "Un mois entier. Parlez à votre médecin de ce qui a changé.",
))


def _profile(key, type_, ar, fr, signals, days) -> Profile:
    return Profile(key, type_, Text(ar, fr), signals, days)


PROFILES: dict[SubstanceProfile, Profile] = {
    p.key: p
    for p in (
        _profile(SubstanceProfile.nicotine, AddictionType.tobacco, "النيكوتين", "Nicotine",
                 ("irritability", "restlessness"), (_DAY_3, _DAY_14, _DAY_30)),
        _profile(SubstanceProfile.thc, AddictionType.cannabis, "القنب (الحشيش)", "Cannabis (THC)",
                 ("sleep", "irritability"), (_DAY_3, _DAY_14, _DAY_30)),
        _profile(SubstanceProfile.pregabalin, AddictionType.pills, "البريغابالين", "Prégabaline",
                 ("anxiety", "sleep"), (_DAY_3, _DAY_7, _DAY_30)),
        _profile(SubstanceProfile.buprenorphine, AddictionType.opioids, "البوبرينورفين",
                 "Buprénorphine", ("discomfort", "sleep"), (_DAY_3, _DAY_7, _DAY_30)),
        _profile(SubstanceProfile.cocaine, AddictionType.stimulants, "الكوكايين", "Cocaïne",
                 ("low_mood", "low_energy"), (_DAY_3, _DAY_14, _DAY_30)),
        _profile(SubstanceProfile.amphetamines, AddictionType.stimulants,
                 "الأمفيتامينات (أديرال)", "Amphétamines (Adderall)",
                 ("sleep", "low_appetite"), (_DAY_3, _DAY_14, _DAY_30)),
    )
}


def signals_of(profile: SubstanceProfile | None) -> tuple[str, ...]:
    """The signal keys a daily check must rate: none for generic tracking."""
    return PROFILES[profile].signals if profile is not None else ()


# Small goals (PRD 5.6): the steps a patient can aim for, in days; after the
# last one the milestone ladder (PRD 5.1) takes over, then every year.
GOAL_STEPS = (1, 3, 7, 14, 28)
LATER_MILESTONES = (60, 90, 180, 365)


def next_goal(streak_days: int) -> int:
    """The step the app picks by itself: the first one not reached yet."""
    for step in GOAL_STEPS + LATER_MILESTONES:
        if streak_days < step:
            return step
    return (streak_days // 365 + 1) * 365


def current_goal(streak_days: int, chosen: int | None) -> int:
    """The patient's own choice while it is still ahead, else the next step."""
    if chosen is not None and streak_days < chosen:
        return chosen
    return next_goal(streak_days)
