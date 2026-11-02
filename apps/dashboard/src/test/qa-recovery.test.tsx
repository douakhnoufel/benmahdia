import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signOut } from '../api';
import { I18nProvider, type Lang } from '../i18n';
import { Alerts } from '../pages/Alerts';
import { PatientDetail } from '../pages/PatientDetail';
import { lastDays } from '../pages/Tracking';

// QA recovery run 2026-10-26 (ux-clients): what the doctor reads about a
// patient's recovery (PRD 5.6 "What the doctor sees", 7) and the alerts
// inbox, in Arabic (RTL, the default) and French. Sample data only: fake
// phones, no real patients, no medical content beyond what a check needs.
//
// A test that shows a real bug is written with `bug(...)` (it.fails) and its
// QA id from qa/recovery/2026-10-26/ux-clients.md: it passes while the bug is
// there. To see each one fail for its real reason, run with QA_RUN_BUGS=true.

const bug = process.env.QA_RUN_BUGS === 'true' ? it : it.fails;

type Reply = { status: number; body?: unknown } | undefined;

const PHONE = '+213661234501';
const patient = { id: 'p1', phone: PHONE };

const PROFILES = [
  {
    key: 'pregabalin',
    type: 'pills',
    name: { ar: 'البريغابالين', fr: 'Prégabaline' },
    signals: [
      { key: 'anxiety', label: { ar: 'القلق', fr: 'Anxiété' } },
      { key: 'sleep', label: { ar: 'صعوبة النوم', fr: 'Troubles du sommeil' } },
    ],
  },
];

const DAY = 24 * 60 * 60 * 1000;
const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Algiers' }).format(new Date());
const [yesterday, twoDaysAgo] = [1, 2].map((n) => lastDays(today, n + 1)[0]);

/** Patient's own words, in the language of the test (they are not translated). */
const words = {
  fr: { note: 'Une soirée difficile', habit: 'Jardiner', medicine: 'Médicament A' },
  ar: { note: 'سهرة صعبة', habit: 'البستنة', medicine: 'دواء أ' },
};

function addictions(lang: Lang) {
  return [
    {
      id: 'ad1',
      type: 'pills',
      profile: 'pregabalin',
      substance: null,
      goal_days: 28,
      goal: 28,
      // 9 days and 3 hours into this streak; 21 days was the longest; 55 before.
      clean_since: new Date(Date.now() - 9 * DAY - 3 * 60 * 60 * 1000).toISOString(),
      longest_past_days: 21,
      past_days: 55,
      review_status: 'confirmed',
      // 23:30 UTC is already the next day in Algiers.
      relapses: [{ at: '2026-10-15T23:30:00Z', note: words[lang].note }],
    },
    {
      id: 'ad2',
      type: 'alcohol',
      profile: null,
      substance: null,
      goal_days: null,
      goal: 3,
      clean_since: new Date(Date.now() - 2 * DAY).toISOString(),
      longest_past_days: 0,
      past_days: 0,
      review_status: 'pending',
      relapses: [],
    },
  ];
}

const checks = {
  days: 30,
  checked_days: 2,
  checks: [
    { addiction_id: 'ad1', day: twoDaysAgo, used: false, craving: 2, signals: { anxiety: 3, sleep: 4 } },
    { addiction_id: 'ad1', day: yesterday, used: false, craving: 4, signals: { anxiety: 1, sleep: 2 } },
  ],
};

function habits(lang: Lang) {
  return [
    { id: 'h1', kind: 'water', text: null, days: 30, done_days: 12 },
    { id: 'h2', kind: 'custom', text: words[lang].habit, days: 30, done_days: 3 },
  ];
}

const ALERT_KINDS = ['relapse', 'missed_doses', 'craving_high', 'no_checkin', 'milestone'] as const;

function alertRows() {
  const base = { patient_id: 'p1', patient_phone: PHONE, read: false, created_at: '2026-10-17T10:00:00Z' };
  return [
    ...ALERT_KINDS.map((type, i) => ({ ...base, id: `al${i}`, type, priority: type === 'relapse' ? 'high' : 'normal' })),
    { ...base, id: 'alx', type: 'some_future_kind', priority: 'normal' },
  ];
}

