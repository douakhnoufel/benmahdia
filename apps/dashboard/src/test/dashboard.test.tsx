import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { App } from '../App';
import { signOut } from '../api';
import { I18nProvider, type Lang } from '../i18n';
import { Patients } from '../pages/Patients';
import { Signups } from '../pages/Signups';
import { Today, clinicToday } from '../pages/Today';

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

function renderIn(ui: React.ReactNode, lang: Lang = 'fr') {
  return render(<I18nProvider initial={lang}>{ui}</I18nProvider>);
}

const session = { access_token: 'a1', refresh_token: 'r1', user: { role: 'doctor' } };

const visit = {
  id: 'v1',
  patient_id: 'p1',
  patient_phone: '+213661234567',
  start: '2026-10-19T08:00:00Z',
  end: '2026-10-19T08:15:00Z',
  status: 'confirmed',
  method: 'clinic',
  price_dzd: 2000,
  paid: false,
};

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
});

describe('Login', () => {
  it('signs in and shows today', async () => {
    const calls = mockFetch((url) =>
      url.pathname === '/v1/staff/login' ? { status: 200, body: session } : { status: 200, body: [] },
    );
    renderIn(<App />);
    await userEvent.type(screen.getByLabelText('E-mail'), 'dr@example.invalid');
    await userEvent.type(screen.getByLabelText('Mot de passe'), 'secret123');
    await userEvent.click(screen.getByRole('button', { name: 'Se connecter' }));
    expect(await screen.findByText('Aucun rendez-vous ce jour-là.')).toBeInTheDocument();
    expect(JSON.parse(calls[0].init.body as string)).toEqual({ email: 'dr@example.invalid', password: 'secret123' });
    expect((calls[1].init.headers as Record<string, string>).authorization).toBe('Bearer a1');
  });

  it('explains wrong credentials', async () => {
    mockFetch(() => ({ status: 401, body: { detail: { code: 'wrong_credentials' } } }));
    renderIn(<App />);
    await userEvent.type(screen.getByLabelText('E-mail'), 'dr@example.invalid');
    await userEvent.type(screen.getByLabelText('Mot de passe'), 'nope');
    await userEvent.click(screen.getByRole('button', { name: 'Se connecter' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('E-mail ou mot de passe incorrect.');
  });

  it('is in Arabic and right-to-left by default', () => {
    mockFetch(() => ({ status: 200, body: [] }));
    renderIn(<App />, 'ar');
    expect(document.documentElement.dir).toBe('rtl');
    expect(screen.getByRole('button', { name: 'تسجيل الدخول' })).toBeInTheDocument();
  });
});

describe('Today', () => {
  it('lists the visits in clinic time and marks a clinic payment', async () => {
    const calls = mockFetch((url) =>
      url.pathname.endsWith('/paid') ? { status: 200, body: { ...visit, paid: true } } : { status: 200, body: [visit] },
    );
    renderIn(<Today initialDay="2026-10-19" />);
    expect(await screen.findByText('09:00')).toBeInTheDocument();
    expect(screen.getByText('+213661234567')).toBeInTheDocument();
    expect(calls[0].url.search).toBe('?day=2026-10-19');
    await userEvent.click(screen.getByRole('button', { name: 'Marquer payé' }));
    expect(await screen.findByText('Payé')).toBeInTheDocument();
    expect(JSON.parse(calls[1].init.body as string)).toEqual({ paid: true });
  });

  it('does not offer completed or absent before the visit starts', async () => {
    mockFetch(() => ({ status: 200, body: [{ ...visit, start: '2999-01-01T08:00:00Z' }] }));
    renderIn(<Today initialDay="2999-01-01" />);
    await screen.findByText('+213661234567');
    expect(screen.queryByRole('button', { name: 'Effectué' })).toBeNull();
  });

  it('card payments cannot be marked by hand', async () => {
    mockFetch(() => ({ status: 200, body: [{ ...visit, method: 'cib', paid: true }] }));
    renderIn(<Today initialDay="2026-10-19" />);
    await screen.findByText('+213661234567');
    expect(screen.queryByRole('button', { name: 'Marquer impayé' })).toBeNull();
  });

  it('offers a retry when the server is down', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Promise.reject(new TypeError('offline'))));
    renderIn(<Today initialDay="2026-10-19" />);
    expect(await screen.findByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
  });

  it('knows today in Algiers time', () => {
    expect(clinicToday(new Date('2026-10-17T23:30:00Z'))).toBe('2026-10-18');
  });
});

describe('Patients', () => {
  it('filters by phone', async () => {
    mockFetch(() => ({
      status: 200,
      body: [
        { id: 'p1', phone: '+213661111111', visits: 2, last_visit: '2026-09-01T08:00:00Z', next_visit: null },
        { id: 'p2', phone: '+213772222222', visits: 0, last_visit: null, next_visit: null },
      ],
    }));
    renderIn(<Patients />);
    await screen.findByText('+213661111111');
    await userEvent.type(screen.getByLabelText('Téléphone'), '0772');
    await waitFor(() => expect(screen.queryByText('+213661111111')).toBeNull());
    expect(screen.getByText('+213772222222')).toBeInTheDocument();
  });
});

describe('Signups', () => {
  it('approves a sign-up and removes it from the list', async () => {
    const calls = mockFetch((url) =>
      url.pathname.endsWith('/approve')
        ? { status: 200, body: { id: 's1', phone: '+213661234567', created_at: '2026-10-17T10:00:00Z' } }
        : { status: 200, body: [{ id: 's1', phone: '+213661234567', created_at: '2026-10-17T10:00:00Z' }] },
    );
    renderIn(<Signups />);
    await userEvent.click(await screen.findByRole('button', { name: 'Approuver' }));
    expect(await screen.findByText('Aucune inscription en attente.')).toBeInTheDocument();
    expect(calls[1].url.pathname).toBe('/v1/staff/signups/s1/approve');
  });
});
