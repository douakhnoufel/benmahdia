import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signOut, type Visit, type VisitHistory } from '../api';
import { I18nProvider, type Lang } from '../i18n';
import { PatientAppointments } from '../pages/PatientAppointments';

function mockFetch(history: VisitHistory | null) {
  const calls: URL[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: URL) => {
      calls.push(input);
      return history ? new Response(JSON.stringify(history), { status: 200 }) : Promise.reject(new TypeError('offline'));
    }),
  );
  return calls;
}

function renderIn(lang: Lang = 'fr') {
  return render(
    <I18nProvider initial={lang}>
      <PatientAppointments patientId="p1" />
    </I18nProvider>,
  );
}

const visit: Visit = {
  id: 'a1',
  start: '2026-10-20T08:00:00Z',
  end: '2026-10-20T08:15:00Z',
  status: 'confirmed',
  doctor_name_ar: 'د. بن مهدية',
  doctor_name_fr: 'Dr Benmahdia',
  mine: true,
  paid: false,
  method: 'clinic',
  price_dzd: 2000,
  has_note: false,
  note_shared: false,
};

const history: VisitHistory = {
  attendance: { completed: 2, no_show: 1, rate: 2 / 3 },
  appointments: [
    visit,
    { ...visit, id: 'a2', start: '2026-10-01T08:00:00Z', status: 'completed', paid: true, doctor_name_fr: 'Dr Autre', mine: false },
    { ...visit, id: 'a3', start: '2026-09-15T08:00:00Z', status: 'no_show' },
    { ...visit, id: 'a4', start: '2026-09-10T08:00:00Z', status: 'cancelled' },
  ],
};

const card = () => screen.findByRole('region', { name: 'Rendez-vous' });

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
});

