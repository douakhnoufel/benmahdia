import { Fragment, useState } from 'react';
import { api, type PaymentRow } from '../api';
import { useI18n } from '../i18n';
import { METHOD_KEY, ReceiptPanel } from '../components/ReceiptPanel';
import { Badge, Button, Card, Input } from '../components/ui';
import { useLoad } from '../useLoad';
import { Failed, Loading } from './Status';
import { clinicToday } from './Today';
import { fill } from './Tracking';

const MAX_DAYS = 92;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Whether [from]..[to] (YYYY-MM-DD, both included) is a range the server accepts. */
export function validRange(from: string, to: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) return false;
  const days = (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY_MS;
  return days >= 0 && days < MAX_DAYS;
}

/** Paid / unpaid status per appointment, with receipts (PRD 4.4, 7). A doctor
 * sees their own appointments, the super admin everyone's: the API decides. */
export function Payments() {
  const { t } = useI18n();
  const today = clinicToday();
  const [from, setFrom] = useState(`${today.slice(0, 8)}01`);
  const [to, setTo] = useState(today);
  const valid = validRange(from, to);
  return (
    <section className="flex flex-col gap-lg">
      <Card className="flex flex-wrap items-end gap-md">
        <Input label={t('periodStart')} type="date" dir="ltr" value={from} onChange={(e) => setFrom(e.target.value)} />
        <Input label={t('periodEnd')} type="date" dir="ltr" value={to} onChange={(e) => setTo(e.target.value)} />
        {!valid && <p role="alert" className="text-caption text-danger">{t('errRange')}</p>}
      </Card>
      {valid && <PaymentsTable from={from} to={to} />}
    </section>
  );
}

function PaymentsTable({ from, to }: { from: string; to: string }) {
  const { t } = useI18n();
  const { load, reload } = useLoad(() => api.payments(from, to), [from, to]);
  const [open, setOpen] = useState<string | null>(null);
  if (load.state === 'loading') return <Loading />;
  if (load.state === 'error') return <Failed onRetry={reload} />;
  const { rows, totals } = load.data;
  return (
    <>
      <div className="flex flex-wrap gap-sm">
        <Badge tone="success">{fill(t('totalsPaid'), { amount: totals.paid_dzd, n: totals.paid_count })}</Badge>
        <Badge tone="warning">{fill(t('totalsUnpaid'), { amount: totals.unpaid_dzd, n: totals.unpaid_count })}</Badge>
      </div>
      <Card className="overflow-x-auto p-0">
        {rows.length === 0 ? (
          <p className="p-xl text-ink-muted">{t('noPayments')}</p>
        ) : (
          <table className="w-full text-start">
            <thead className="border-b border-border text-label text-ink-muted">
              <tr>
                <th className="p-md text-start">{t('dateLabel')}</th>
                <th className="p-md text-start">{t('patient')}</th>
                <th className="p-md text-start">{t('doctor')}</th>
                <th className="p-md text-start">{t('status')}</th>
                <th className="p-md text-start">{t('paymentMethod')}</th>
                <th className="p-md text-start">{t('amount')}</th>
                <th className="p-md text-start">{t('payment')}</th>
                <th className="p-md text-start">{t('receipt')}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <Fragment key={r.id}>
                  <Row row={r} open={open === r.id} onToggle={() => setOpen(open === r.id ? null : r.id)} />
                  {open === r.id && (
                    <tr className="border-b border-border">
                      <td colSpan={8} className="p-md">
                        <ReceiptPanel appointmentId={r.id} onClose={() => setOpen(null)} />
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        )}
      </Card>
    </>
  );
}

function Row({ row, open, onToggle }: { row: PaymentRow; open: boolean; onToggle: () => void }) {
  const { t, lang, date, time } = useI18n();
  return (
    <tr className="border-b border-border last:border-0">
      <td className="p-md text-ink-strong">
        {date(row.start)} · <span dir="ltr">{time(row.start)}</span>
      </td>
      <td className="p-md" dir="ltr">{row.patient_phone ?? '—'}</td>
      <td className="p-md text-ink-body">{lang === 'ar' ? row.doctor_name_ar : row.doctor_name_fr}</td>
      <td className="p-md">
        <Badge>{t(row.status)}</Badge>
      </td>
      <td className="p-md text-ink-body">{row.method ? t(METHOD_KEY[row.method]) : '—'}</td>
      <td className="p-md text-ink-strong">
        {row.price_dzd} {t('dzd')}
      </td>
      <td className="p-md">
        <Badge tone={row.paid ? 'success' : 'warning'}>{t(row.paid ? 'paid' : 'unpaid')}</Badge>
      </td>
      <td className="p-md">
        {row.paid && (
          <Button variant="secondary" aria-expanded={open} onClick={onToggle}>
            {t(open ? 'close' : 'receipt')}
          </Button>
        )}
      </td>
    </tr>
  );
}