function backend(lang: Lang, handler: (url: URL, init: RequestInit) => Reply = () => undefined) {
  const calls: { url: URL; init: RequestInit }[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: URL, init: RequestInit) => {
      calls.push({ url: input, init });
      const { status, body } = handler(input, init) ?? defaults(lang, input, init);
      return new Response(status === 204 ? null : body === undefined ? '' : JSON.stringify(body), { status });
    }),
  );
  return calls;
}

function defaults(lang: Lang, url: URL, init: RequestInit): { status: number; body?: unknown } {
  const p = url.pathname;
  const method = init.method ?? 'GET';
  if (p === '/v1/staff/recovery/profiles') return { status: 200, body: PROFILES };
  if (p.endsWith('/addictions') && method === 'GET') return { status: 200, body: addictions(lang) };
  if (p.endsWith('/confirm')) return { status: 200, body: { ...addictions(lang)[1], review_status: 'confirmed' } };
  if (p.endsWith('/checks')) return { status: 200, body: checks };
  if (p.endsWith('/habits')) return { status: 200, body: habits(lang) };
  if (p.endsWith('/medications') && method === 'GET') {
    return {
      status: 200,
      body: [{ id: 'm1', name: words[lang].medicine, amount: '1', times: ['08:00'], start_date: '2026-10-10', end_date: null, instructions: null }],
    };
  }
  if (p.includes('/medications/') && method === 'DELETE') return { status: 204 };
  if (p === '/v1/staff/alerts') return { status: 200, body: alertRows() };
  if (p.endsWith('/read')) return { status: 200, body: { ...alertRows()[0], read: true } };
  return { status: 200, body: [] };
}

function renderIn(ui: React.ReactNode, lang: Lang) {
  return render(<I18nProvider initial={lang}>{ui}</I18nProvider>);
}

function openFile(lang: Lang) {
  return renderIn(<PatientDetail patient={patient} onBack={() => undefined} />, lang);
}

const T = {
  fr: {
    profile: 'Prégabaline',
    generic: 'Alcool',
    confirmed: 'Confirmée',
    pending: 'À vérifier',
    current: 'Série actuelle',
    longest: 'Plus longue série',
    total: 'Total des jours sans consommation',
    goal: 'Petit objectif',
    goalChosen: 'choisi par le patient',
    goalAuto: 'automatique',
    relapses: 'Rechutes',
    noRelapses: 'Aucune rechute.',
    craving: 'Envie de consommer',
    signals: ['Anxiété', 'Troubles du sommeil'],
    checked: '2 jours remplis sur 30',
    chartTitle: 'Bilan quotidien — 30 derniers jours',
    notDiagnosis: /pas un diagnostic/,
    water: 'Boire de l’eau',
    habitDone: ['12 jours sur 30', '3 jours sur 30'],
    noAddictions: "Le patient n'a saisi aucune addiction.",
    noChecks: 'Aucun bilan sur cette période.',
    noHabits: 'Le patient n’a choisi aucune habitude.',
    noMedications: 'Aucun médicament prescrit.',
    offline: 'Impossible de joindre le serveur. Réessayez.',
    retry: 'Réessayer',
    alerts: {
      relapse: 'Rechute signalée',
      missed_doses: 'Prises manquées depuis 2 jours',
      craving_high: 'Forte envie 3 jours de suite',
      no_checkin: 'Aucun bilan depuis 3 jours',
      milestone: 'Nouvelle étape sans consommation',
    },
    alertOther: 'Alerte',
    high: 'Prioritaire',
    noAlerts: 'Aucune alerte.',
    dir: 'ltr',
  },
  ar: {
    profile: 'البريغابالين',
    generic: 'كحول',
    confirmed: 'مؤكَّد',
    pending: 'في انتظار المراجعة',
    current: 'السلسلة الحالية',
    longest: 'أطول سلسلة',
    total: 'مجموع الأيام دون تعاطٍ',
    goal: 'الهدف الصغير',
    goalChosen: 'اختاره المريض',
    goalAuto: 'تلقائي',
    relapses: 'الانتكاسات',
    noRelapses: 'لا انتكاسات.',
    craving: 'الرغبة في التعاطي',
    signals: ['القلق', 'صعوبة النوم'],
    checked: '2 من 30 يوما مسجّلة',
    chartTitle: 'التسجيل اليومي — آخر 30 يوما',
    notDiagnosis: /ليست تشخيصا/,
    water: 'شرب الماء',
    habitDone: ['12 من 30 يوما', '3 من 30 يوما'],
    noAddictions: 'لم يسجّل المريض أي إدمان.',
    noChecks: 'لا تسجيلات في هذه الفترة.',
    noHabits: 'لم يختر المريض أي عادة بعد.',
    noMedications: 'لا توجد أدوية موصوفة.',
    offline: 'تعذر الاتصال بالخادم. حاول مجددا.',
    retry: 'إعادة المحاولة',
    alerts: {
      relapse: 'انتكاسة مسجّلة',
      missed_doses: 'جرعات فائتة منذ يومين',
      craving_high: 'رغبة قوية 3 أيام متتالية',
      no_checkin: 'لا تسجيل يومي منذ 3 أيام',
      milestone: 'بلغ مرحلة جديدة دون تعاطٍ',
    },
    alertOther: 'تنبيه',
    high: 'عاجل',
    noAlerts: 'لا توجد تنبيهات.',
    dir: 'rtl',
  },
} as const;

