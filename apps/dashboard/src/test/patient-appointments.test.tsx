import { render, screen, within } from '@testing-library/react';
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
    expect(await within(region).findByText('Assiduité : 67 % (2 effectués, 1 absences)')).toBeInTheDocument();
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
    expect(await within(region).findByText('الحضور: 67% (2 حضور، 1 غياب)')).toBeInTheDocument();
  });
});
