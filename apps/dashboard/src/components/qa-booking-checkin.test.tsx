// QA booking run 2026-10-25 (ux-clients): the front-desk check-in box on the
// Today page (PRD 4.3 "Booking code and check-in", 7, 8.6). Sample data only.
// A test that shows a real bug uses test.fails (see qa/booking/2026-10-25/ux-clients.md).
import { act, fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signOut, type AgendaItem } from '../api';
import { I18nProvider, type Lang } from '../i18n';
import { CheckinBox } from './CheckinBox';

type Reply = { status: number; body?: unknown };

function mockFetch(reply: (body: { code: string }) => Reply | Promise<Reply>) {
  const sent: { path: string; body: { code: string } }[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: URL, init: RequestInit) => {
      const body = JSON.parse(init.body as string) as { code: string };
      sent.push({ path: input.pathname, body });
      const { status, body: out } = await reply(body);
      return new Response(out === undefined ? '' : JSON.stringify(out), { status });
    }),
  );
  return sent;
}

const visit: AgendaItem = {
  id: 'v1',
  patient_id: 'p1',
  patient_phone: '+213661234501',
  start: '2026-10-19T08:00:00Z',
  end: '2026-10-19T08:15:00Z',
  status: 'confirmed',
  method: 'clinic',
  price_dzd: 2000,
  doctor_name_ar: 'د. بن مهدية',
  doctor_name_fr: 'Dr Benmahdia',
  mine: true,
  paid: false,
  checked_in_at: '2026-10-19T07:55:00Z',
};

const text = {
  fr: {
    label: 'Code de réservation',
    submit: 'Valider',
    done: 'Arrivée enregistrée.',
    reminder: "Rappel : vérifiez la pièce d'identité originale du patient.",
    invalid: 'Code inconnu. Vérifiez-le et réessayez.',
    notToday: 'Ce code correspond à un rendez-vous un autre jour.',
    notCheckable: 'Ce rendez-vous ne peut plus être enregistré (annulé ou déjà traité).',
    tooMany: 'Trop de codes erronés. Attendez quelques minutes avant de réessayer.',
    offline: 'Impossible de joindre le serveur. Réessayez.',
    failed: 'Enregistrement impossible. Réessayez.',
  },
  ar: {
    label: 'رمز الحجز',
    submit: 'تأكيد',
    done: 'تم تسجيل وصول المريض.',
    reminder: 'تذكير: تحقق من بطاقة هوية المريض الأصلية.',
    invalid: 'رمز غير معروف. تحقق منه وأعد المحاولة.',
    notToday: 'هذا الرمز لموعد في يوم آخر.',
    notCheckable: 'لا يمكن تسجيل هذا الموعد (ملغى أو تمت معالجته).',
    tooMany: 'رموز خاطئة كثيرة. انتظر بضع دقائق ثم أعد المحاولة.',
    offline: 'تعذر الاتصال بالخادم. حاول مجددا.',
    failed: 'تعذر التسجيل. حاول مجددا.',
  },
} as const;

function renderBox(lang: Lang = 'fr') {
  const onCheckedIn = vi.fn();
  render(
    <I18nProvider initial={lang}>
      <CheckinBox onCheckedIn={onCheckedIn} />
    </I18nProvider>,
  );
  return onCheckedIn;
}

async function submit(lang: Lang, code: string) {
  await userEvent.type(screen.getByLabelText(text[lang].label), code);
  await userEvent.click(screen.getByRole('button', { name: text[lang].submit }));
}

beforeEach(() => {
  signOut();
  vi.unstubAllGlobals();
});

