import { fireEvent, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signOut, type Availability } from '../api';
import { I18nProvider, type Lang } from '../i18n';
import { AvailabilityPage, problem, slotCount, toClock, toMinute } from '../pages/Availability';

type Handler = (url: URL, init: RequestInit) => { status: number; body?: unknown };

function mockFetch(handler: Handler) {
  const calls: { url: URL; init: RequestInit }[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: URL, init: RequestInit) => {
      calls.push({ url: input, init });
      const { status, body } = handler(input, init);
      return new Response(body === undefined ? '' : JSON.stringify(body), { status });
    }),
  );
  return calls;
}

function renderIn(lang: Lang = 'fr') {
  return render(
    <I18nProvider initial={lang}>
      <AvailabilityPage />
    </I18nProvider>,
  );
}

// Every day but Friday, 09:00-12:00 and 14:00-16:00, like the seed.
const seeded: Availability = {
  slot_minutes: 15,
  notice_hours: 24,
  windows: [0, 1, 2, 3, 5, 6].flatMap((weekday) => [
    { weekday, start_minute: 540, end_minute: 720 },
    { weekday, start_minute: 840, end_minute: 960 },
  ]),
  blocked_days: [],
  conflicts: [],
};

const region = (name: string) => screen.getByRole('region', { name });

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
});

describe('availability helpers', () => {
  it('converts clock times', () => {
    expect(toClock(540)).toBe('09:00');
    expect(toClock(1440)).toBe('24:00');
    expect(toMinute('14:05')).toBe(845);
    expect(toMinute('')).toBeNull();
    expect(toMinute('24:01')).toBeNull();
  });

  it('checks a day like the server does', () => {
    const w = (start_minute: number, end_minute: number) => ({ weekday: 0, start_minute, end_minute });
    expect(problem([w(540, 720), w(720, 840)])).toBeNull();
    expect(problem([w(543, 720)])).toBe('errOffGrid');
    expect(problem([w(720, 540)])).toBe('errEmptyWindow');
    expect(problem([w(540, 720), w(700, 840)])).toBe('errOverlap');
    expect(problem([0, 1, 2, 3, 4, 5, 6].map((h) => w(h * 60, h * 60 + 30)))).toBe('errTooMany');
    expect(slotCount([w(540, 720), w(840, 960)], 15)).toBe(20);
    expect(slotCount([w(540, 560)], 15)).toBe(1);
  });
});

