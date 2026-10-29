import { useEffect, useState, type FormEvent } from 'react';
import { api, type Visit } from '../api';
import { useI18n } from '../i18n';
import { ReceiptPanel } from '../components/ReceiptPanel';
import { Badge, Button, Card, Notice } from '../components/ui';
import { useLoad } from '../useLoad';
import { Failed, Loading } from './Status';
import { fill } from './Tracking';

const statusTone = { confirmed: 'info', completed: 'success', no_show: 'danger', cancelled: 'neutral', awaiting_payment: 'warning' } as const;
const MAX_NOTE = 5000;

/** A note follows one of the doctor's own visits that started and was not cancelled. */
function notable(v: Visit): boolean {
  return v.mine && ['confirmed', 'completed', 'no_show'].includes(v.status) && new Date(v.start).getTime() <= Date.now();
}

/** The patient's visits in the clinic, newest first, and how many they
 * attended (PRD 4.3). Other doctors' visits are booking data only. On their
 * own past visits, the doctor writes a private note. */
export function PatientAppointments({ patientId }: { patientId: string }) {
  const { t } = useI18n();
  const { load, reload, setLoad } = useLoad(() => api.patientAppointments(patientId), [patientId]);

  function noted(id: string, has: boolean) {
    if (load.state !== 'ready') return;
    const appointments = load.data.appointments.map((v) => (v.id === id ? { ...v, has_note: has } : v));
    setLoad({ state: 'ready', data: { ...load.data, appointments } });
  }

  return (
    <section aria-labelledby="appointments">
      <Card className="flex flex-col gap-md">
        <h3 id="appointments" className="text-h3 text-ink-strong">{t('appointmentsTitle')}</h3>
        {load.state === 'loading' && <Loading />}
        {load.state === 'error' && <Failed onRetry={reload} />}
        {load.state === 'ready' && (
          <>
            <Attendance {...load.data.attendance} />
            {load.data.appointments.length === 0 ? (
              <p className="text-ink-muted">{t('noAppointments')}</p>
            ) : (
              <ul className="flex flex-col">
                {load.data.appointments.map((v) => (
                  <VisitRow key={v.id} visit={v} onNoted={(has) => noted(v.id, has)} />
                ))}
              </ul>
            )}
          </>
        )}
      </Card>
    </section>
  );
}

function Attendance({ completed, no_show, rate }: { completed: number; no_show: number; rate: number | null }) {
  const { t } = useI18n();
  if (rate === null) return <p className="text-ink-muted">{t('noAttendance')}</p>;
  return (
    <p className="text-body-lg text-ink-strong">
      {fill(t('attendance'), { rate: Math.round(rate * 100), done: completed, missed: no_show })}
    </p>
  );
}

function VisitRow({ visit, onNoted }: { visit: Visit; onNoted: (has: boolean) => void }) {
  const { t, lang, date, time } = useI18n();
  const [editing, setEditing] = useState(false);
  const [receipt, setReceipt] = useState(false);
  return (
    <li className="flex flex-col gap-sm border-b border-border py-sm last:border-0">
      <div className="flex flex-wrap items-center gap-md">
        <span className="min-w-[10rem] text-ink-strong">
          {date(visit.start)} · <span dir="ltr">{time(visit.start)}</span>
        </span>
        <span className="text-ink-body">{lang === 'ar' ? visit.doctor_name_ar : visit.doctor_name_fr}</span>
        <Badge tone={statusTone[visit.status]}>{t(visit.status)}</Badge>
        {visit.status !== 'cancelled' && <Badge tone={visit.paid ? 'success' : 'warning'}>{t(visit.paid ? 'paid' : 'unpaid')}</Badge>}
        <div className="ms-auto flex flex-wrap gap-sm">
          {visit.mine && visit.paid && (
            <Button variant="ghost" aria-expanded={receipt} onClick={() => setReceipt(!receipt)}>
              {t(receipt ? 'close' : 'receipt')}
            </Button>
          )}
          {notable(visit) && !editing && (
            <Button variant="secondary" onClick={() => setEditing(true)}>
              {t(visit.has_note ? 'noteOpen' : 'noteAdd')}
            </Button>
          )}
        </div>
      </div>
      {receipt && <ReceiptPanel appointmentId={visit.id} onClose={() => setReceipt(false)} />}
      {editing && <NoteEditor appointmentId={visit.id} onClose={() => setEditing(false)} onNoted={onNoted} />}
    </li>
  );
}

function NoteEditor({ appointmentId, onClose, onNoted }: { appointmentId: string; onClose: () => void; onNoted: (has: boolean) => void }) {
  const { t, date } = useI18n();
  const { load, reload } = useLoad(() => api.note(appointmentId), [appointmentId]);
  const [text, setText] = useState('');
  const [updatedAt, setUpdatedAt] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<'saved' | 'failed' | null>(null);

  useEffect(() => {
    if (load.state === 'ready') {
      setText(load.data.text ?? '');
      setUpdatedAt(load.data.updated_at);
    }
  }, [load]);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setOutcome(null);
    try {
      const saved = await api.saveNote(appointmentId, text);
      setText(saved.text ?? '');
      setUpdatedAt(saved.updated_at);
      onNoted(saved.text !== null);
      setOutcome('saved');
    } catch {
      setOutcome('failed');
    } finally {
      setBusy(false);
    }
  }

  if (load.state === 'loading') return <Loading />;
  if (load.state === 'error') return <Failed onRetry={reload} />;
  return (
    <form onSubmit={submit} className="flex flex-col gap-sm rounded-field bg-sand-50 p-md">
      <Notice>{t('notePrivacy')}</Notice>
      <label className="flex flex-col gap-xs text-label text-ink-strong">
        {t('noteLabel')}
        <textarea
          rows={5}
          maxLength={MAX_NOTE}
          className="rounded-field border border-border bg-surface p-md text-body text-ink-strong focus:border-teal-500 focus:outline-none"
          value={text}
          onChange={(e) => {
            setText(e.target.value);
            setOutcome(null);
          }}
        />
      </label>
      <span className="text-caption text-ink-muted">
        {updatedAt ? `${fill(t('noteUpdated'), { date: date(updatedAt) })} · ` : ''}
        {t('noteEmptyDeletes')}
      </span>
      {outcome === 'saved' && <p role="status" className="text-success">{t('saved')}</p>}
      {outcome === 'failed' && <p role="alert" className="text-danger">{t('saveFailed')}</p>}
      <div className="flex gap-sm">
        <Button type="submit" disabled={busy}>{t('save')}</Button>
        <Button variant="ghost" onClick={onClose}>{t('close')}</Button>
      </div>
    </form>
  );
}
