import { fireEvent, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { signOut, type Payments as PaymentsData, type Receipt } from '../api';
import { I18nProvider, type Lang } from '../i18n';
import { PatientAppointments } from '../pages/PatientAppointments';
import { Payments, validRange } from '../pages/Payments';
import { Today, clinicToday } from '../pages/Today';

type Handler = (url: URL, init: RequestInit) => { status: number; body?: unknown } | undefined;

const receipt: Receipt = {
  number: 'BM-1A2B3C4D',
  appointment_id: 'a1',
  doctor_name_ar: 'د. بن مهدية',
  doctor_name_fr: 'Dr Benmahdia',
  start: '2026-10-19T08:00:00Z',
  amount_dzd: 2000,
  method: 'cib',
  paid_at: '2026-10-17T10:00:00Z',
  payment_ref: 'chk_1',
};

const row = {
  id: 'a1',
  start: '2026-10-19T08:00:00Z',
  doctor_name_ar: 'د. بن مهدية',
  doctor_name_fr: 'Dr Benmahdia',
  mine: true,
  patient_phone: '+213661234567',
  status: 'confirmed' as const,
  method: 'cib' as const,
  price_dzd: 2000,
  paid: true,
  paid_at: '2026-10-17T10:00:00Z',
};

const payments: PaymentsData = {
  rows: [row, { ...row, id: 'a2', start: '2026-10-20T08:00:00Z', method: 'clinic', paid: false, paid_at: null }],
  totals: { paid_count: 1, paid_dzd: 2000, unpaid_count: 1, unpaid_dzd: 2000 },
};

function mockFetch(handler: Handler) {
  const calls: URL[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: URL, init: RequestInit) => {
      calls.push(input);
      const own = handler(input, init);
      const reply = own ?? (input.pathname.endsWith('/receipt') ? { status: 200, body: receipt } : { status: 200, body: [] });
      return new Response(JSON.stringify(reply.body), { status: reply.status });
    }),
  );
  return calls;
}

function renderIn(ui: React.ReactNode, lang: Lang = 'fr') {
  return render(<I18nProvider initial={lang}>{ui}</I18nProvider>);
}

const writeText = vi.fn();

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
  writeText.mockReset();
  Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
});

afterEach(() => {
  Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true });
});

describe('payment period', () => {
  it('accepts up to 92 days, oldest first', () => {
    expect(validRange('2026-01-01', '2026-04-02')).toBe(true);
    expect(validRange('2026-01-01', '2026-04-03')).toBe(false);
    expect(validRange('2026-10-02', '2026-10-01')).toBe(false);
    expect(validRange('2026-10-01', '2026-10-01')).toBe(true);
    expect(validRange('', '2026-10-01')).toBe(false);
  });
});