describe('Patient file: appointments', () => {
  it('shows the attendance rate and every visit', async () => {
    const calls = mockFetch(history);
    renderIn();
    const region = await card();
    expect(await within(region).findByText('Assiduité : 67 % — effectués : 2, absences : 1')).toBeInTheDocument();
    const rows = within(region).getAllByRole('listitem');
    expect(rows).toHaveLength(4);
    expect(rows[0]).toHaveTextContent('09:00');
    expect(rows[0]).toHaveTextContent('Confirmé');
    expect(rows[0]).toHaveTextContent('Impayé');
    expect(rows[1]).toHaveTextContent('Dr Autre');
    expect(rows[1]).toHaveTextContent('Payé');
    expect(rows[2]).toHaveTextContent('Absent');
    // A cancelled visit has nothing to pay.
    expect(rows[3]).not.toHaveTextContent(/payé/i);
    expect(calls[0].pathname).toBe('/v1/staff/patients/p1/appointments');
  });

  it('says when there is no past visit yet', async () => {
    mockFetch({ attendance: { completed: 0, no_show: 0, rate: null }, appointments: [visit] });
    renderIn();
    expect(await within(await card()).findByText('Pas encore de rendez-vous passé.')).toBeInTheDocument();
  });

  it('says when there is no visit at all', async () => {
    mockFetch({ attendance: { completed: 0, no_show: 0, rate: null }, appointments: [] });
    renderIn();
    expect(await within(await card()).findByText('Aucun rendez-vous.')).toBeInTheDocument();
  });

  it('offers a retry when the server is down', async () => {
    mockFetch(null);
    renderIn();
    expect(await within(await card()).findByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
  });

  it('is in Arabic', async () => {
    mockFetch(history);
    renderIn('ar');
    const region = await screen.findByRole('region', { name: 'المواعيد' });
    expect(await within(region).findByText('الحضور: 67% — حضر: 2، غاب: 1')).toBeInTheDocument();
  });
});

describe('Patient file: notes', () => {
  const past: Visit = { ...visit, id: 'a9', start: '2026-10-12T08:00:00Z', status: 'completed', paid: true };

  function backend(note: { text: string | null; updated_at: string | null; shared?: boolean; mine?: boolean }) {
    const calls: { url: URL; init: RequestInit }[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: URL, init: RequestInit) => {
        calls.push({ url: input, init });
        if (input.pathname.endsWith('/note')) {
          if (init.method === 'PUT') {
            const body = JSON.parse(init.body as string) as { text: string; shared: boolean };
            const text = body.text.trim();
            return new Response(
              JSON.stringify(text ? { text, updated_at: '2026-10-29T10:00:00Z', shared: body.shared, mine: true } : { text: null, updated_at: null, shared: false, mine: true }),
            );
          }
          return new Response(JSON.stringify({ shared: false, mine: true, ...note }));
        }
        const future = { ...visit, start: '2999-01-01T08:00:00Z' };
        const theirs = { ...past, id: 'a8', mine: false, doctor_name_fr: 'Dr Autre' };
        const cancelled = { ...past, id: 'a7', status: 'cancelled' };
        const own = { ...past, has_note: note.text !== null };
        return new Response(JSON.stringify({ attendance: { completed: 1, no_show: 0, rate: 1 }, appointments: [future, own, theirs, cancelled] }));
      }),
    );
    return calls;
  }

  it('is offered only on the doctor’s own visits that took place', async () => {
    backend({ text: null, updated_at: null });
    renderIn();
    const rows = within(await card()).getAllByRole('listitem');
    await within(rows[1]).findByRole('button', { name: 'Ajouter une note' });
    const noteButton = { name: /note/i };
    expect(within(rows[0]).queryByRole('button', noteButton)).toBeNull();
    expect(within(rows[2]).queryByRole('button', noteButton)).toBeNull();
    expect(within(rows[3]).queryByRole('button', noteButton)).toBeNull();
  });

  it('writes a note and says it is private', async () => {
    const calls = backend({ text: null, updated_at: null });
    renderIn();
    const region = await card();
    await userEvent.click(await within(region).findByRole('button', { name: 'Ajouter une note' }));
    expect(await within(region).findByText('Privée : visible par vous seul. Jamais montrée au patient ni à l’assistant IA.')).toBeInTheDocument();
    await userEvent.type(within(region).getByLabelText('Note'), 'Revoir le sommeil');
    await userEvent.click(within(region).getByRole('button', { name: 'Enregistrer' }));
    expect(await within(region).findByRole('status')).toHaveTextContent('Enregistré.');
    const put = calls.find((c) => c.init.method === 'PUT')!;
    expect(put.url.pathname).toBe('/v1/staff/appointments/a9/note');
    expect(JSON.parse(put.init.body as string)).toEqual({ text: 'Revoir le sommeil', shared: false });
    await userEvent.click(within(region).getByRole('button', { name: 'Fermer' }));
    expect(within(region).getByRole('button', { name: 'Voir la note' })).toBeInTheDocument();
  });

  it('opens the saved note and deletes it when emptied', async () => {
    backend({ text: 'Sevrage bien toléré', updated_at: '2026-10-12T10:00:00Z' });
    renderIn();
    const region = await card();
    const row = within(region).getAllByRole('listitem')[1];
    expect(row).toHaveTextContent('Voir la note');
    await userEvent.click(within(row).getByRole('button', { name: 'Voir la note' }));
    const box = await within(region).findByLabelText('Note');
    expect(box).toHaveValue('Sevrage bien toléré');
    expect(within(region).getByText(/Modifiée le 12 octobre 2026/)).toBeInTheDocument();
    await userEvent.clear(box);
    await userEvent.click(within(region).getByRole('button', { name: 'Enregistrer' }));
    await within(region).findByRole('status');
    await userEvent.click(within(region).getByRole('button', { name: 'Fermer' }));
    expect(within(row).getByRole('button', { name: 'Ajouter une note' })).toBeInTheDocument();
  });

  it('shares a note with the clinic’s doctors when the box is ticked', async () => {
    const calls = backend({ text: null, updated_at: null });
    renderIn();
    const region = await card();
    await userEvent.click(await within(region).findByRole('button', { name: 'Ajouter une note' }));
    await userEvent.type(await within(region).findByLabelText('Note'), 'Revoir le sommeil');
    await userEvent.click(within(region).getByRole('checkbox', { name: 'Partager avec les médecins de la clinique' }));
    expect(within(region).getByText(/^Partagée : visible par tous les médecins/)).toBeInTheDocument();
    await userEvent.click(within(region).getByRole('button', { name: 'Enregistrer' }));
    await within(region).findByRole('status');
    const put = calls.find((c) => c.init.method === 'PUT')!;
    expect(JSON.parse(put.init.body as string)).toEqual({ text: 'Revoir le sommeil', shared: true });
  });

  it('shows a colleague’s shared note read only', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: URL) => {
        if (input.pathname.endsWith('/note'))
          return new Response(JSON.stringify({ text: 'Bonne réponse au traitement', updated_at: '2026-10-12T10:00:00Z', shared: true, mine: false }));
        const theirs = { ...past, id: 'a8', mine: false, doctor_name_fr: 'Dr Autre', has_note: true, note_shared: true };
        return new Response(JSON.stringify({ attendance: { completed: 1, no_show: 0, rate: 1 }, appointments: [theirs] }));
      }),
    );
    renderIn();
    const region = await card();
    await userEvent.click(await within(region).findByRole('button', { name: 'Lire la note' }));
    expect(await within(region).findByText('Bonne réponse au traitement')).toBeInTheDocument();
    expect(within(region).getByText('Note partagée par un confrère : lecture seule.')).toBeInTheDocument();
    expect(within(region).queryByRole('button', { name: 'Enregistrer' })).toBeNull();
  });

  it('says when saving failed', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (input: URL, init: RequestInit) => {
        if (init.method === 'PUT') return new Response(JSON.stringify({ detail: { code: 'not_started' } }), { status: 409 });
        if (input.pathname.endsWith('/note')) return new Response(JSON.stringify({ text: null, updated_at: null, shared: false, mine: true }));
        return new Response(JSON.stringify({ attendance: { completed: 1, no_show: 0, rate: 1 }, appointments: [past] }));
      }),
    );
    renderIn();
    const region = await card();
    await userEvent.click(await within(region).findByRole('button', { name: 'Ajouter une note' }));
    await userEvent.type(await within(region).findByLabelText('Note'), 'x');
    await userEvent.click(within(region).getByRole('button', { name: 'Enregistrer' }));
    expect(await within(region).findByRole('alert')).toHaveTextContent('Enregistrement impossible. Réessayez.');
  });
});
