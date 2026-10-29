import { useState, type FormEvent, type ReactNode } from 'react';
import { ApiError, api, type Availability, type BlockedDay, type SlotMinutes, type Window } from '../api';
import { useI18n, type StringKey } from '../i18n';
import { Badge, Button, Card, Input, Notice } from '../components/ui';
import { useLoad } from '../useLoad';
import { Failed, Loading } from './Status';
import { clinicToday } from './Today';
import { fill } from './Tracking';

/** Saturday first, as on Algerian calendars. Monday = 0 ... Sunday = 6. */
export const WEEK = [5, 6, 0, 1, 2, 3, 4];
const SLOT_LENGTHS: SlotMinutes[] = [5, 10, 15];
const GRID = 5;
const MAX_PER_DAY = 6;
const MAX_NOTICE = 168;

/** 540 → "09:00". */
export function toClock(minute: number): string {
  return `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
}

/** "09:00" → 540; anything else → null. "24:00" is the end of the day. */
export function toMinute(clock: string): number | null {
  const m = /^(\d{2}):(\d{2})$/.exec(clock);
  if (!m) return null;
  const minute = Number(m[1]) * 60 + Number(m[2]);
  return Number(m[2]) < 60 && minute <= 1440 ? minute : null;
}

/** The first problem in one day's periods, by the same rules as the server. */
export function problem(windows: Window[]): StringKey | null {
  if (windows.length > MAX_PER_DAY) return 'errTooMany';
  for (const w of windows) {
    if (w.start_minute % GRID || w.end_minute % GRID) return 'errOffGrid';
    if (w.start_minute >= w.end_minute) return 'errEmptyWindow';
  }
  const sorted = [...windows].sort((a, b) => a.start_minute - b.start_minute);
  return sorted.some((w, i) => i > 0 && sorted[i - 1].end_minute > w.start_minute) ? 'errOverlap' : null;
}

/** How many visits fit in one day's periods. */
export function slotCount(windows: Window[], slot: number): number {
  return windows.reduce((n, w) => n + Math.max(0, Math.floor((w.end_minute - w.start_minute) / slot)), 0);
}

const SERVER_ERROR: Record<string, StringKey> = {
  off_grid: 'errOffGrid',
  empty_window: 'errEmptyWindow',
  overlapping_windows: 'errOverlap',
  too_many_windows: 'errTooMany',
  day_in_past: 'errDayInPast',
  day_too_far: 'errDayTooFar',
  already_blocked: 'errAlreadyBlocked',
};

function errorKey(e: unknown): StringKey {
  return (e instanceof ApiError && SERVER_ERROR[e.code]) || 'saveFailed';
}

type Outcome = { kind: 'saved' } | { kind: 'error'; key: StringKey } | null;

function OutcomeLine({ outcome }: { outcome: Outcome }) {
  const { t } = useI18n();
  if (outcome?.kind === 'saved') return <p role="status" className="text-success">{t('saved')}</p>;
  if (outcome?.kind === 'error') return <p role="alert" className="text-danger">{t(outcome.key)}</p>;
  return null;
}

function Section({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section aria-labelledby={id}>
      <Card className="flex flex-col gap-md">
        <h3 id={id} className="text-h3 text-ink-strong">{title}</h3>
        {children}
      </Card>
    </section>
  );
}

/** The doctor's own consultation hours (PRD 4.3, 7). A change never moves or
 * cancels a booked visit: the ones left outside the hours are listed so the
 * clinic can call those patients. */
export function AvailabilityPage() {
  const { load, reload, setLoad } = useLoad(() => api.availability(), []);
  if (load.state === 'loading') return <Loading />;
  if (load.state === 'error') return <Failed onRetry={reload} />;
  const state = load.data;
  const saved = (next: Availability) => setLoad({ state: 'ready', data: next });
  return (
    <div className="flex flex-col gap-lg">
      <Conflicts state={state} />
      <Week initial={state.windows} slot={state.slot_minutes} onSaved={saved} />
      <Settings state={state} onSaved={saved} />
      <BlockedDays days={state.blocked_days} onSaved={saved} />
    </div>
  );
}

function Conflicts({ state }: { state: Availability }) {
  const { t, date, time } = useI18n();
  if (state.conflicts.length === 0) return null;
  return (
    <Section id="conflicts" title={t('conflictsTitle')}>
      <Notice>{t('conflictsNotice')}</Notice>
      <ul className="flex flex-col gap-sm">
        {state.conflicts.map((c) => (
          <li key={c.appointment_id} className="flex flex-wrap items-center gap-sm">
            <span className="text-ink-strong">
              {date(c.start)} · <span dir="ltr">{time(c.start)}</span>
            </span>
            <span className="text-ink-body" dir="ltr">{c.patient_phone ?? '—'}</span>
            <Badge tone="warning">{t(c.reason === 'blocked_day' ? 'conflictBlockedDay' : 'conflictOutsideHours')}</Badge>
          </li>
        ))}
      </ul>
    </Section>
  );
}

type Period = { from: string; to: string };

function draftOf(windows: Window[]): Record<number, Period[]> {
  const days: Record<number, Period[]> = Object.fromEntries(WEEK.map((d) => [d, []]));
  for (const w of [...windows].sort((a, b) => a.start_minute - b.start_minute)) {
    days[w.weekday].push({ from: toClock(w.start_minute), to: toClock(w.end_minute) });
  }
  return days;
}

/** A day's periods as windows; a time that is not filled in counts as empty. */
function windowsOf(weekday: number, periods: Period[]): Window[] {
  return periods.map((p) => ({ weekday, start_minute: toMinute(p.from) ?? 0, end_minute: toMinute(p.to) ?? 0 }));
}

function Week({ initial, slot, onSaved }: { initial: Window[]; slot: number; onSaved: (s: Availability) => void }) {
  const { t, lang } = useI18n();
  const [draft, setDraft] = useState(() => draftOf(initial));
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<Outcome>(null);
  const dayName = (weekday: number) =>
    new Intl.DateTimeFormat(lang === 'ar' ? 'ar-DZ' : 'fr-DZ', { weekday: 'long', timeZone: 'UTC' }).format(
      // 2026-10-19 is a Monday (weekday 0).
      new Date(Date.UTC(2026, 9, 19 + weekday)),
    );
  const problems = Object.fromEntries(WEEK.map((d) => [d, problem(windowsOf(d, draft[d]))]));
  const blocked = WEEK.some((d) => problems[d] !== null);

  function edit(weekday: number, periods: Period[]) {
    setDraft((all) => ({ ...all, [weekday]: periods }));
    setOutcome(null);
  }

  function add(weekday: number) {
    const last = draft[weekday].at(-1);
    const start = last ? Math.min(toMinute(last.to) ?? 0, 23 * 60) : 9 * 60;
    edit(weekday, [...draft[weekday], { from: toClock(start), to: toClock(Math.min(start + 60, 1440)) }]);
  }

  async function save() {
    setBusy(true);
    try {
      const next = await api.saveWindows(WEEK.flatMap((d) => windowsOf(d, draft[d])));
      setDraft(draftOf(next.windows));
      onSaved(next);
      setOutcome({ kind: 'saved' });
    } catch (e) {
      setOutcome({ kind: 'error', key: errorKey(e) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <Section id="week" title={t('weeklyHours')}>
      <Notice>{t('weeklyHoursHint')}</Notice>
      <ul className="flex flex-col">
        {WEEK.map((weekday) => {
          const name = dayName(weekday);
          const periods = draft[weekday];
          const windows = windowsOf(weekday, periods).sort((a, b) => a.start_minute - b.start_minute);
          return (
            <li key={weekday} className="flex flex-col gap-sm border-b border-border py-md last:border-0">
              <div className="flex flex-wrap items-center gap-sm">
                <h4 className="min-w-[7rem] text-body-lg text-ink-strong">{name}</h4>
                {periods.length === 0 ? (
                  <Badge>{t('closedDay')}</Badge>
                ) : (
                  problems[weekday] === null && (
                    <span className="text-caption text-ink-muted">{fill(t('slotsCount'), { n: slotCount(windows, slot) })}</span>
                  )
                )}
                <Button variant="ghost" className="ms-auto" onClick={() => add(weekday)} disabled={periods.length >= MAX_PER_DAY}>
                  {t('addPeriod')}
                </Button>
              </div>
              {periods.map((p, i) => (
                <div key={i} className="flex flex-wrap items-end gap-sm">
                  <TimeField
                    label={t('periodFrom')}
                    name={`${t('periodFrom')} · ${name} ${i + 1}`}
                    value={p.from}
                    onChange={(from) => edit(weekday, periods.map((x, j) => (j === i ? { ...x, from } : x)))}
                  />
                  <TimeField
                    label={t('periodTo')}
                    name={`${t('periodTo')} · ${name} ${i + 1}`}
                    value={p.to}
                    onChange={(to) => edit(weekday, periods.map((x, j) => (j === i ? { ...x, to } : x)))}
                  />
                  <Button
                    variant="danger"
                    aria-label={`${t('removePeriod')} · ${name} ${i + 1}`}
                    onClick={() => edit(weekday, periods.filter((_, j) => j !== i))}
                  >
                    {t('removePeriod')}
                  </Button>
                </div>
              ))}
              {problems[weekday] === null &&
                windows.slice(1).map((w, i) =>
                  windows[i].end_minute < w.start_minute ? (
                    <span key={i} className="text-caption text-ink-muted" dir="ltr">
                      {fill(t('breakFromTo'), { from: toClock(windows[i].end_minute), to: toClock(w.start_minute) })}
                    </span>
                  ) : null,
                )}
              {problems[weekday] !== null && (
                <p role="alert" className="text-caption text-danger">
                  {name} — {t(problems[weekday]!)}
                </p>
              )}
            </li>
          );
        })}
      </ul>
      <OutcomeLine outcome={outcome} />
      <div>
        <Button onClick={save} disabled={busy || blocked}>{t('saveHours')}</Button>
      </div>
    </Section>
  );
}

function TimeField({ label, name, value, onChange }: { label: string; name: string; value: string; onChange: (v: string) => void }) {
  return (
    <label className="flex flex-col gap-xs text-label text-ink-strong">
      {label}
      <input
        type="time"
        step={GRID * 60}
        dir="ltr"
        aria-label={name}
        className="min-h-[44px] rounded-field border border-border bg-surface px-md text-body text-ink-strong focus:border-teal-500 focus:outline-none"
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
    </label>
  );
}

function Settings({ state, onSaved }: { state: Availability; onSaved: (s: Availability) => void }) {
  const { t } = useI18n();
  const [slot, setSlot] = useState<SlotMinutes>(state.slot_minutes);
  const [notice, setNotice] = useState(String(state.notice_hours));
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<Outcome>(null);
  const hours = Number(notice);
  const valid = notice.trim() !== '' && Number.isInteger(hours) && hours >= 0 && hours <= MAX_NOTICE;

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!valid) return;
    setBusy(true);
    try {
      onSaved(await api.saveBookingSettings(slot, hours));
      setOutcome({ kind: 'saved' });
    } catch (err) {
      setOutcome({ kind: 'error', key: errorKey(err) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <Section id="settings" title={t('bookingSettings')}>
      <form onSubmit={submit} className="flex flex-col gap-md">
        <div className="grid gap-md sm:grid-cols-2">
          <label className="flex flex-col gap-xs text-label text-ink-strong">
            {t('slotLength')}
            <select
              className="min-h-[44px] rounded-field border border-border bg-surface px-md text-body text-ink-strong"
              value={slot}
              onChange={(e) => {
                setSlot(Number(e.target.value) as SlotMinutes);
                setOutcome(null);
              }}
            >
              {SLOT_LENGTHS.map((m) => (
                <option key={m} value={m}>
                  {fill(t('minutesCount'), { n: m })}
                </option>
              ))}
            </select>
          </label>
          <Input
            label={t('noticeHours')}
            type="number"
            min={0}
            max={MAX_NOTICE}
            step={1}
            dir="ltr"
            required
            value={notice}
            onChange={(e) => {
              setNotice(e.target.value);
              setOutcome(null);
            }}
          />
        </div>
        {!valid && <p role="alert" className="text-caption text-danger">{t('errNotice')}</p>}
        <OutcomeLine outcome={outcome} />
        <div>
          <Button type="submit" disabled={busy || !valid}>{t('save')}</Button>
        </div>
      </form>
    </Section>
  );
}

function BlockedDays({ days, onSaved }: { days: BlockedDay[]; onSaved: (s: Availability) => void }) {
  const { t, date } = useI18n();
  const today = clinicToday();
  const [day, setDay] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [outcome, setOutcome] = useState<Outcome>(null);

  async function run(key: string, call: () => Promise<Availability>, after?: () => void) {
    setBusy(key);
    setOutcome(null);
    try {
      onSaved(await call());
      after?.();
      setOutcome({ kind: 'saved' });
    } catch (e) {
      setOutcome({ kind: 'error', key: errorKey(e) });
    } finally {
      setBusy(null);
    }
  }

  function submit(e: FormEvent) {
    e.preventDefault();
    run('new', () => api.blockDay(day, reason.trim() || null), () => {
      setDay('');
      setReason('');
    });
  }

  return (
    <Section id="blocked" title={t('blockedDays')}>
      <Notice>{t('blockedDaysHint')}</Notice>
      {days.length === 0 && <p className="text-ink-muted">{t('noBlockedDays')}</p>}
      {days.length > 0 && (
        <ul className="flex flex-col">
          {days.map((b) => (
            <li key={b.id} className="flex flex-wrap items-center gap-md border-b border-border py-sm last:border-0">
              <span className="text-ink-strong">{date(`${b.day}T12:00:00Z`)}</span>
              {b.reason && <span className="text-ink-body">{b.reason}</span>}
              <Button variant="secondary" className="ms-auto" disabled={busy === b.id} onClick={() => run(b.id, () => api.unblockDay(b.id))}>
                {t('unblockDay')}
              </Button>
            </li>
          ))}
        </ul>
      )}
      <form onSubmit={submit} className="flex flex-col gap-md border-t border-border pt-md">
        <div className="grid gap-md sm:grid-cols-2">
          <Input label={t('blockedDay')} type="date" required min={today} dir="ltr" value={day} onChange={(e) => setDay(e.target.value)} />
          <Input label={t('blockReason')} maxLength={120} value={reason} onChange={(e) => setReason(e.target.value)} />
        </div>
        <OutcomeLine outcome={outcome} />
        <div>
          <Button type="submit" disabled={busy === 'new' || day === ''}>{t('blockDay')}</Button>
        </div>
      </form>
    </Section>
  );
}
