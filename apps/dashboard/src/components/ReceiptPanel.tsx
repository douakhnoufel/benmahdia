import { useState } from 'react';
import { api, type PaymentMethod, type Receipt } from '../api';
import { useI18n, type StringKey } from '../i18n';
import { Failed, Loading } from '../pages/Status';
import { useLoad } from '../useLoad';
import { Button, Notice } from './ui';

export const METHOD_KEY: Record<PaymentMethod, StringKey> = {
  cib: 'methodCib',
  edahabia: 'methodEdahabia',
  clinic: 'methodClinic',
};

/** The receipt of a paid appointment, the same as the patient's (PRD 4.4),
 * shown in place under its row and copyable as text. */
export function ReceiptPanel({ appointmentId, onClose }: { appointmentId: string; onClose: () => void }) {
  const { t } = useI18n();
  const { load, reload } = useLoad(() => api.receipt(appointmentId), [appointmentId]);
  return (
    <section aria-label={t('receiptTitle')} className="flex flex-col gap-md rounded-field bg-sand-50 p-md">
      {load.state === 'loading' && <Loading />}
      {load.state === 'error' && <Failed onRetry={reload} />}
      {load.state === 'ready' && <Details receipt={load.data} />}
      <div>
        <Button variant="ghost" onClick={onClose}>{t('close')}</Button>
      </div>
    </section>
  );
}

function Details({ receipt }: { receipt: Receipt }) {
  const { t, lang, date, time } = useI18n();
  const [copy, setCopy] = useState<'copied' | 'copyFailed' | null>(null);
  const at = (iso: string) => `${date(iso)} ${time(iso)}`;
  const lines: [StringKey, string][] = [
    ['receiptNumber', receipt.number],
    ['doctor', lang === 'ar' ? receipt.doctor_name_ar : receipt.doctor_name_fr],
    ['receiptVisit', at(receipt.start)],
    ['amount', `${receipt.amount_dzd} ${t('dzd')}`],
    ['paymentMethod', t(METHOD_KEY[receipt.method])],
    ['receiptPaidAt', at(receipt.paid_at)],
    ...(receipt.payment_ref ? ([['receiptRef', receipt.payment_ref]] as [StringKey, string][]) : []),
  ];

  async function copyText() {
    const text = [t('receiptTitle'), ...lines.map(([k, v]) => `${t(k)} : ${v}`), t('receiptNotice')].join('\n');
    try {
      await navigator.clipboard.writeText(text);
      setCopy('copied');
    } catch {
      setCopy('copyFailed');
    }
  }

  return (
    <>
      <h4 className="text-body-lg text-ink-strong">{t('receiptTitle')}</h4>
      <dl className="grid grid-cols-[auto_1fr] gap-x-xl gap-y-xs">
        {lines.map(([k, v]) => (
          <div key={k} className="contents">
            <dt className="text-label text-ink-muted">{t(k)}</dt>
            <dd className="text-ink-strong">{v}</dd>
          </div>
        ))}
      </dl>
      <Notice>{t('receiptNotice')}</Notice>
      <div className="flex flex-wrap items-center gap-md">
        <Button variant="secondary" onClick={copyText}>{t('copyText')}</Button>
        {copy === 'copied' && <span role="status" className="text-success">{t('copied')}</span>}
        {copy === 'copyFailed' && <span role="alert" className="text-danger">{t('copyFailed')}</span>}
      </div>
    </>
  );
}
