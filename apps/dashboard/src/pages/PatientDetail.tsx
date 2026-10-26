import { useState, type FormEvent } from 'react';
import {
  api,
  type AddictionType,
  type Medication,
  type Patient,
  type PatientAddiction,
  type ProfileSpec,
  type SubstanceProfile,
} from '../api';
import { useI18n, type StringKey } from '../i18n';
import { Badge, Button, Card, Input, Notice } from '../components/ui';
import { useLoad } from '../useLoad';
import { Failed, Loading } from './Status';
import { clinicToday } from './Today';
import { CheckChart, Habits, PROFILE_KEY, fill } from './Tracking';

export const TYPE_KEY: Record<AddictionType, StringKey> = {
  opioids: 'typeOpioids',
  cannabis: 'typeCannabis',
  alcohol: 'typeAlcohol',
  tobacco: 'typeTobacco',
  pills: 'typePills',
  stimulants: 'typeStimulants',
  gambling: 'typeGambling',
  other: 'typeOther',
};

const REVIEW_KEY = {
  pending: 'reviewPending',
  confirmed: 'reviewConfirmed',
  rejected: 'reviewRejected',
} as const satisfies Record<PatientAddiction['review_status'], StringKey>;

/** One patient's recovery file: what they entered (to confirm or refuse), how
 * each addiction is tracked and its last 30 days of checks, their good habits,
 * and the medicines the doctor prescribed. Reached from the patient list or an alert. */
export function PatientDetail({ patient, onBack }: { patient: Pick<Patient, 'id' | 'phone'>; onBack: () => void }) {
  const { t } = useI18n();
  return (
    <section className="flex flex-col gap-lg">
      <div className="flex flex-wrap items-center gap-md">
        <Button variant="ghost" onClick={onBack}>{t('back')}</Button>
        <h2 className="text-h3 text-ink-strong" dir="ltr">{patient.phone ?? '—'}</h2>
      </div>
      <Addictions patientId={patient.id} />
      <Habits patientId={patient.id} />
      <Medications patientId={patient.id} />
    </section>
  );
}

