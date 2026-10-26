import { api, type AddictionCheck, type HabitKind, type ProfileSpec, type SubstanceProfile } from '../api';
import { useI18n, type StringKey } from '../i18n';
import { Card } from '../components/ui';
import { useLoad } from '../useLoad';
import { Failed, Loading } from './Status';
import { clinicToday } from './Today';

// Per-substance tracking in the patient file (PRD 5.6, 7): the last 30 days
// of daily checks as small multiples (craving and the profile's two
// signals, one row each, 1-5 where higher = harder) and the good habits.
// Everything here is what the patient declared, never a diagnosis.

export const PROFILE_KEY: Record<SubstanceProfile, StringKey> = {
  nicotine: 'profileNicotine',
  thc: 'profileThc',
  pregabalin: 'profilePregabalin',
  buprenorphine: 'profileBuprenorphine',
  cocaine: 'profileCocaine',
  amphetamines: 'profileAmphetamines',
};

const HABIT_KEY: Record<Exclude<HabitKind, 'custom'>, StringKey> = {
  sport: 'habitSport',
  brush_teeth: 'habitBrushTeeth',
  water: 'habitWater',
  reading: 'habitReading',
  call_family: 'habitCallFamily',
  sleep: 'habitSleep',
};

/** Fills "{n}"-style slots in a translated string. */
export function fill(text: string, values: Record<string, string | number>): string {
  return Object.entries(values).reduce((out, [k, v]) => out.replaceAll(`{${k}}`, String(v)), text);
}

/** The [count] calendar days ending [today] ("2026-10-17"), oldest first. */
export function lastDays(today: string, count: number): string[] {
  const end = new Date(`${today}T12:00:00Z`);
  return Array.from({ length: count }, (_, i) => {
    const d = new Date(end);
    d.setUTCDate(end.getUTCDate() - (count - 1 - i));
    return d.toISOString().slice(0, 10);
  });
}

type Row = { key: string; label: string; value: (c: AddictionCheck) => number | undefined };

