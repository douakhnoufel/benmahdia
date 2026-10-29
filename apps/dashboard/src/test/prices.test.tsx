import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { App } from '../App';
import { signOut } from '../api';
import { I18nProvider, type Lang } from '../i18n';
import { Prices } from '../pages/Prices';

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

const doctors = [
  { id: 'd1', name_ar: 'د. بن مهدية', name_fr: 'Dr Benmahdia', price_dzd: 2000, slot_minutes: 15 },
  { id: 'd2', name_ar: 'د. آخر', name_fr: 'Dr Autre', price_dzd: 1500, slot_minutes: 10 },
];

async function signIn(role: 'doctor' | 'super_admin') {
  const calls = mockFetch((url) => {
    if (url.pathname === '/v1/staff/login') return { status: 200, body: { access_token: 'a', refresh_token: 'r' } };
    if (url.pathname === '/v1/staff/me') return { status: 200, body: { id: 'd1', role, name_ar: '', name_fr: '' } };
    return { status: 200, body: [] };
  });
  renderIn(<App />);
  await userEvent.type(screen.getByLabelText('E-mail'), 'dr@example.invalid');
  await userEvent.type(screen.getByLabelText('Mot de passe'), 'secret123');
  await userEvent.click(screen.getByRole('button', { name: 'Se connecter' }));
  await screen.findByText('Aucun rendez-vous ce jour-là.');
  return calls;
}

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
});

describe('Prices', () => {
  it('is in the menu for the super admin only', async () => {
    await signIn('super_admin');
    expect(await screen.findByRole('button', { name: 'Tarifs' })).toBeInTheDocument();
  });

  it('is not in the menu for a doctor', async () => {
    const calls = await signIn('doctor');
    await vi.waitFor(() => expect(calls.some((c) => c.url.pathname === '/v1/staff/me')).toBe(true));
    expect(screen.queryByRole('button', { name: 'Tarifs' })).toBeNull();
  });

  it('sets the price of one doctor', async () => {
    const calls = mockFetch((_, init) =>
      init.method === 'PUT' ? { status: 200, body: { ...doctors[1], price_dzd: 1800 } } : { status: 200, body: doctors },
    );
    renderIn(<Prices />);
    const input = await screen.findByLabelText('Prix (DA) · Dr Autre');
    expect(input).toHaveValue(1500);
    const row = input.closest('li')!;
    expect(within(row).getByRole('button', { name: 'Enregistrer' })).toBeDisabled();
    await userEvent.clear(input);
    await userEvent.type(input, '1800');
    await userEvent.click(within(row).getByRole('button', { name: 'Enregistrer' }));
    expect(await within(row).findByRole('status')).toHaveTextContent('Enregistré.');
    const put = calls.find((c) => c.init.method === 'PUT')!;
    expect(put.url.pathname).toBe('/v1/admin/doctors/d2/price');
    expect(JSON.parse(put.init.body as string)).toEqual({ price_dzd: 1800 });
    expect(screen.getByLabelText('Prix (DA) · Dr Benmahdia')).toHaveValue(2000);
  });

  it('refuses a price out of range', async () => {
    mockFetch(() => ({ status: 200, body: doctors }));
    renderIn(<Prices />);
    const input = await screen.findByLabelText('Prix (DA) · Dr Benmahdia');
    await userEvent.clear(input);
    await userEvent.type(input, '200000');
    const row = input.closest('li')!;
    expect(within(row).getByRole('alert')).toHaveTextContent('Le prix doit être entre 0 et 100 000 DA.');
    expect(within(row).getByRole('button', { name: 'Enregistrer' })).toBeDisabled();
  });

  it('says when saving failed', async () => {
    mockFetch((_, init) => (init.method === 'PUT' ? { status: 403, body: { detail: { code: 'forbidden' } } } : { status: 200, body: doctors }));
    renderIn(<Prices />);
    const input = await screen.findByLabelText('Prix (DA) · Dr Benmahdia');
    await userEvent.clear(input);
    await userEvent.type(input, '2100');
    await userEvent.click(within(input.closest('li')!).getByRole('button', { name: 'Enregistrer' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Enregistrement impossible. Réessayez.');
  });

  it('is in Arabic', async () => {
    mockFetch(() => ({ status: 200, body: doctors }));
    renderIn(<Prices />, 'ar');
    expect(await screen.findByLabelText('السعر (دج) · د. آخر')).toHaveValue(1500);
  });
});
