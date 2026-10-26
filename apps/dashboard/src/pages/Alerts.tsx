import { useState } from 'react';
import { api, type Alert } from '../api';
import { useI18n, type StringKey } from '../i18n';
import { Badge, Button, Card, Notice } from '../components/ui';
import { useLoad } from '../useLoad';
import { Failed, Loading } from './Status';

const KIND: Record<string, StringKey> = {
  relapse: 'alertRelapse',
  missed_doses: 'alertMissedDoses',
  booking_confirmed: 'alertBookingConfirmed',
  booking_cancelled: 'alertBookingCancelled',
};

/** The doctor's alerts. They name an event and a patient, nothing medical;
 * "Open" goes to the patient's file for the detail. */
export function Alerts({ onOpen, onChange }: { onOpen: (patient: { id: string; phone: string | null }) => void; onChange?: () => void }) {
  const { t, date, time } = useI18n();
  const { load, reload, setLoad } = useLoad(() => api.alerts(), []);
  const [unreadOnly, setUnreadOnly] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);

  async function markRead(a: Alert) {
    setBusy(a.id);
    try {
      const updated = await api.markAlertRead(a.id);
      if (load.state === 'ready') setLoad({ state: 'ready', data: load.data.map((x) => (x.id === a.id ? updated : x)) });
      onChange?.();
    } catch {
      reload();
    } finally {
      setBusy(null);
    }
  }

  const shown = load.state === 'ready' ? load.data.filter((a) => !unreadOnly || !a.read) : [];

  return (
    <section className="flex flex-col gap-lg">
      <Notice>{t('alertNotice')}</Notice>
      <label className="flex items-center gap-sm text-label text-ink-strong">
        <input type="checkbox" checked={unreadOnly} onChange={(e) => setUnreadOnly(e.target.checked)} />
        {t('unreadOnly')}
      </label>
      <Card className="p-0">
        {load.state === 'loading' && <Loading />}
        {load.state === 'error' && <Failed onRetry={reload} />}
        {load.state === 'ready' && shown.length === 0 && <p className="p-xl text-ink-muted">{t('noAlerts')}</p>}
        {shown.map((a) => (
          <article key={a.id} className="flex flex-wrap items-center gap-md border-b border-border p-md last:border-0">
            <div className="flex min-w-[12rem] flex-1 flex-col gap-xs">
              <div className="flex flex-wrap items-center gap-sm">
                <span className={a.read ? 'text-ink-muted' : 'text-body-lg text-ink-strong'}>{t(KIND[a.type] ?? 'alertOther')}</span>
                {a.priority === 'high' && !a.read && <Badge tone="danger">{t('priorityHigh')}</Badge>}
              </div>
              <span className="text-ink-body" dir="ltr">{a.patient_phone ?? '—'}</span>
              <span className="text-caption text-ink-muted">{date(a.created_at)} · {time(a.created_at)}</span>
            </div>
            <Button variant="secondary" onClick={() => onOpen({ id: a.patient_id, phone: a.patient_phone })}>
              {t('openPatient')}
            </Button>
            {!a.read && (
              <Button disabled={busy === a.id} onClick={() => markRead(a)}>{t('markRead')}</Button>
            )}
          </article>
        ))}
      </Card>
    </section>
  );
}
