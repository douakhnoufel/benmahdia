import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signOut } from '../api';
import { I18nProvider, type Lang } from '../i18n';
import { Alerts } from '../pages/Alerts';

const base = {
  patient_id: 'p1',
  patient_phone: '+213661234567',
  priority: 'normal',
  read: false,
  created_at: '2026-10-17T10:00:00Z',
};

function backend() {
  vi.stubGlobal(
    'fetch',
    vi.fn(async () =>
      new Response(
        JSON.stringify([
          { ...base, id: 'b1', type: 'booking_confirmed' },
          { ...base, id: 'b2', type: 'booking_cancelled' },
        ]),
        { status: 200 },
      ),
    ),
  );
}

function renderIn(lang: Lang) {
  return render(
    <I18nProvider initial={lang}>
      <Alerts onOpen={() => undefined} />
    </I18nProvider>,
  );
}

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
});

describe('Booking alerts (PRD 4.4: both sides are notified)', () => {
  it('names a confirmed and a cancelled booking in French', async () => {
    backend();
    renderIn('fr');
    expect(await screen.findByText('Rendez-vous confirmé')).toBeInTheDocument();
    expect(screen.getByText('Rendez-vous annulé')).toBeInTheDocument();
    expect(screen.queryByText('Alerte')).toBeNull();
  });

  it('and in Arabic', async () => {
    backend();
    renderIn('ar');
    expect(await screen.findByText('موعد مؤكَّد')).toBeInTheDocument();
    expect(screen.getByText('موعد ملغى')).toBeInTheDocument();
  });
});