export function CheckChart({
  patientId,
  addictionId,
  spec,
}: {
  patientId: string;
  addictionId: string;
  spec: ProfileSpec | undefined;
}) {
  const { t, lang, date } = useI18n();
  const { load, reload } = useLoad(() => api.addictionChecks(patientId, addictionId), [patientId, addictionId]);

  if (load.state === 'loading') return <Loading />;
  if (load.state === 'error') return <Failed onRetry={reload} />;

  const { days, checked_days: checked, checks } = load.data;
  const byDay = new Map(checks.map((c) => [c.day, c]));
  const calendar = lastDays(clinicToday(), days);
  const rows: Row[] = [
    { key: 'craving', label: t('craving'), value: (c) => c.craving },
    ...(spec?.signals ?? []).map((s) => ({ key: s.key, label: s.label[lang], value: (c: AddictionCheck) => c.signals[s.key] })),
  ];
  const dayLabel = (day: string) => date(`${day}T12:00:00Z`);

  return (
    <div className="flex flex-col gap-sm">
      <div className="flex flex-wrap items-baseline justify-between gap-sm">
        <h4 className="text-label text-ink-strong">{fill(t('checksTitle'), { d: days })}</h4>
        <span className="text-caption text-ink-muted">{fill(t('checkedDays'), { n: checked, d: days })}</span>
      </div>
      {checks.length === 0 ? (
        <p className="text-ink-muted">{t('noChecks')}</p>
      ) : (
        <>
          <p className="text-caption text-ink-muted">{t('chartNotice')}</p>
          {/* Days run left to right in both languages, like a timeline. */}
          <div dir="ltr" className="flex flex-col gap-sm">
            <UsedRow calendar={calendar} byDay={byDay} label={t('usedDay')} dayLabel={dayLabel} />
            {rows.map((row) => (
              <BarRow
                key={row.key}
                row={row}
                calendar={calendar}
                byDay={byDay}
                dayLabel={dayLabel}
                rating={(v) => fill(t('ratingOf'), { v })}
                empty={t('notChecked')}
              />
            ))}
          </div>
          <details className="text-caption text-ink-body">
            <summary className="cursor-pointer text-teal-700">{t('showTable')}</summary>
            <table className="mt-sm w-full text-start">
              <thead>
                <tr className="text-ink-muted">
                  <th className="py-xs text-start font-medium">{t('day')}</th>
                  <th className="py-xs text-start font-medium">{t('usedDay')}</th>
                  {rows.map((r) => (
                    <th key={r.key} className="py-xs text-start font-medium">
                      {r.label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {checks.map((c) => (
                  <tr key={c.day} className="border-t border-border">
                    <td className="py-xs">{dayLabel(c.day)}</td>
                    <td className="py-xs">{c.used ? '●' : '—'}</td>
                    {rows.map((r) => (
                      <td key={r.key} className="py-xs">
                        {r.value(c) ?? '—'}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </details>
        </>
      )}
    </div>
  );
}

const GRID = 'grid grid-cols-[minmax(7rem,9rem)_1fr] items-end gap-sm';
const DAYS = 'grid h-full items-end gap-[2px]';

function UsedRow({
  calendar,
  byDay,
  label,
  dayLabel,
}: {
  calendar: string[];
  byDay: Map<string, AddictionCheck>;
  label: string;
  dayLabel: (day: string) => string;
}) {
  if (!calendar.some((d) => byDay.get(d)?.used)) return null;
  return (
    <div className={GRID}>
      <span className="text-caption text-ink-body">{label}</span>
      <div className={DAYS} style={{ gridTemplateColumns: `repeat(${calendar.length}, minmax(0, 1fr))` }}>
        {calendar.map((day) =>
          byDay.get(day)?.used ? (
            <span
              key={day}
              title={`${dayLabel(day)} — ${label}`}
              aria-label={`${dayLabel(day)} — ${label}`}
              className="mx-auto h-sm w-sm rounded-pill bg-danger"
            />
          ) : (
            <span key={day} />
          ),
        )}
      </div>
    </div>
  );
}

function BarRow({
  row,
  calendar,
  byDay,
  dayLabel,
  rating,
  empty,
}: {
  row: Row;
  calendar: string[];
  byDay: Map<string, AddictionCheck>;
  dayLabel: (day: string) => string;
  rating: (v: number) => string;
  empty: string;
}) {
  return (
    <div className={GRID} role="group" aria-label={row.label}>
      <span className="text-caption text-ink-body">{row.label}</span>
      <div
        className={`${DAYS} h-[48px] border-b border-border`}
        style={{ gridTemplateColumns: `repeat(${calendar.length}, minmax(0, 1fr))` }}
      >
        {calendar.map((day) => {
          const check = byDay.get(day);
          const value = check ? row.value(check) : undefined;
          const tip = `${dayLabel(day)} — ${value === undefined ? empty : rating(value)}`;
          return (
            // The whole column is the hover target, wider than the bar.
            <span key={day} title={tip} aria-label={tip} className="flex h-full items-end hover:bg-sand-100">
              {value !== undefined && (
                <span
                  className="w-full rounded-t-[4px] bg-teal-500"
                  style={{ height: `${(value / 5) * 100}%` }}
                />
              )}
            </span>
          );
        })}
      </div>
    </div>
  );
}

/** The patient's good habits with the days done over the last 30 (PRD 5.6). */
export function Habits({ patientId }: { patientId: string }) {
  const { t } = useI18n();
  const { load, reload } = useLoad(() => api.habits(patientId), [patientId]);
  return (
    <Card className="flex flex-col gap-md">
      <h3 className="text-h3 text-ink-strong">{t('habits')}</h3>
      {load.state === 'loading' && <Loading />}
      {load.state === 'error' && <Failed onRetry={reload} />}
      {load.state === 'ready' && load.data.length === 0 && <p className="text-ink-muted">{t('noHabits')}</p>}
      {load.state === 'ready' && load.data.length > 0 && (
        <ul className="flex flex-col gap-sm">
          {load.data.map((h) => (
            <li key={h.id} className="flex flex-col gap-xs">
              <div className="flex flex-wrap items-baseline justify-between gap-sm">
                <span className="text-ink-strong">{h.kind === 'custom' ? h.text : t(HABIT_KEY[h.kind])}</span>
                <span className="text-caption text-ink-muted">{fill(t('habitDone'), { n: h.done_days, d: h.days })}</span>
              </div>
              <div className="h-sm overflow-hidden rounded-pill bg-teal-100" aria-hidden="true">
                <div
                  className="h-full rounded-pill bg-teal-500"
                  style={{ width: `${(h.done_days / Math.max(h.days, 1)) * 100}%` }}
                />
              </div>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
