import { useState } from 'react';
import { api, type AgendaItem } from '../api';
import { useI18n } from '../i18n';
import { Badge, Button, Card } from '../components/ui';
import { useLoad } from '../useLoad';
import { Failed, Loading } from './Status';

/** Today's date in clinic time, YYYY-MM-DD. */
export function clinicToday(now = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Algiers' }).format(now);
}

function shift(day: string, by: number): string {
  const d = new Date(`${day}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + by);
  return d.toISOString().slice(0, 10);
}

const statusTone = { confirmed: 'info', completed: 'success', no_show: 'danger', cancelled: 'neutral', awaiting_payment: 'warning' } as const;

export function Today({ initialDay }: { initialDay?: string }) {
  const { t, date, time } = useI18n();
  const [day, setDay] = useState(initialDay ?? clinicToday());
  const { load, reload, setLoad } = useLoad(() => api.agenda(day), [day]);

  function replace(item: AgendaItem) {
    if (load.state !== 'ready') return;
    setLoad({ state: 'ready', data: load.data.map((a) => (a.id === item.id ? item : a)) });
  }

  return (
    <section className="flex flex-col gap-lg">
      <div className="flex flex-wrap items-center gap-md">
        <Button variant="secondary" onClick={() => setDay(shift(day, -1))} aria-label={t('previousDay')}>
          ‹
        </Button>
        <h2 className="text-h2 text-ink-strong">{date(`${day}T12:00:00Z`)}</h2>
        <Button variant="secondary" onClick={() => setDay(shift(day, 1))} aria-label={t('nextDay')}>
          ›
        </Button>
      </div>
      <Card className="overflow-x-auto p-0">
        {load.state === 'loading' && <Loading />}
        {load.state === 'error' && <Failed onRetry={reload} />}
        {load.state === 'ready' && load.data.length === 0 && <p className="p-xl text-ink-muted">{t('noVisits')}</p>}
        {load.state === 'ready' && load.data.length > 0 && (
          <table className="w-full text-start">
            <thead className="border-b border-border text-label text-ink-muted">
              <tr>
                <th className="p-md text-start">{t('time')}</th>
                <th className="p-md text-start">{t('patient')}</th>
                <th className="p-md text-start">{t('status')}</th>
                <th className="p-md text-start">{t('payment')}</th>
                <th className="p-md text-start">{t('actions')}</th>
              </tr>
            </thead>
            <tbody>
              {load.data.map((a) => (
                <Row key={a.id} item={a} onChange={replace} timeOf={time} />
              ))}
            </tbody>
          </table>
        )}
      </Card>
    </section>
  );
}

function Row({ item, onChange, timeOf }: { item: AgendaItem; onChange: (a: AgendaItem) => void; timeOf: (iso: string) => string }) {
  const { t } = useI18n();
  const [busy, setBusy] = useState(false);
  const started = new Date(item.start).getTime() <= Date.now();
  const markable = started && ['confirmed', 'completed', 'no_show'].includes(item.status);

  async function act(run: () => Promise<AgendaItem>) {
    setBusy(true);
    try {
      onChange(await run());
    } catch {
      // The row keeps its last known state; the doctor can try again.
    } finally {
      setBusy(false);
    }
  }

  return (
    <tr className="border-b border-border last:border-0">
      <td className="p-md text-ink-strong" dir="ltr">
        {timeOf(item.start)}
      </td>
      <td className="p-md" dir="ltr">
        {item.patient_phone ?? '—'}
      </td>
      <td className="p-md">
        <Badge tone={statusTone[item.status]}>{t(item.status)}</Badge>
      </td>
      <td className="p-md">
        <div className="flex flex-wrap items-center gap-sm">
          <Badge tone={item.paid ? 'success' : 'warning'}>{t(item.paid ? 'paid' : 'unpaid')}</Badge>
          <span className="text-caption text-ink-muted">
            {t(item.method === 'clinic' ? 'clinic' : 'card')} · {item.price_dzd} DA
          </span>
        </div>
      </td>
      <td className="p-md">
        <div className="flex flex-wrap gap-sm">
          {item.method === 'clinic' && item.status !== 'cancelled' && (
            <Button variant="secondary" disabled={busy} onClick={() => act(() => api.setPaid(item.id, !item.paid))}>
              {t(item.paid ? 'markUnpaid' : 'markPaid')}
            </Button>
          )}
          {markable && item.status !== 'completed' && (
            <Button disabled={busy} onClick={() => act(() => api.setStatus(item.id, 'completed'))}>
              {t('markCompleted')}
            </Button>
          )}
          {markable && item.status !== 'no_show' && (
            <Button variant="danger" disabled={busy} onClick={() => act(() => api.setStatus(item.id, 'no_show'))}>
              {t('markNoShow')}
            </Button>
          )}
        </div>
      </td>
    </tr>
  );
}