// API values that must never reach the screen as they are.
const RAW = /\b(pregabalin|pills|alcohol|confirmed|pending|rejected|anxiety|craving_high|no_checkin|missed_doses|milestone|relapse|some_future_kind|[a-z]+_[a-z_]+)\b/;

// Units stay in Latin letters in Arabic text ("50 mg" in the dose example).
const UNITS = new Set(['mg']);

/** No API code on screen; in Arabic no Latin word either (phones are digits). */
function expectTranslated(lang: Lang) {
  const text = document.body.textContent ?? '';
  expect(text).not.toMatch(RAW);
  if (lang === 'ar') expect((text.match(/[A-Za-z]{2,}/g) ?? []).filter((w) => !UNITS.has(w))).toEqual([]);
}

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
});

for (const lang of ['fr', 'ar'] as const) {
  const t = T[lang];

  describe(`patient file: what the doctor sees (PRD 5.6, 7) · ${lang}`, () => {
    it('profile, review state, counter, longest streak, total days and small goal', async () => {
      backend(lang);
      openFile(lang);
      const first = (await screen.findByRole('heading', { name: t.profile })).closest('article')!;
      expect(document.documentElement.dir).toBe(t.dir);
      expect(document.documentElement.lang).toBe(lang);
      expect(within(first).getByText(t.confirmed)).toBeInTheDocument();
      // 9 days now (the 3 hours do not make a day), 21 the longest, 55 + 9 in all.
      const scope = within(first);
      const value = (label: string) => scope.getByText(label).parentElement!.firstChild!.textContent;
      expect(value(t.current)).toMatch(/^9\D/);
      expect(value(t.longest)).toMatch(/^21\D/);
      expect(value(t.total)).toMatch(/^64\D/);
      expect(value(t.goal)).toMatch(new RegExp(`^28\\D.*${t.goalChosen}`));
      // The selected profile reads as its name, not its key.
      expect(scope.getByRole('combobox')).toHaveDisplayValue(t.profile);

      // The generic entry still waits for review, with its automatic goal.
      const second = screen.getByRole('heading', { name: t.generic }).closest('article')!;
      expect(within(second).getByText(t.pending)).toBeInTheDocument();
      expect(within(second).getByText(t.goal).parentElement!.firstChild!.textContent).toMatch(
        new RegExp(`^3\\D.*${t.goalAuto}`),
      );
      expect(within(second).getByText(t.noRelapses)).toBeInTheDocument();
    });

    it('relapses with their notes; the date is the Algiers day', async () => {
      backend(lang);
      openFile(lang);
      const first = (await screen.findByRole('heading', { name: t.profile })).closest('article')!;
      expect(within(first).getByText(t.relapses)).toBeInTheDocument();
      const item = within(first).getByText(new RegExp(words[lang].note));
      // 2026-10-15 23:30 UTC is 16 October 00:30 in Algiers.
      expect(item.textContent).toMatch(/^16\D/);
      expect(item.textContent).not.toMatch(/^15\D/);
    });

    it('a 30-day chart of craving and the two signals, and check-in days out of 30', async () => {
      const calls = backend(lang);
      openFile(lang);
      await screen.findByRole('heading', { name: t.profile });
      expect(await screen.findAllByText(t.chartTitle)).toHaveLength(2);
      expect(screen.getAllByText(t.checked)).toHaveLength(2);
      // The profiled addiction rates craving and its two signals...
      for (const row of [t.craving, ...t.signals]) {
        expect(screen.getAllByRole('group', { name: row }).length).toBeGreaterThan(0);
      }
      // ...the generic one craving only: two craving rows, one row per signal.
      expect(screen.getAllByRole('group', { name: t.craving })).toHaveLength(2);
      for (const row of t.signals) expect(screen.getAllByRole('group', { name: row })).toHaveLength(1);
      // 30 columns per row, two of them rated.
      const cols = screen.getAllByRole('group', { name: t.signals[0] })[0].querySelectorAll('[aria-label]');
      expect(cols).toHaveLength(30);
      expect(screen.getAllByText(t.notDiagnosis).length).toBeGreaterThan(0);
      expect(calls.filter((c) => c.url.pathname.endsWith('/checks') && c.url.search === '?days=30')).toHaveLength(2);
    });

    it('good habits with the days done out of 30', async () => {
      backend(lang);
      openFile(lang);
      expect(await screen.findByText(t.water)).toBeInTheDocument();
      expect(screen.getByText(t.habitDone[0])).toBeInTheDocument();
      expect(screen.getByText(words[lang].habit)).toBeInTheDocument();
      expect(screen.getByText(t.habitDone[1])).toBeInTheDocument();
    });

    it('no API code on screen, and nothing left untranslated', async () => {
      backend(lang);
      openFile(lang);
      await screen.findByText(t.water);
      await screen.findAllByText(t.checked);
      expectTranslated(lang);
    });

    it('empty states: no addiction, no habit, no medicine', async () => {
      backend(lang, (url, init) => {
        const p = url.pathname;
        if ((p.endsWith('/addictions') || p.endsWith('/habits') || p.endsWith('/medications')) && (init.method ?? 'GET') === 'GET') {
          return { status: 200, body: [] };
        }
        return undefined;
      });
      openFile(lang);
      expect(await screen.findByText(t.noAddictions)).toBeInTheDocument();
      expect(await screen.findByText(t.noHabits)).toBeInTheDocument();
      expect(await screen.findByText(t.noMedications)).toBeInTheDocument();
      expectTranslated(lang);
    });

    it('empty chart: no check in 30 days', async () => {
      backend(lang, (url) =>
        url.pathname.endsWith('/checks') ? { status: 200, body: { days: 30, checked_days: 0, checks: [] } } : undefined,
      );
      openFile(lang);
      expect(await screen.findAllByText(t.noChecks)).toHaveLength(2);
      expect(screen.queryByRole('group', { name: t.craving })).toBeNull();
    });

    it('a failed load offers a retry that loads the file', async () => {
      let failures = 1;
      backend(lang, (url, init) => {
        if (url.pathname.endsWith('/addictions') && (init.method ?? 'GET') === 'GET' && failures > 0) {
          failures -= 1;
          return { status: 500 };
        }
        return undefined;
      });
      openFile(lang);
      expect(await screen.findByText(t.offline)).toBeInTheDocument();
      const card = screen.getByText(t.offline).closest('div')!.parentElement!;
      await userEvent.click(within(card).getByRole('button', { name: t.retry }));
      expect(await screen.findByRole('heading', { name: t.profile })).toBeInTheDocument();
    });
  });

  describe(`alerts inbox (PRD 5.1, 5.3, 5.6, 7) · ${lang}`, () => {
    it('names every recovery alert kind, with no code and no medical content', async () => {
      backend(lang);
      renderIn(<Alerts onOpen={() => undefined} />, lang);
      for (const kind of ALERT_KINDS) {
        expect(await screen.findByText(t.alerts[kind])).toBeInTheDocument();
      }
      // An unknown kind still reads as an alert, never as its code.
      expect(screen.getByText(t.alertOther)).toBeInTheDocument();
      // Only the relapse is high priority.
      expect(screen.getAllByText(t.high)).toHaveLength(1);
      expect(within(screen.getByText(t.alerts.relapse).parentElement!).getByText(t.high)).toBeInTheDocument();
      expect(document.documentElement.dir).toBe(t.dir);
      expectTranslated(lang);
      for (const leak of [/Prégabaline|البريغابالين/, /Anxiété|القلق/, new RegExp(words[lang].note)]) {
        expect(screen.queryByText(leak)).toBeNull();
      }
    });

    it('says so when there is no alert', async () => {
      backend(lang, (url) => (url.pathname === '/v1/staff/alerts' ? { status: 200, body: [] } : undefined));
      renderIn(<Alerts onOpen={() => undefined} />, lang);
      expect(await screen.findByText(t.noAlerts)).toBeInTheDocument();
    });
  });
}

