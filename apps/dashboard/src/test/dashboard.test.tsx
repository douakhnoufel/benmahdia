import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { App } from '../App';
import { api, signOut } from '../api';
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

describe('Check-in', () => {
  const arrived = { ...visit, checked_in_at: '2026-10-19T08:02:00Z' };

  it('marks the patient as arrived with the booking code and reminds to check the ID', async () => {
    const calls = mockFetch((url) =>
      url.pathname === '/v1/staff/checkin' ? { status: 200, body: arrived } : { status: 200, body: [visit] },
    );
    renderIn(<Today initialDay="2026-10-19" />);
    await screen.findByText('09:00');
    expect(screen.queryByText('Arrivé')).toBeNull();
    await userEvent.type(screen.getByLabelText('Code de réservation'), 'k7m-4px');
    await userEvent.click(screen.getByRole('button', { name: 'Valider' }));
    expect(await screen.findByRole('status')).toHaveTextContent('Arrivée enregistrée.');
    expect(screen.getByRole('status')).toHaveTextContent('+213661234567');
    expect(screen.getByRole('status')).toHaveTextContent("vérifiez la pièce d'identité");
    expect(screen.getByText('Arrivé')).toBeInTheDocument();
    expect(calls[1].url.pathname).toBe('/v1/staff/checkin');
    expect(JSON.parse(calls[1].init.body as string)).toEqual({ code: 'k7m-4px' });
    expect(screen.getByLabelText('Code de réservation')).toHaveValue('');
  });

  it('shows the arrived badge for a patient who is already in', async () => {
    mockFetch(() => ({ status: 200, body: [arrived] }));
    renderIn(<Today initialDay="2026-10-19" />);
    expect(await screen.findByText('Arrivé')).toBeInTheDocument();
  });

  it.each([
    ['checkin_code_invalid', 404, 'Code inconnu. Vérifiez-le et réessayez.'],
    ['not_today', 409, 'Ce code correspond à un rendez-vous un autre jour.'],
    ['not_checkable', 409, 'Ce rendez-vous ne peut plus être enregistré (annulé ou déjà traité).'],
    ['too_many_attempts', 429, 'Trop de codes erronés. Attendez quelques minutes avant de réessayer.'],
    ['something_new', 500, 'Enregistrement impossible. Réessayez.'],
  ])('explains %s', async (code, status, message) => {
    mockFetch((url) =>
      url.pathname === '/v1/staff/checkin' ? { status, body: { detail: { code } } } : { status: 200, body: [visit] },
    );
    renderIn(<Today initialDay="2026-10-19" />);
    await screen.findByText('09:00');
    await userEvent.type(screen.getByLabelText('Code de réservation'), 'ZZZZZZ');
    await userEvent.click(screen.getByRole('button', { name: 'Valider' }));
    expect(await screen.findByRole('alert')).toHaveTextContent(message);
    expect(screen.queryByText('Arrivé')).toBeNull();
  });

  it('does not send an empty code', async () => {
    const calls = mockFetch(() => ({ status: 200, body: [visit] }));
    renderIn(<Today initialDay="2026-10-19" />);
    await screen.findByText('09:00');
    expect(screen.getByRole('button', { name: 'Valider' })).toBeDisabled();
    expect(calls).toHaveLength(1);
  });

  it('is available in Arabic', async () => {
    mockFetch(() => ({ status: 200, body: [] }));
    renderIn(<Today initialDay="2026-10-19" />, 'ar');
    expect(await screen.findByLabelText('رمز الحجز')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'تأكيد' })).toBeInTheDocument();
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

describe('Signups: reviewing a declared ID', () => {
  const declared = {
    id: 's1',
    phone: '+213661234567',
    created_at: '2026-10-17T10:00:00Z',
    id_status: 'declared',
    duplicate_attempt: false,
  };
  const identity = {
    id_type: 'national_id',
    full_name: 'Karim Benali',
    birth_date: '1990-05-17',
    declared_at: '2026-10-17T10:05:00Z',
    submissions: 1,
    has_selfie: true,
  };

  type Reply = { status: number; body?: unknown };
  function backend(extra?: (url: URL, init: RequestInit) => Reply | undefined) {
    URL.createObjectURL = vi.fn(() => 'blob:selfie');
    URL.revokeObjectURL = vi.fn();
    return mockFetch((url, init) => {
      const custom = extra?.(url, init);
      if (custom) return custom;
      if (url.pathname === '/v1/staff/login') return { status: 200, body: session };
      if (url.pathname.endsWith('/identity')) return { status: 200, body: identity };
      if (url.pathname.endsWith('/selfie')) return { status: 200, body: 'jpeg-bytes' };
      if (url.pathname.endsWith('/approve') || url.pathname.endsWith('/reject'))
        return { status: 200, body: { ...declared, id_status: 'approved' } };
      return { status: 200, body: [declared] };
    });
  }

  it('shows what was declared and the selfie before the doctor can decide', async () => {
    const calls = backend();
    await api.login('d@x.fr', 'pw');
    renderIn(<Signups />);
    expect(await screen.findByText('Identité déclarée')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Approuver' })).toBeNull();
    await userEvent.click(screen.getByRole('button', { name: 'Examiner' }));
    expect(await screen.findByText('Karim Benali')).toBeInTheDocument();
    expect(screen.getByText('1990-05-17')).toBeInTheDocument();
    expect(screen.getByText("Carte d'identité algérienne")).toBeInTheDocument();
    expect(await screen.findByAltText('Photo du patient')).toHaveAttribute('src', 'blob:selfie');
    expect(calls.some((c) => c.url.pathname === '/v1/staff/signups/s1/selfie')).toBe(true);
    expect((calls.find((c) => c.url.pathname.endsWith('/selfie'))!.init.headers as Record<string, string>).authorization).toBe('Bearer a1');
    await userEvent.click(screen.getByRole('button', { name: 'Approuver' }));
    expect(await screen.findByText('Aucune inscription en attente.')).toBeInTheDocument();
    expect(calls.some((c) => c.url.pathname === '/v1/staff/signups/s1/approve')).toBe(true);
  });

  it('rejects with a reason', async () => {
    const calls = backend();
    renderIn(<Signups />);
    await userEvent.click(await screen.findByRole('button', { name: 'Examiner' }));
    await userEvent.type(await screen.findByLabelText('Motif du refus (facultatif)'), 'Photo floue');
    await userEvent.click(screen.getByRole('button', { name: 'Refuser' }));
    expect(await screen.findByText('Aucune inscription en attente.')).toBeInTheDocument();
    const call = calls.find((c) => c.url.pathname.endsWith('/reject'))!;
    expect(JSON.parse(call.init.body as string)).toEqual({ reason: 'Photo floue' });
  });

  it('rejects without a reason by sending no body', async () => {
    const calls = backend();
    renderIn(<Signups />);
    await userEvent.click(await screen.findByRole('button', { name: 'Examiner' }));
    await userEvent.click(await screen.findByRole('button', { name: 'Refuser' }));
    await screen.findByText('Aucune inscription en attente.');
    expect(calls.find((c) => c.url.pathname.endsWith('/reject'))!.init.body).toBeUndefined();
  });

  it('flags an ID already linked to another account and a sign-up with no ID yet', async () => {
    backend((url) =>
      url.pathname === '/v1/staff/signups'
        ? { status: 200, body: [{ ...declared, id_status: 'none', duplicate_attempt: true }] }
        : undefined,
    );
    renderIn(<Signups />);
    expect(await screen.findByText('Identité déjà liée à un autre compte')).toBeInTheDocument();
    expect(screen.getByText("Pas encore d'identité déclarée")).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Approuver' })).toBeInTheDocument();
  });

  it('says so when the patient has no selfie', async () => {
    backend((url) =>
      url.pathname.endsWith('/identity') ? { status: 200, body: { ...identity, has_selfie: false } } : undefined,
    );
    renderIn(<Signups />);
    await userEvent.click(await screen.findByRole('button', { name: 'Examiner' }));
    expect(await screen.findByText('Aucune photo.')).toBeInTheDocument();
  });

  it('says when the patient declared an Algerian passport', async () => {
    backend((url) =>
      url.pathname.endsWith('/identity') ? { status: 200, body: { ...identity, id_type: 'passport' } } : undefined,
    );
    renderIn(<Signups />);
    await userEvent.click(await screen.findByRole('button', { name: 'Examiner' }));
    expect(await screen.findByText('Passeport algérien')).toBeInTheDocument();
  });

  it('is available in Arabic', async () => {
    backend();
    renderIn(<Signups />, 'ar');
    expect(await screen.findByText('هوية مصرّح بها')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'مراجعة' })).toBeInTheDocument();
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
