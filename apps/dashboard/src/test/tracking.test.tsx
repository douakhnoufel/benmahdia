import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signOut } from '../api';
import { I18nProvider, type Lang } from '../i18n';
import { Alerts } from '../pages/Alerts';
import { PatientDetail } from '../pages/PatientDetail';
import { fill, lastDays } from '../pages/Tracking';

// Per-substance tracking in the patient file (PRD 5.6, 7): the substance
// profile, the counters and small goal, the 30-day craving and signal chart,
// and the good habits. Nothing here is a diagnosis.

type Reply = { status: number; body?: unknown } | undefined;

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
  {
    key: 'cocaine',
    type: 'stimulants',
    name: { ar: 'الكوكايين', fr: 'Cocaïne' },
    signals: [
      { key: 'low_mood', label: { ar: 'انخفاض المزاج', fr: 'Humeur basse' } },
      { key: 'low_energy', label: { ar: 'قلة الطاقة', fr: "Manque d'énergie" } },
    ],
  },
];

// The clinic's "today" in the test environment, which the chart's calendar uses.
const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Algiers' }).format(new Date());
const [yesterday, twoDaysAgo] = [1, 2].map((n) => lastDays(today, n + 1)[0]);

const addiction = {
  id: 'ad1',
  type: 'pills',
  profile: 'pregabalin',
  goal_days: 28,
  goal: 28,
  substance: 'Lyrica',
  clean_since: new Date(Date.now() - 9 * 24 * 60 * 60 * 1000).toISOString(),
  longest_past_days: 21,
  past_days: 55,
  review_status: 'confirmed',
  relapses: [],
};

const checks = {
  days: 30,
  checked_days: 2,
  checks: [
    { addiction_id: 'ad1', day: twoDaysAgo, used: false, craving: 2, signals: { anxiety: 3, sleep: 4 } },
    { addiction_id: 'ad1', day: yesterday, used: true, craving: 5, signals: { anxiety: 5, sleep: 2 } },
  ],
};

const habits = [
  { id: 'h1', kind: 'sport', text: null, days: 30, done_days: 12 },
  { id: 'h2', kind: 'custom', text: 'Jardiner', days: 30, done_days: 3 },
];

function backend(handler: (url: URL, init: RequestInit) => Reply = () => undefined) {
  const calls: { url: URL; init: RequestInit }[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: URL, init: RequestInit) => {
      calls.push({ url: input, init });
      const own = handler(input, init);
      const { status, body } = own ?? defaults(input, init);
      return new Response(status === 204 ? null : body === undefined ? '' : JSON.stringify(body), { status });
    }),
  );
  return calls;
}

function defaults(url: URL, init: RequestInit): { status: number; body?: unknown } {
  const p = url.pathname;
  const method = init.method ?? 'GET';
  if (p === '/v1/staff/recovery/profiles') return { status: 200, body: PROFILES };
  if (p.endsWith('/addictions') && method === 'GET') return { status: 200, body: [addiction] };
  if (p.endsWith('/profile') && method === 'PUT') {
    const profile = JSON.parse(String(init.body)).profile;
    const type = PROFILES.find((x) => x.key === profile)?.type ?? addiction.type;
    return { status: 200, body: { ...addiction, profile, type } };
  }
  if (p.endsWith('/checks')) return { status: 200, body: checks };
  if (p.endsWith('/habits')) return { status: 200, body: habits };
  if (p.endsWith('/medications')) return { status: 200, body: [] };
  if (p.endsWith('/appointments')) return { status: 200, body: { attendance: { completed: 0, no_show: 0, rate: null }, appointments: [] } };
  if (p === '/v1/staff/alerts') {
    const base = { id: 'al1', patient_id: 'p1', patient_phone: '+213661234567', read: false, priority: 'normal', created_at: '2026-10-17T10:00:00Z' };
    return {
      status: 200,
      body: [
        { ...base, type: 'craving_high' },
        { ...base, id: 'al2', type: 'no_checkin' },
      ],
    };
  }
  return { status: 200, body: [] };
}

function renderIn(ui: React.ReactNode, lang: Lang = 'fr') {
  return render(<I18nProvider initial={lang}>{ui}</I18nProvider>);
}

const patient = { id: 'p1', phone: '+213661234567' };

function openFile(lang: Lang = 'fr') {
  return renderIn(<PatientDetail patient={patient} onBack={() => undefined} />, lang);
}

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
  // The sample backend; a test that needs its own answers calls backend() again.
  backend();
});

describe('substance profile', () => {
  it('names the substance, its type and the counters', async () => {
    openFile();
    expect(await screen.findByRole('heading', { name: 'Prégabaline' })).toBeInTheDocument();
    expect(screen.getByText('Lyrica')).toBeInTheDocument();
    // The type stays visible beside the substance.
    expect(screen.getByText('Médicaments (comprimés)')).toBeInTheDocument();
    // 9 days clean, longest 21, total 55 + 9, goal 28 chosen by the patient.
    expect(screen.getByText('9 j')).toBeInTheDocument();
    expect(screen.getByText('21 j')).toBeInTheDocument();
    expect(screen.getByText('64 j')).toBeInTheDocument();
    expect(screen.getByText('28 j · choisi par le patient')).toBeInTheDocument();
  });

  it('the doctor changes the profile, which sets the type', async () => {
    const calls = backend();
    openFile();
    const select = await screen.findByLabelText('Substance suivie');
    expect(select).toHaveValue('pregabalin');
    await userEvent.selectOptions(select, 'cocaine');
    // The type row follows the new substance ("Cocaïne" is also an option).
    expect(await screen.findByText('Stimulants')).toBeInTheDocument();
    expect(select).toHaveValue('cocaine');
    const put = calls.find((c) => c.init.method === 'PUT');
    expect(put?.url.pathname).toBe('/v1/staff/patients/p1/addictions/ad1/profile');
    expect(JSON.parse(String(put?.init.body))).toEqual({ profile: 'cocaine' });
  });

  it('can go back to generic tracking', async () => {
    const calls = backend();
    openFile();
    await userEvent.selectOptions(await screen.findByLabelText('Substance suivie'), '');
    await waitFor(() => expect(JSON.parse(String(calls.at(-1)?.init.body))).toEqual({ profile: null }));
  });

  it('tells the doctor when the change fails', async () => {
    backend((_url, init) => (init.method === 'PUT' ? { status: 500 } : undefined));
    openFile();
    await userEvent.selectOptions(await screen.findByLabelText('Substance suivie'), 'cocaine');
    expect(await screen.findByRole('alert')).toHaveTextContent('Changement impossible. Réessayez.');
  });
});

