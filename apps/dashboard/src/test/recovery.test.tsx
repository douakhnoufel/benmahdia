import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { App } from '../App';
import { api, signOut } from '../api';
import { I18nProvider, type Lang } from '../i18n';
import { Alerts } from '../pages/Alerts';
import { PatientDetail, parseTimes } from '../pages/PatientDetail';

type Reply = { status: number; body?: unknown } | undefined;

function backend(handler: (url: URL, init: RequestInit) => Reply = () => undefined) {
  const calls: { url: URL; init: RequestInit }[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: URL, init: RequestInit) => {
      calls.push({ url: input, init });
      const own = handler(input, init);
      const { status, body } = own ?? defaults(input, init);
      // A 204 has no body at all, as on the wire.
      return new Response(status === 204 ? null : body === undefined ? '' : JSON.stringify(body), { status });
    }),
  );
  return calls;
}

const addiction = {
  id: 'ad1',
  type: 'cannabis',
  substance: 'haschich',
  clean_since: '2026-10-15T09:30:00Z',
  longest_past_days: 8,
  past_days: 8,
  review_status: 'pending',
  relapses: [{ at: '2026-10-15T09:30:00Z', note: 'soirée' }],
};
const medication = {
  id: 'm1',
  name: 'Sertraline',
  amount: '50 mg',
  times: ['08:00', '20:00'],
  start_date: '2026-10-10',
  end_date: null,
  instructions: 'Après le repas',
};
const alert = {
  id: 'al1',
  patient_id: 'p1',
  patient_phone: '+213661234567',
  type: 'relapse',
  priority: 'high',
  read: false,
  created_at: '2026-10-17T10:00:00Z',
};

function defaults(url: URL, init: RequestInit): { status: number; body?: unknown } {
  const p = url.pathname;
  const method = init.method ?? 'GET';
  if (p.endsWith('/addictions') && method === 'GET') return { status: 200, body: [addiction] };
  if (p.endsWith('/confirm')) return { status: 200, body: { ...addiction, review_status: 'confirmed' } };
  if (p.endsWith('/reject')) return { status: 200, body: { ...addiction, review_status: 'rejected' } };
  if (p.endsWith('/medications') && method === 'GET') return { status: 200, body: [medication] };
  if (p.endsWith('/medications') && method === 'POST') return { status: 201, body: { ...medication, id: 'm2', name: 'Autre' } };
  if (p.includes('/medications/') && method === 'DELETE') return { status: 204 };
  if (p === '/v1/staff/alerts') {
    const all = [alert, { ...alert, id: 'al2', type: 'missed_doses', read: true }];
    return { status: 200, body: url.searchParams.get('unread') === 'true' ? all.filter((a) => !a.read) : all };
  }
  if (p.endsWith('/read')) return { status: 200, body: { ...alert, read: true } };
  return { status: 200, body: [] };
}

function renderIn(ui: React.ReactNode, lang: Lang = 'fr') {
  return render(<I18nProvider initial={lang}>{ui}</I18nProvider>);
}

const patient = { id: 'p1', phone: '+213661234567' };

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
});