describe('feedback when the server refuses a change (UX-03)', () => {
  bug('UX-03: a failed confirm is silent', async () => {
    const calls = backend('fr', (url) => (url.pathname.endsWith('/confirm') ? { status: 500 } : undefined));
    openFile('fr');
    const second = (await screen.findByRole('heading', { name: 'Alcool' })).closest('article')!;
    await userEvent.click(within(second).getByRole('button', { name: 'Confirmer' }));
    await waitFor(() => expect(calls.some((c) => c.url.pathname.endsWith('/confirm'))).toBe(true));
    // The doctor is told the review was not saved.
    expect(await screen.findByRole('alert')).toBeInTheDocument();
  });

  bug('UX-03: a failed "mark read" is silent', async () => {
    const calls = backend('fr', (url) => (url.pathname.endsWith('/read') ? { status: 500 } : undefined));
    renderIn(<Alerts onOpen={() => undefined} />, 'fr');
    await screen.findByText(T.fr.alerts.relapse);
    await userEvent.click(screen.getAllByRole('button', { name: 'Marquer lu' })[0]);
    await waitFor(() => expect(calls.some((c) => c.url.pathname.endsWith('/read'))).toBe(true));
    expect(await screen.findByRole('alert')).toBeInTheDocument();
  });

  bug('UX-03: a failed "stop" on a medicine is silent', async () => {
    const calls = backend('fr', (url, init) =>
      url.pathname.includes('/medications/') && init.method === 'DELETE' ? { status: 500 } : undefined,
    );
    openFile('fr');
    await screen.findByText(/Médicament A/);
    await userEvent.click(screen.getByRole('button', { name: 'Arrêter' }));
    await waitFor(() => expect(calls.some((c) => c.init.method === 'DELETE')).toBe(true));
    expect(await screen.findByRole('alert')).toBeInTheDocument();
  });
});

describe('Arabic wording (UX-14)', () => {
  bug('UX-14: "9 يوم" is not Arabic; 3 to 10 days take the plural "أيام"', async () => {
    backend('ar');
    openFile('ar');
    const first = (await screen.findByRole('heading', { name: T.ar.profile })).closest('article')!;
    const value = within(first).getByText(T.ar.current).parentElement!.firstChild!.textContent;
    expect(value).toBe('9 أيام');
  });
});