describe('QA check-in box: success', () => {
  it.each(['fr', 'ar'] as const)('marks the patient arrived and reminds to check the original ID (%s)', async (lang) => {
    const sent = mockFetch(() => ({ status: 200, body: visit }));
    const onCheckedIn = renderBox(lang);
    await submit(lang, 'K7M4PX');
    const status = await screen.findByRole('status');
    expect(status).toHaveTextContent(text[lang].done);
    expect(status).toHaveTextContent(text[lang].reminder);
    expect(status).toHaveTextContent('+213661234501');
    expect(onCheckedIn).toHaveBeenCalledWith(visit);
    expect(sent).toEqual([{ path: '/v1/staff/checkin', body: { code: 'K7M4PX' } }]);
    expect(screen.getByLabelText(text[lang].label)).toHaveValue('');
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('is right-to-left in Arabic, left-to-right in French; the code and phone stay LTR', async () => {
    mockFetch(() => ({ status: 200, body: visit }));
    renderBox('ar');
    expect(document.documentElement.dir).toBe('rtl');
    expect(document.documentElement.lang).toBe('ar');
    expect(screen.getByLabelText(text.ar.label)).toHaveAttribute('dir', 'ltr');
    await submit('ar', 'K7M4PX');
    const phone = (await screen.findByRole('status')).querySelector('[dir="ltr"]');
    expect(phone).toHaveTextContent('+213661234501');
  });

  it('shows the visit time in clinic time (08:00Z = 09:00 in Algiers)', async () => {
    mockFetch(() => ({ status: 200, body: visit }));
    renderBox('fr');
    await submit('fr', 'K7M4PX');
    expect(await screen.findByRole('status')).toHaveTextContent('09:00');
  });

  it('a repeated check-in (already arrived) is still a success, not an error', async () => {
    mockFetch(() => ({ status: 200, body: visit }));
    renderBox('fr');
    await submit('fr', 'K7M4PX');
    await screen.findByRole('status');
    await submit('fr', 'K7M4PX');
    expect(await screen.findByRole('status')).toHaveTextContent(text.fr.done);
    expect(screen.queryByRole('alert')).toBeNull();
  });
});

describe('QA check-in box: code input', () => {
  it('a blank or spaces-only code cannot be sent', async () => {
    const sent = mockFetch(() => ({ status: 200, body: visit }));
    renderBox('fr');
    const button = screen.getByRole('button', { name: text.fr.submit });
    expect(button).toBeDisabled();
    await userEvent.type(screen.getByLabelText(text.fr.label), '   ');
    expect(button).toBeDisabled();
    fireEvent.submit(button.closest('form')!);
    expect(sent).toHaveLength(0);
  });

  it('a loosely typed code is sent as typed; the server normalises it', async () => {
    const sent = mockFetch(() => ({ status: 200, body: visit }));
    renderBox('fr');
    await submit('fr', 'k7m-4px');
    await screen.findByRole('status');
    expect(sent[0].body).toEqual({ code: 'k7m-4px' });
  });

  it('the input is capped (no unbounded paste)', async () => {
    mockFetch(() => ({ status: 200, body: visit }));
    renderBox('fr');
    const input = screen.getByLabelText(text.fr.label);
    await userEvent.type(input, 'A'.repeat(50));
    expect((input as HTMLInputElement).value.length).toBeLessThanOrEqual(32);
  });

  it('pressing Enter twice while the first request runs sends one request', async () => {
    let release: (r: Reply) => void = () => {};
    const sent = mockFetch(() => new Promise<Reply>((resolve) => (release = resolve)));
    renderBox('fr');
    await userEvent.type(screen.getByLabelText(text.fr.label), 'K7M4PX');
    const form = screen.getByRole('button', { name: text.fr.submit }).closest('form')!;
    fireEvent.submit(form);
    fireEvent.submit(form);
    expect(screen.getByRole('button', { name: text.fr.submit })).toBeDisabled();
    await act(async () => release({ status: 200, body: visit }));
    expect(await screen.findByRole('status')).toHaveTextContent(text.fr.done);
    expect(sent).toHaveLength(1);
  });
});

describe('QA check-in box: refusals (fr + ar)', () => {
  const cases = [
    ['checkin_code_invalid', 404, 'invalid'],
    ['not_today', 409, 'notToday'],
    ['not_checkable', 409, 'notCheckable'],
    ['too_many_attempts', 429, 'tooMany'],
    ['something_new', 500, 'failed'],
    ['unknown', 400, 'failed'],
  ] as const;

  for (const lang of ['fr', 'ar'] as const) {
    it.each(cases)(`%s (%i) → human message · ${lang}`, async (code, status, key) => {
      mockFetch(() => ({ status, body: { detail: { code } } }));
      const onCheckedIn = renderBox(lang);
      await submit(lang, 'ZZZZZZ');
      const alert = await screen.findByRole('alert');
      expect(alert).toHaveTextContent(text[lang][key]);
      expect(alert.textContent).not.toContain(code);
      expect(alert.textContent).not.toMatch(/\b[a-z]+_[a-z_]+\b/);
      expect(screen.queryByRole('status')).toBeNull();
      expect(onCheckedIn).not.toHaveBeenCalled();
    });

    it(`server unreachable → offline message · ${lang}`, async () => {
      vi.stubGlobal('fetch', vi.fn(async () => Promise.reject(new TypeError('Failed to fetch'))));
      renderBox(lang);
      await submit(lang, 'K7M4PX');
      expect(await screen.findByRole('alert')).toHaveTextContent(text[lang].offline);
    });

    it(`a 422 body (list detail) is not shown raw · ${lang}`, async () => {
      mockFetch(() => ({ status: 422, body: { detail: [{ type: 'string_too_long', msg: 'String too long' }] } }));
      renderBox(lang);
      await submit(lang, 'K7M4PX');
      const alert = await screen.findByRole('alert');
      expect(alert).toHaveTextContent(text[lang].failed);
      expect(alert.textContent).not.toContain('String too long');
    });
  }

  it('after the lockout message the desk can still try once the wait is over', async () => {
    let locked = true;
    mockFetch(() => (locked ? { status: 429, body: { detail: { code: 'too_many_attempts', retry_after: 120 } } } : { status: 200, body: visit }));
    renderBox('ar');
    await submit('ar', 'ZZZZZZ');
    expect(await screen.findByRole('alert')).toHaveTextContent(text.ar.tooMany);
    locked = false;
    await userEvent.clear(screen.getByLabelText(text.ar.label));
    await submit('ar', 'K7M4PX');
    expect(await screen.findByRole('status')).toHaveTextContent(text.ar.done);
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('a wrong code after a success replaces the success (no stale "arrived")', async () => {
    let ok = true;
    mockFetch(() => (ok ? { status: 200, body: visit } : { status: 404, body: { detail: { code: 'checkin_code_invalid' } } }));
    renderBox('fr');
    await submit('fr', 'K7M4PX');
    await screen.findByRole('status');
    ok = false;
    await submit('fr', 'ZZZZZZ');
    expect(await screen.findByRole('alert')).toHaveTextContent(text.fr.invalid);
    expect(screen.queryByRole('status')).toBeNull();
  });
});