function Addictions({ patientId }: { patientId: string }) {
  const { t, date } = useI18n();
  const { load, reload, setLoad } = useLoad(() => api.patientAddictions(patientId), [patientId]);
  const profiles = useLoad(() => api.profiles(), []);
  const specs = profiles.load.state === 'ready' ? profiles.load.data : [];
  const [busy, setBusy] = useState<string | null>(null);
  const [profileFailed, setProfileFailed] = useState(false);

  function replace(updated: PatientAddiction) {
    if (load.state === 'ready') {
      setLoad({ state: 'ready', data: load.data.map((x) => (x.id === updated.id ? updated : x)) });
    }
  }

  async function changeProfile(a: PatientAddiction, profile: SubstanceProfile | null) {
    setBusy(a.id);
    setProfileFailed(false);
    try {
      replace(await api.setProfile(patientId, a.id, profile));
    } catch {
      setProfileFailed(true);
    } finally {
      setBusy(null);
    }
  }

  async function review(a: PatientAddiction, decision: 'confirm' | 'reject') {
    setBusy(a.id);
    try {
      replace(await api.reviewAddiction(patientId, a.id, decision));
    } catch {
      reload();
    } finally {
      setBusy(null);
    }
  }

  return (
    <Card className="flex flex-col gap-md">
      <h3 className="text-h3 text-ink-strong">{t('addictions')}</h3>
      {load.state === 'loading' && <Loading />}
      {load.state === 'error' && <Failed onRetry={reload} />}
      {load.state === 'ready' && load.data.length === 0 && <p className="text-ink-muted">{t('noAddictions')}</p>}
      {profileFailed && (
        <p role="alert" className="text-danger">
          {t('profileFailed')}
        </p>
      )}
      {load.state === 'ready' &&
        load.data.map((a) => (
          <article key={a.id} className="flex flex-col gap-sm border-b border-border pb-md last:border-0 last:pb-0">
            <div className="flex flex-wrap items-center gap-sm">
              <h4 className="text-body-lg text-ink-strong">
                {a.profile ? t(PROFILE_KEY[a.profile]) : t(TYPE_KEY[a.type])}
              </h4>
              <Badge tone={a.review_status === 'confirmed' ? 'success' : a.review_status === 'rejected' ? 'danger' : 'warning'}>
                {t(REVIEW_KEY[a.review_status])}
              </Badge>
            </div>
            <Streak a={a} />
            <dl className="grid grid-cols-[auto_1fr] gap-x-xl gap-y-xs">
              <dt className="text-label text-ink-muted">
                <label htmlFor={`profile-${a.id}`}>{t('profileLabel')}</label>
              </dt>
              <dd>
                <select
                  id={`profile-${a.id}`}
                  className="rounded-field border border-border bg-surface px-sm py-xs text-ink-strong"
                  disabled={busy === a.id}
                  value={a.profile ?? ''}
                  onChange={(e) => changeProfile(a, (e.target.value || null) as SubstanceProfile | null)}
                >
                  <option value="">{t('profileGeneric')}</option>
                  {(Object.keys(PROFILE_KEY) as SubstanceProfile[]).map((p) => (
                    <option key={p} value={p}>
                      {t(PROFILE_KEY[p])}
                    </option>
                  ))}
                </select>
              </dd>
              {a.profile && (
                <>
                  <dt className="text-label text-ink-muted">{t('typeLabel')}</dt>
                  <dd className="text-ink-strong">{t(TYPE_KEY[a.type])}</dd>
                </>
              )}
              {a.substance && (
                <>
                  <dt className="text-label text-ink-muted">{t('substance')}</dt>
                  <dd className="text-ink-strong">{a.substance}</dd>
                </>
              )}
              <dt className="text-label text-ink-muted">{t('cleanSince')}</dt>
              <dd className="text-ink-strong">{date(a.clean_since)}</dd>
              <dt className="text-label text-ink-muted">{t('relapses')}</dt>
              <dd className="text-ink-strong">
                {a.relapses.length === 0 ? (
                  t('noRelapses')
                ) : (
                  <ul className="flex flex-col gap-xs">
                    {a.relapses.map((r) => (
                      <li key={r.at}>
                        {date(r.at)}
                        {r.note ? ` — ${r.note}` : ''}
                      </li>
                    ))}
                  </ul>
                )}
              </dd>
            </dl>
            <CheckChart patientId={patientId} addictionId={a.id} spec={specOf(specs, a.profile)} />
            <div className="flex gap-sm">
              {a.review_status !== 'confirmed' && (
                <Button disabled={busy === a.id} onClick={() => review(a, 'confirm')}>{t('confirm')}</Button>
              )}
              {a.review_status !== 'rejected' && (
                <Button variant="danger" disabled={busy === a.id} onClick={() => review(a, 'reject')}>{t('reject')}</Button>
              )}
            </div>
          </article>
        ))}
    </Card>
  );
}

function specOf(specs: ProfileSpec[], profile: SubstanceProfile | null): ProfileSpec | undefined {
  return specs.find((s) => s.key === profile);
}

const DAY_MS = 24 * 60 * 60 * 1000;

/** The counter as the patient sees it (PRD 5.1, 5.6): current, longest and
 * total days without use, and the small goal. */
function Streak({ a }: { a: PatientAddiction }) {
  const { t } = useI18n();
  const current = Math.max(0, Math.floor((Date.now() - new Date(a.clean_since).getTime()) / DAY_MS));
  const days = (n: number) => fill(t('daysCount'), { n });
  const stats: [StringKey, string][] = [
    ['currentStreak', days(current)],
    ['longestStreak', days(Math.max(a.longest_past_days, current))],
    ['totalSober', days(a.past_days + current)],
    ['smallGoal', `${days(a.goal)} · ${t(a.goal_days === null ? 'goalAuto' : 'goalChosen')}`],
  ];
  return (
    <div className="grid grid-cols-2 gap-sm sm:grid-cols-4">
      {stats.map(([key, value]) => (
        <div key={key} className="flex flex-col rounded-field bg-sand-50 px-md py-sm">
          <span className="text-h3 text-teal-700">{value}</span>
          <span className="text-caption text-ink-muted">{t(key)}</span>
        </div>
      ))}
    </div>
  );
}