describe('Availability page', () => {
  it('shows the week from Saturday with the slots and the breaks', async () => {
    mockFetch(() => ({ status: 200, body: seeded }));
    renderIn();
    const week = await screen.findByRole('region', { name: 'Horaires de la semaine' });
    const days = within(week).getAllByRole('heading', { level: 4 }).map((h) => h.textContent);
    expect(days).toEqual(['samedi', 'dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi']);
    expect(within(week).getAllByText('20 créneaux')).toHaveLength(6);
    expect(within(week).getAllByText('Pause 12:00–14:00')).toHaveLength(6);
    expect(within(week).getByText('Fermé')).toBeInTheDocument();
    expect(within(week).getByLabelText('De · lundi 1')).toHaveValue('09:00');
  });

  it('saves the edited week', async () => {
    const calls = mockFetch((_, init) =>
      init.method === 'PUT' ? { status: 200, body: { ...seeded, ...JSON.parse(init.body as string) } } : { status: 200, body: seeded },
    );
    renderIn();
    const week = await screen.findByRole('region', { name: 'Horaires de la semaine' });
    fireEvent.change(within(week).getByLabelText('De · lundi 1'), { target: { value: '10:00' } });
    await userEvent.click(within(week).getByRole('button', { name: 'Supprimer la plage · samedi 2' }));
    await userEvent.click(within(week).getByRole('button', { name: 'Enregistrer les horaires' }));
    expect(await within(week).findByRole('status')).toHaveTextContent('Enregistré.');
    const put = calls.find((c) => c.init.method === 'PUT')!;
    expect(put.url.pathname).toBe('/v1/staff/availability/windows');
    const { windows } = JSON.parse(put.init.body as string);
    expect(windows).toHaveLength(11);
    expect(windows.filter((w: { weekday: number }) => w.weekday === 5)).toEqual([{ weekday: 5, start_minute: 540, end_minute: 720 }]);
    expect(windows).toContainEqual({ weekday: 0, start_minute: 600, end_minute: 720 });
  });

  it('opens a closed day with a new period', async () => {
    const calls = mockFetch(() => ({ status: 200, body: seeded }));
    renderIn();
    const week = await screen.findByRole('region', { name: 'Horaires de la semaine' });
    const friday = within(week).getByRole('heading', { name: 'vendredi' }).closest('li')!;
    await userEvent.click(within(friday).getByRole('button', { name: 'Ajouter une plage' }));
    expect(within(friday).getByLabelText('De · vendredi 1')).toHaveValue('09:00');
    expect(within(friday).getByLabelText('À · vendredi 1')).toHaveValue('10:00');
    expect(within(friday).getByText('4 créneaux')).toBeInTheDocument();
    await userEvent.click(within(week).getByRole('button', { name: 'Enregistrer les horaires' }));
    const { windows } = JSON.parse(calls.find((c) => c.init.method === 'PUT')!.init.body as string);
    expect(windows).toContainEqual({ weekday: 4, start_minute: 540, end_minute: 600 });
  });

  it('refuses overlapping periods before sending anything', async () => {
    const calls = mockFetch(() => ({ status: 200, body: seeded }));
    renderIn();
    const week = await screen.findByRole('region', { name: 'Horaires de la semaine' });
    fireEvent.change(within(week).getByLabelText('À · lundi 1'), { target: { value: '15:00' } });
    expect(within(week).getByRole('alert')).toHaveTextContent('lundi — Deux plages se chevauchent le même jour.');
    expect(within(week).getByRole('button', { name: 'Enregistrer les horaires' })).toBeDisabled();
    expect(calls).toHaveLength(1);
  });

  it('explains a refusal from the server', async () => {
    mockFetch((_, init) =>
      init.method === 'PUT' ? { status: 400, body: { detail: { code: 'too_many_windows' } } } : { status: 200, body: seeded },
    );
    renderIn();
    const week = await screen.findByRole('region', { name: 'Horaires de la semaine' });
    await userEvent.click(within(week).getByRole('button', { name: 'Enregistrer les horaires' }));
    expect(await within(week).findByRole('alert')).toHaveTextContent('Six plages au maximum par jour.');
  });

  it('saves the slot length and the notice', async () => {
    const calls = mockFetch((_, init) =>
      init.method === 'PUT' ? { status: 200, body: { ...seeded, slot_minutes: 10, notice_hours: 48 } } : { status: 200, body: seeded },
    );
    renderIn();
    await screen.findByRole('region', { name: 'Réglages des rendez-vous' });
    const settings = region('Réglages des rendez-vous');
    await userEvent.selectOptions(within(settings).getByLabelText('Durée d’un créneau'), '10');
    const notice = within(settings).getByLabelText('Délai minimum pour réserver ou annuler (heures)');
    await userEvent.clear(notice);
    await userEvent.type(notice, '48');
    await userEvent.click(within(settings).getByRole('button', { name: 'Enregistrer' }));
    expect(await within(settings).findByRole('status')).toHaveTextContent('Enregistré.');
    const put = calls.find((c) => c.init.method === 'PUT')!;
    expect(put.url.pathname).toBe('/v1/staff/availability/settings');
    expect(JSON.parse(put.init.body as string)).toEqual({ slot_minutes: 10, notice_hours: 48 });
    // The week now counts 10-minute slots.
    expect(within(region('Horaires de la semaine')).getAllByText('30 créneaux')).toHaveLength(6);
  });

  it('refuses a notice above a week', async () => {
    mockFetch(() => ({ status: 200, body: seeded }));
    renderIn();
    const settings = await screen.findByRole('region', { name: 'Réglages des rendez-vous' });
    const notice = within(settings).getByLabelText('Délai minimum pour réserver ou annuler (heures)');
    await userEvent.clear(notice);
    await userEvent.type(notice, '200');
    expect(within(settings).getByRole('alert')).toHaveTextContent('Le délai doit être entre 0 et 168 heures.');
    expect(within(settings).getByRole('button', { name: 'Enregistrer' })).toBeDisabled();
  });

  it('blocks and reopens a day', async () => {
    const blocked = { ...seeded, blocked_days: [{ id: 'b1', day: '2026-11-01', reason: 'Fête' }] };
    const calls = mockFetch((_, init) =>
      init.method === 'POST' ? { status: 201, body: blocked } : init.method === 'DELETE' ? { status: 200, body: seeded } : { status: 200, body: seeded },
    );
    renderIn();
    const days = await screen.findByRole('region', { name: 'Jours fermés' });
    expect(within(days).getByText('Aucun jour fermé.')).toBeInTheDocument();
    fireEvent.change(within(days).getByLabelText('Jour'), { target: { value: '2026-11-01' } });
    await userEvent.type(within(days).getByLabelText('Motif (facultatif)'), 'Fête');
    await userEvent.click(within(days).getByRole('button', { name: 'Fermer ce jour' }));
    expect(await within(days).findByText('Fête')).toBeInTheDocument();
    const post = calls.find((c) => c.init.method === 'POST')!;
    expect(post.url.pathname).toBe('/v1/staff/availability/blocked-days');
    expect(JSON.parse(post.init.body as string)).toEqual({ day: '2026-11-01', reason: 'Fête' });
    expect(within(days).getByLabelText('Jour')).toHaveValue('');
    await userEvent.click(within(days).getByRole('button', { name: 'Rouvrir' }));
    expect(await within(days).findByText('Aucun jour fermé.')).toBeInTheDocument();
    expect(calls.at(-1)!.url.pathname).toBe('/v1/staff/availability/blocked-days/b1');
  });

  it('explains a day that is already closed', async () => {
    mockFetch((_, init) =>
      init.method === 'POST' ? { status: 409, body: { detail: { code: 'already_blocked' } } } : { status: 200, body: seeded },
    );
    renderIn();
    const days = await screen.findByRole('region', { name: 'Jours fermés' });
    fireEvent.change(within(days).getByLabelText('Jour'), { target: { value: '2026-11-01' } });
    await userEvent.click(within(days).getByRole('button', { name: 'Fermer ce jour' }));
    expect(await within(days).findByRole('alert')).toHaveTextContent('Ce jour est déjà fermé.');
  });

  it('lists booked visits left outside the hours', async () => {
    mockFetch(() => ({
      status: 200,
      body: {
        ...seeded,
        conflicts: [{ appointment_id: 'a1', start: '2026-11-02T08:00:00Z', patient_phone: '+213661234567', reason: 'outside_hours' }],
      },
    }));
    renderIn();
    const conflicts = await screen.findByRole('region', { name: 'Rendez-vous réservés hors des horaires' });
    expect(within(conflicts).getByText('+213661234567')).toBeInTheDocument();
    expect(within(conflicts).getByText('Hors horaires')).toBeInTheDocument();
    expect(within(conflicts).getByText('09:00')).toBeInTheDocument();
  });

  it('is in Arabic', async () => {
    mockFetch(() => ({ status: 200, body: seeded }));
    renderIn('ar');
    const week = await screen.findByRole('region', { name: 'ساعات العمل الأسبوعية' });
    expect(within(week).getAllByRole('heading', { level: 4 })[0]).toHaveTextContent('السبت');
    expect(document.documentElement.dir).toBe('rtl');
  });

  it('offers a retry when the server is down', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Promise.reject(new TypeError('offline'))));
    renderIn();
    expect(await screen.findByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
  });
});