describe('Payments page', () => {
  it('shows this month with the totals', async () => {
    const calls = mockFetch((url) => (url.pathname === '/v1/staff/payments' ? { status: 200, body: payments } : undefined));
    renderIn(<Payments />);
    expect(await screen.findByText('Payé : 2000 DA (1)')).toBeInTheDocument();
    expect(screen.getByText('Impayé : 2000 DA (1)')).toBeInTheDocument();
    const today = clinicToday();
    expect(calls[0].search).toBe(`?from=${today.slice(0, 8)}01&to=${today}`);
    const rows = screen.getAllByRole('row').slice(1);
    expect(rows[0]).toHaveTextContent('Carte CIB');
    expect(rows[0]).toHaveTextContent('Payé');
    expect(rows[1]).toHaveTextContent('À la clinique');
    // Only a paid visit has a receipt.
    expect(within(rows[1]).queryByRole('button', { name: 'Reçu' })).toBeNull();
  });

  it('opens a receipt and copies it as text', async () => {
    const calls = mockFetch((url) => (url.pathname === '/v1/staff/payments' ? { status: 200, body: payments } : undefined));
    renderIn(<Payments />);
    await userEvent.click(await screen.findByRole('button', { name: 'Reçu' }));
    const panel = await screen.findByRole('region', { name: 'Reçu de paiement' });
    expect(await within(panel).findByText('BM-1A2B3C4D')).toBeInTheDocument();
    expect(within(panel).getByText('chk_1')).toBeInTheDocument();
    expect(within(panel).getByText('Reçu de paiement, pas une facture.')).toBeInTheDocument();
    expect(calls.at(-1)!.pathname).toBe('/v1/staff/appointments/a1/receipt');
    await userEvent.click(within(panel).getByRole('button', { name: 'Copier le texte' }));
    expect(await within(panel).findByRole('status')).toHaveTextContent('Copié.');
    const text = writeText.mock.calls[0][0] as string;
    expect(text).toContain('N° de reçu : BM-1A2B3C4D');
    expect(text).toContain('Montant : 2000 DA');
    expect(text).toContain('Référence Chargily : chk_1');
    expect(text).not.toContain('+213');
    await userEvent.click(within(panel).getByRole('button', { name: 'Fermer' }));
    expect(screen.queryByRole('region', { name: 'Reçu de paiement' })).toBeNull();
  });

  it('says when copying failed', async () => {
    writeText.mockRejectedValue(new Error('denied'));
    mockFetch((url) => (url.pathname === '/v1/staff/payments' ? { status: 200, body: payments } : undefined));
    renderIn(<Payments />);
    await userEvent.click(await screen.findByRole('button', { name: 'Reçu' }));
    const panel = await screen.findByRole('region', { name: 'Reçu de paiement' });
    await userEvent.click(await within(panel).findByRole('button', { name: 'Copier le texte' }));
    expect(await within(panel).findByRole('alert')).toHaveTextContent('Copie impossible.');
  });

  it('refuses a period that is too long without asking the server', async () => {
    const calls = mockFetch((url) => (url.pathname === '/v1/staff/payments' ? { status: 200, body: payments } : undefined));
    renderIn(<Payments />);
    await screen.findByText('Payé : 2000 DA (1)');
    fireEvent.change(screen.getByLabelText('Du'), { target: { value: '2026-01-01' } });
    fireEvent.change(screen.getByLabelText('Au'), { target: { value: '2026-06-01' } });
    expect(screen.getByRole('alert')).toHaveTextContent('au plus 92 jours');
    expect(calls.filter((u) => u.pathname === '/v1/staff/payments')).toHaveLength(1);
    fireEvent.change(screen.getByLabelText('Au'), { target: { value: '2026-01-31' } });
    expect(await screen.findByText('Payé : 2000 DA (1)')).toBeInTheDocument();
    expect(calls.at(-1)!.search).toBe('?from=2026-01-01&to=2026-01-31');
  });

  it('says when the period is empty', async () => {
    mockFetch((url) =>
      url.pathname === '/v1/staff/payments'
        ? { status: 200, body: { rows: [], totals: { paid_count: 0, paid_dzd: 0, unpaid_count: 0, unpaid_dzd: 0 } } }
        : undefined,
    );
    renderIn(<Payments />);
    expect(await screen.findByText('Aucun rendez-vous sur cette période.')).toBeInTheDocument();
  });

  it('is in Arabic', async () => {
    mockFetch((url) => (url.pathname === '/v1/staff/payments' ? { status: 200, body: payments } : undefined));
    renderIn(<Payments />, 'ar');
    expect(await screen.findByText('مدفوع: 2000 دج (1)')).toBeInTheDocument();
    expect(screen.getAllByText('بطاقة CIB')).toHaveLength(1);
  });
});

describe('Receipt buttons elsewhere', () => {
  const visit = {
    id: 'a1',
    patient_id: 'p1',
    patient_phone: '+213661234567',
    start: '2026-10-19T08:00:00Z',
    end: '2026-10-19T08:15:00Z',
    status: 'confirmed',
    method: 'cib',
    price_dzd: 2000,
    paid: true,
    doctor_name_ar: 'د',
    doctor_name_fr: 'Dr Benmahdia',
    mine: true,
  };

  it('opens the receipt of a paid visit from Today', async () => {
    mockFetch((url) =>
      url.pathname === '/v1/staff/agenda'
        ? { status: 200, body: [visit, { ...visit, id: 'a2', doctor_name_fr: 'Dr Autre', mine: false }] }
        : undefined,
    );
    renderIn(<Today initialDay="2026-10-19" />);
    await screen.findByText('Dr Autre');
    // One button: another doctor's receipt is not offered.
    await userEvent.click(screen.getByRole('button', { name: 'Reçu' }));
    const panel = await screen.findByRole('region', { name: 'Reçu de paiement' });
    expect(await within(panel).findByText('BM-1A2B3C4D')).toBeInTheDocument();
  });

  it('opens the receipt of a paid visit from the patient file', async () => {
    mockFetch((url) =>
      url.pathname.endsWith('/appointments')
        ? {
            status: 200,
            body: {
              attendance: { completed: 0, no_show: 0, rate: null },
              appointments: [{ ...row, end: '2026-10-19T08:15:00Z', has_note: false }, { ...row, id: 'a3', paid: false }],
            },
          }
        : undefined,
    );
    renderIn(<PatientAppointments patientId="p1" />);
    const buttons = await screen.findAllByRole('button', { name: 'Reçu' });
    expect(buttons).toHaveLength(1);
    await userEvent.click(buttons[0]);
    expect(await screen.findByText('BM-1A2B3C4D')).toBeInTheDocument();
  });
});
