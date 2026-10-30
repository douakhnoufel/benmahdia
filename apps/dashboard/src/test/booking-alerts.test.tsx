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
          { ...base, id: 'm1', type: 'milestone' },
          { ...base, id: 'd1', type: 'account_deleted' },
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
    expect(screen.getByText('Nouvelle étape sans consommation')).toBeInTheDocument();
    expect(screen.getByText('Le patient a supprimé son compte')).toBeInTheDocument();
    expect(screen.queryByText('Alerte')).toBeNull();
    // The deleted patient's alert has no link to a file that no longer exists.
    expect(screen.getAllByText('Ouvrir la fiche')).toHaveLength(3);
  });

  it('and in Arabic', async () => {
    backend();
    renderIn('ar');
    expect(await screen.findByText('موعد مؤكَّد')).toBeInTheDocument();
    expect(screen.getByText('موعد ملغى')).toBeInTheDocument();
    expect(screen.getByText('بلغ مرحلة جديدة دون تعاطٍ')).toBeInTheDocument();
    expect(screen.getByText('حذف المريض حسابه')).toBeInTheDocument();
  });
});