describe('PatientDetail: addictions', () => {
  it('shows what the patient entered with the relapses', async () => {
    const calls = backend();
    await api.login('d@x.fr', 'pw').catch(() => undefined);
    renderIn(<PatientDetail patient={patient} onBack={() => undefined} />);
    expect(await screen.findByText('Cannabis')).toBeInTheDocument();
    expect(screen.getByText('À vérifier')).toBeInTheDocument();
    expect(screen.getByText('haschich')).toBeInTheDocument();
    expect(screen.getByText(/soirée/)).toBeInTheDocument();
    expect(calls.some((c) => c.url.pathname === '/v1/staff/patients/p1/addictions')).toBe(true);
  });

  it('confirms an addiction', async () => {
    const calls = backend();
    renderIn(<PatientDetail patient={patient} onBack={() => undefined} />);
    await userEvent.click(await screen.findByRole('button', { name: 'Confirmer' }));
    expect(await screen.findByText('Confirmée')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Confirmer' })).toBeNull();
    expect(calls.some((c) => c.url.pathname === '/v1/staff/patients/p1/addictions/ad1/confirm' && c.init.method === 'POST')).toBe(true);
  });

  it('rejects an addiction', async () => {
    backend();
    renderIn(<PatientDetail patient={patient} onBack={() => undefined} />);
    const card = (await screen.findByText('Cannabis')).closest('article')!;
    await userEvent.click(within(card).getByRole('button', { name: 'Refuser' }));
    expect(await screen.findByText('Refusée')).toBeInTheDocument();
  });

  it('says so when there is nothing yet', async () => {
    backend((url) => (url.pathname.endsWith('/addictions') ? { status: 200, body: [] } : undefined));
    renderIn(<PatientDetail patient={patient} onBack={() => undefined} />);
    expect(await screen.findByText("Le patient n'a saisi aucune addiction.")).toBeInTheDocument();
  });

  it('goes back', async () => {
    backend();
    const back = vi.fn();
    renderIn(<PatientDetail patient={patient} onBack={back} />);
    await userEvent.click(screen.getByRole('button', { name: 'Retour' }));
    expect(back).toHaveBeenCalled();
  });
});

describe('PatientDetail: medications', () => {
  it('lists the prescribed medicines', async () => {
    backend();
    renderIn(<PatientDetail patient={patient} onBack={() => undefined} />);
    expect(await screen.findByText(/Sertraline/)).toBeInTheDocument();
    expect(screen.getByText('08:00 · 20:00')).toBeInTheDocument();
    expect(screen.getByText(/Après le repas/)).toBeInTheDocument();
  });

  it('prescribes with the times parsed into a list', async () => {
    const calls = backend();
    renderIn(<PatientDetail patient={patient} onBack={() => undefined} />);
    await userEvent.type(await screen.findByLabelText('Médicament'), 'Autre');
    await userEvent.type(screen.getByLabelText('Dose (ex. 50 mg)'), '10 mg');
    await userEvent.type(screen.getByLabelText('Heures (ex. 08:00, 20:00)'), '20:00, 08:00');
    await userEvent.click(screen.getByRole('button', { name: 'Prescrire' }));
    await waitFor(() => expect(screen.getAllByText(/Autre/).length).toBeGreaterThan(0));
    const post = calls.find((c) => c.init.method === 'POST' && c.url.pathname.endsWith('/medications'))!;
    const body = JSON.parse(post.init.body as string);
    expect(body).toMatchObject({ name: 'Autre', amount: '10 mg', times: ['20:00', '08:00'], end_date: null, instructions: null });
    expect(body.start_date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('tells the doctor when the prescription is refused', async () => {
    backend((url, init) =>
      init.method === 'POST' && url.pathname.endsWith('/medications')
        ? { status: 422, body: { detail: { code: 'validation' } } }
        : undefined,
    );
    renderIn(<PatientDetail patient={patient} onBack={() => undefined} />);
    await userEvent.type(await screen.findByLabelText('Médicament'), 'X');
    await userEvent.type(screen.getByLabelText('Dose (ex. 50 mg)'), '1');
    await userEvent.type(screen.getByLabelText('Heures (ex. 08:00, 20:00)'), '8h');
    await userEvent.click(screen.getByRole('button', { name: 'Prescrire' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Prescription impossible.');
  });

  it('stops a medicine', async () => {
    const calls = backend();
    renderIn(<PatientDetail patient={patient} onBack={() => undefined} />);
    await userEvent.click(await screen.findByRole('button', { name: 'Arrêter' }));
    await waitFor(() => expect(screen.getByText('Aucun médicament prescrit.')).toBeInTheDocument());
    expect(calls.some((c) => c.init.method === 'DELETE' && c.url.pathname.endsWith('/medications/m1'))).toBe(true);
  });

  it('parses times separated by commas or spaces', () => {
    expect(parseTimes('08:00, 20:00')).toEqual(['08:00', '20:00']);
    expect(parseTimes(' 08:00  20:00;')).toEqual(['08:00', '20:00']);
    expect(parseTimes('')).toEqual([]);
  });

  it('is available in Arabic', async () => {
    backend();
    renderIn(<PatientDetail patient={patient} onBack={() => undefined} />, 'ar');
    expect(await screen.findByText('قنب')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'رجوع' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'وصف الدواء' })).toBeInTheDocument();
  });
});

describe('Alerts', () => {
  it('lists unread alerts with no medical content and marks one read', async () => {
    const calls = backend();
    const changed = vi.fn();
    renderIn(<Alerts onOpen={() => undefined} onChange={changed} />);
    expect(await screen.findByText('Rechute signalée')).toBeInTheDocument();
    expect(screen.getByText('Prioritaire')).toBeInTheDocument();
    expect(screen.queryByText('Prises manquées depuis 2 jours')).toBeNull(); // read: hidden by default
    await userEvent.click(screen.getByRole('button', { name: 'Marquer lu' }));
    await waitFor(() => expect(screen.getByText('Aucune alerte.')).toBeInTheDocument());
    expect(calls.some((c) => c.url.pathname === '/v1/staff/alerts/al1/read' && c.init.method === 'POST')).toBe(true);
    expect(changed).toHaveBeenCalled();
  });

  it('can show the read ones too', async () => {
    backend();
    renderIn(<Alerts onOpen={() => undefined} />);
    await screen.findByText('Rechute signalée');
    await userEvent.click(screen.getByLabelText('Non lues seulement'));
    expect(await screen.findByText('Prises manquées depuis 2 jours')).toBeInTheDocument();
  });

  it('opens the patient behind an alert', async () => {
    backend();
    const open = vi.fn();
    renderIn(<Alerts onOpen={open} />);
    await userEvent.click(await screen.findByRole('button', { name: 'Ouvrir la fiche' }));
    expect(open).toHaveBeenCalledWith({ id: 'p1', phone: '+213661234567' });
  });
});

describe('App', () => {
  const session = { access_token: 'a1', refresh_token: 'r1', user: { role: 'doctor' } };

  it('shows the unread count on the alerts tab and opens the patient from an alert', async () => {
    backend((url) => (url.pathname === '/v1/staff/login' ? { status: 200, body: session } : undefined));
    await api.login('d@x.fr', 'pw');
    renderIn(<App />);
    const tab = await screen.findByRole('button', { name: /Alertes/ });
    await waitFor(() => expect(tab).toHaveTextContent('Alertes1'));
    await userEvent.click(tab);
    await userEvent.click(await screen.findByRole('button', { name: 'Ouvrir la fiche' }));
    expect(await screen.findByText('Cannabis')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: '+213661234567' })).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Retour' }));
    expect(await screen.findByText('Pas encore de patients.')).toBeInTheDocument();
  });
});