/** "08:00, 20:00" or "08:00 20:00" as a list; the server checks each time. */
export function parseTimes(text: string): string[] {
  return text.split(/[\s,;]+/).filter(Boolean);
}

function Medications({ patientId }: { patientId: string }) {
  const { t, date } = useI18n();
  const { load, reload, setLoad } = useLoad(() => api.medications(patientId), [patientId]);
  const [busy, setBusy] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  const [form, setForm] = useState({ name: '', amount: '', times: '', start: clinicToday(), end: '', instructions: '' });
  const set = (key: keyof typeof form) => (e: { target: { value: string } }) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy('new');
    setFailed(false);
    try {
      const added = await api.prescribe(patientId, {
        name: form.name.trim(),
        amount: form.amount.trim(),
        times: parseTimes(form.times),
        start_date: form.start,
        end_date: form.end || null,
        instructions: form.instructions.trim() || null,
      });
      if (load.state === 'ready') setLoad({ state: 'ready', data: [...load.data, added] });
      setForm({ name: '', amount: '', times: '', start: clinicToday(), end: '', instructions: '' });
    } catch {
      setFailed(true);
    } finally {
      setBusy(null);
    }
  }

  async function stop(m: Medication) {
    setBusy(m.id);
    try {
      await api.stopMedication(patientId, m.id);
      if (load.state === 'ready') setLoad({ state: 'ready', data: load.data.filter((x) => x.id !== m.id) });
    } catch {
      reload();
    } finally {
      setBusy(null);
    }
  }

  return (
    <Card className="flex flex-col gap-md">
      <h3 className="text-h3 text-ink-strong">{t('medications')}</h3>
      <Notice>{t('medNotice')}</Notice>
      {load.state === 'loading' && <Loading />}
      {load.state === 'error' && <Failed onRetry={reload} />}
      {load.state === 'ready' && load.data.length === 0 && <p className="text-ink-muted">{t('noMedications')}</p>}
      {load.state === 'ready' &&
        load.data.map((m) => (
          <article key={m.id} className="flex flex-wrap items-center gap-md border-b border-border pb-md last:border-0 last:pb-0">
            <div className="flex min-w-[12rem] flex-1 flex-col gap-xs">
              <span className="text-body-lg text-ink-strong">
                {m.name} — <span dir="ltr">{m.amount}</span>
              </span>
              <span className="text-ink-body" dir="ltr">{m.times.join(' · ')}</span>
              <span className="text-caption text-ink-muted">
                {date(`${m.start_date}T12:00:00Z`)}
                {m.end_date ? ` → ${date(`${m.end_date}T12:00:00Z`)}` : ''}
                {m.instructions ? ` — ${m.instructions}` : ''}
              </span>
            </div>
            <Button variant="danger" disabled={busy === m.id} onClick={() => stop(m)}>{t('stop')}</Button>
          </article>
        ))}
      <form onSubmit={submit} className="flex flex-col gap-md border-t border-border pt-md">
        <div className="grid gap-md sm:grid-cols-2">
          <Input label={t('medName')} required maxLength={100} value={form.name} onChange={set('name')} />
          <Input label={t('medAmount')} required maxLength={50} dir="ltr" value={form.amount} onChange={set('amount')} />
          <Input label={t('medTimes')} required dir="ltr" value={form.times} onChange={set('times')} />
          <Input label={t('medStart')} type="date" required dir="ltr" value={form.start} onChange={set('start')} />
          <Input label={t('medEnd')} type="date" dir="ltr" value={form.end} onChange={set('end')} />
          <Input label={t('medInstructions')} maxLength={300} value={form.instructions} onChange={set('instructions')} />
        </div>
        {failed && <p role="alert" className="text-danger">{t('prescribeFailed')}</p>}
        <div>
          <Button type="submit" disabled={busy === 'new'}>{t('prescribe')}</Button>
        </div>
      </form>
    </Card>
  );
}