describe('daily checks', () => {
  it('charts craving and the profile signals, with the days filled', async () => {
    const calls = backend();
    openFile();
    expect(await screen.findByText('Bilan quotidien — 30 derniers jours')).toBeInTheDocument();
    expect(screen.getByText('2 jours remplis sur 30')).toBeInTheDocument();
    for (const row of ['Envie de consommer', 'Anxiété', 'Troubles du sommeil']) {
      expect(screen.getByRole('group', { name: row })).toBeInTheDocument();
    }
    // One bar per rated day, hover text carrying the value.
    const craving = screen.getByRole('group', { name: 'Envie de consommer' });
    expect(within(craving).getAllByLabelText(/sur 5/)).toHaveLength(2);
    expect(within(craving).getAllByLabelText(/5 sur 5/)).toHaveLength(1);
    expect(within(craving).getAllByLabelText(/non rempli/)).toHaveLength(28);
    expect(screen.getByText(/pas un diagnostic/)).toBeInTheDocument();
    expect(calls.some((c) => c.url.search === '?days=30')).toBe(true);
  });

  it('marks a declared use without calling it a relapse', async () => {
    openFile();
    expect(await screen.findAllByLabelText(/Consommation déclarée/)).toHaveLength(1);
  });

  it('offers the same numbers as a table', async () => {
    openFile();
    await userEvent.click(await screen.findByText('Voir le tableau'));
    const rows = within(screen.getByRole('table')).getAllByRole('row');
    expect(rows).toHaveLength(3); // header plus the two checked days
    expect(within(rows[2]).getAllByRole('cell').map((c) => c.textContent)).toEqual([
      expect.any(String),
      '●',
      '5',
      '5',
      '2',
    ]);
  });

  it('says so when nothing was filled in', async () => {
    backend((url) => (url.pathname.endsWith('/checks') ? { status: 200, body: { days: 30, checked_days: 0, checks: [] } } : undefined));
    openFile();
    expect(await screen.findByText('Aucun bilan sur cette période.')).toBeInTheDocument();
  });

  it('a generic addiction rates craving only', async () => {
    backend((url, init) =>
      url.pathname.endsWith('/addictions') && (init.method ?? 'GET') === 'GET'
        ? { status: 200, body: [{ ...addiction, profile: null }] }
        : undefined,
    );
    openFile();
    expect(await screen.findByRole('group', { name: 'Envie de consommer' })).toBeInTheDocument();
    expect(screen.queryByRole('group', { name: 'Anxiété' })).toBeNull();
  });
});

describe('good habits', () => {
  it('lists each habit with the days done out of 30', async () => {
    openFile();
    expect(await screen.findByText('Sport ou marche')).toBeInTheDocument();
    expect(screen.getByText('12 jours sur 30')).toBeInTheDocument();
    expect(screen.getByText('Jardiner')).toBeInTheDocument();
    expect(screen.getByText('3 jours sur 30')).toBeInTheDocument();
  });

  it('says so when the patient kept none', async () => {
    backend((url) => (url.pathname.endsWith('/habits') ? { status: 200, body: [] } : undefined));
    openFile();
    expect(await screen.findByText('Le patient n’a choisi aucune habitude.')).toBeInTheDocument();
  });
});

describe('Arabic', () => {
  it('shows the tracking in Arabic', async () => {
    openFile('ar');
    expect(await screen.findByRole('heading', { name: 'البريغابالين' })).toBeInTheDocument();
    expect(screen.getByLabelText('المادة المتابَعة')).toBeInTheDocument();
    expect(screen.getByRole('group', { name: 'القلق' })).toBeInTheDocument();
    expect(screen.getByText('الرياضة أو المشي')).toBeInTheDocument();
    expect(document.documentElement.dir).toBe('rtl');
  });
});

describe('alerts', () => {
  it('names the craving and missed-check alerts without medical content', async () => {
    backend();
    renderIn(<Alerts onOpen={() => undefined} />);
    expect(await screen.findByText('Forte envie 3 jours de suite')).toBeInTheDocument();
    expect(screen.getByText('Aucun bilan depuis 3 jours')).toBeInTheDocument();
    for (const leak of [/craving/i, /Prégabaline/, /Anxiété/]) {
      expect(screen.queryByText(leak)).toBeNull();
    }
  });
});

describe('helpers', () => {
  it('fills the counts into a string', () => {
    expect(fill('{n} jours sur {d}', { n: 3, d: 30 })).toBe('3 jours sur 30');
  });

  it('lists the calendar days oldest first, ending today', () => {
    const days = lastDays('2026-03-02', 4);
    expect(days).toEqual(['2026-02-27', '2026-02-28', '2026-03-01', '2026-03-02']);
  });
});
