import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signOut, type HoldItem } from '../api';
import { I18nProvider, type Lang } from '../i18n';
import { Today } from '../pages/Today';

function mockFetch(holds: HoldItem[]) {
  const calls: URL[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: URL) => {
      calls.push(input);
      return new Response(JSON.stringify(input.pathname === '/v1/staff/holds' ? holds : []), { status: 200 });
    }),
  );
  return calls;
}

function renderIn(ui: React.ReactNode, lang: Lang = 'fr') {
  return render(<I18nProvider initial={lang}>{ui}</I18nProvider>);
}

const inAnHour = new Date(Date.now() + 60 * 60 * 1000).toISOString();

const hold: HoldItem = {
  id: 'h1',
  patient_id: 'p1',
  patient_phone: '+213661234567',
  start: '2026-10-19T08:00:00Z',
  end: '2026-10-19T08:15:00Z',
  doctor_name_ar: 'د. بن مهدية',
  doctor_name_fr: 'Dr Benmahdia',
  mine: true,
  expires_at: inAnHour,
  paying_by: null,
};

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
});

describe('Today: pending booking requests', () => {
  it('lists the slots waiting for payment of the day', async () => {
    const calls = mockFetch([hold, { ...hold, id: 'h2', patient_phone: '+213770000001', doctor_name_fr: 'Dr Autre', paying_by: 'edahabia' }]);
    renderIn(<Today initialDay="2026-10-19" />);
    const card = await screen.findByRole('region', { name: 'Réservations en attente de paiement' });
    const [first, second] = within(card).getAllByRole('listitem');
    expect(first).toHaveTextContent('09:00');
    expect(first).toHaveTextContent('+213661234567');
    expect(first).toHaveTextContent('En attente de paiement');
    expect(second).toHaveTextContent('Dr Autre');
    expect(second).toHaveTextContent('Paiement Edahabia en cours');
    expect(first).toHaveTextContent(/Libéré à \d{2}:\d{2} si non payé/);
    expect(calls.find((u) => u.pathname === '/v1/staff/holds')!.search).toBe('?day=2026-10-19');
    // Read only: payment confirms a request, not the desk.
    expect(within(card).queryByRole('button')).toBeNull();
  });

  it('hides the card when nothing is waiting', async () => {
    mockFetch([{ ...hold, expires_at: '2020-01-01T00:00:00Z' }]);
    renderIn(<Today initialDay="2026-10-19" />);
    await screen.findByText('Aucun rendez-vous ce jour-là.');
    expect(screen.queryByRole('region', { name: 'Réservations en attente de paiement' })).toBeNull();
  });

  it('asks again for the day shown', async () => {
    const calls = mockFetch([]);
    renderIn(<Today initialDay="2026-10-19" />);
    await screen.findByText('Aucun rendez-vous ce jour-là.');
    await userEvent.click(screen.getByRole('button', { name: 'Jour suivant' }));
    await vi.waitFor(() =>
      expect(calls.filter((u) => u.pathname === '/v1/staff/holds').map((u) => u.search)).toEqual(['?day=2026-10-19', '?day=2026-10-20']),
    );
  });

  it('is in Arabic', async () => {
    mockFetch([hold]);
    renderIn(<Today initialDay="2026-10-19" />, 'ar');
    const card = await screen.findByRole('region', { name: 'حجوزات في انتظار الدفع' });
    expect(within(card).getByText('د. بن مهدية')).toBeInTheDocument();
  });
});

describe('Today: unread alerts', () => {
  it('links to the alerts when some are unread', async () => {
    mockFetch([]);
    const open = vi.fn();
    renderIn(<Today initialDay="2026-10-19" unread={3} onOpenAlerts={open} />);
    expect(await screen.findByText('Alertes non lues : 3')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Voir les alertes' }));
    expect(open).toHaveBeenCalled();
  });

  it('says nothing when all are read', async () => {
    mockFetch([]);
    renderIn(<Today initialDay="2026-10-19" unread={0} onOpenAlerts={() => undefined} />);
    await screen.findByText('Aucun rendez-vous ce jour-là.');
    expect(screen.queryByText(/Alertes non lues/)).toBeNull();
  });
});
