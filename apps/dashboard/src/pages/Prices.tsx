import { useState, type FormEvent } from 'react';
import { api, type AdminDoctor } from '../api';
import { useI18n } from '../i18n';
import { Button, Card, Notice } from '../components/ui';
import { useLoad } from '../useLoad';
import { Failed, Loading } from './Status';

const MAX_PRICE = 100_000;

/** The appointment price of each doctor, set by the super admin (PRD 4.4).
 * The API refuses anyone else. */
export function Prices() {
  const { t } = useI18n();
  const { load, reload, setLoad } = useLoad(() => api.adminDoctors(), []);

  function replace(updated: AdminDoctor) {
    if (load.state === 'ready') setLoad({ state: 'ready', data: load.data.map((d) => (d.id === updated.id ? updated : d)) });
  }

  return (
    <section className="flex flex-col gap-lg">
      <Notice>{t('pricesNotice')}</Notice>
      <Card className="p-0">
        {load.state === 'loading' && <Loading />}
        {load.state === 'error' && <Failed onRetry={reload} />}
        {load.state === 'ready' && (
          <ul className="flex flex-col">
            {load.data.map((d) => (
              <PriceRow key={d.id} doctor={d} onSaved={replace} />
            ))}
          </ul>
        )}
      </Card>
    </section>
  );
}

function PriceRow({ doctor, onSaved }: { doctor: AdminDoctor; onSaved: (d: AdminDoctor) => void }) {
  const { t, lang } = useI18n();
  const name = lang === 'ar' ? doctor.name_ar : doctor.name_fr;
  const [value, setValue] = useState(String(doctor.price_dzd));
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<'saved' | 'failed' | null>(null);
  const price = Number(value);
  const valid = value.trim() !== '' && Number.isInteger(price) && price >= 0 && price <= MAX_PRICE;

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!valid) return;
    setBusy(true);
    setOutcome(null);
    try {
      onSaved(await api.setPrice(doctor.id, price));
      setOutcome('saved');
    } catch {
      setOutcome('failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <li className="border-b border-border p-md last:border-0">
      <form onSubmit={submit} className="flex flex-wrap items-end gap-md">
        <span className="min-w-[12rem] flex-1 text-body-lg text-ink-strong">{name}</span>
        <label className="flex flex-col gap-xs text-label text-ink-strong">
          {t('priceDzd')}
          <input
            type="number"
            min={0}
            max={MAX_PRICE}
            step={1}
            dir="ltr"
            aria-label={`${t('priceDzd')} · ${name}`}
            className="min-h-[44px] w-[10rem] rounded-field border border-border bg-surface px-md text-body text-ink-strong focus:border-teal-500 focus:outline-none"
            value={value}
            onChange={(e) => {
              setValue(e.target.value);
              setOutcome(null);
            }}
          />
        </label>
        <Button type="submit" disabled={busy || !valid || price === doctor.price_dzd}>
          {t('save')}
        </Button>
      </form>
      {!valid && <p role="alert" className="pt-sm text-caption text-danger">{t('errPrice')}</p>}
      {outcome === 'saved' && <p role="status" className="pt-sm text-success">{t('saved')}</p>}
      {outcome === 'failed' && <p role="alert" className="pt-sm text-danger">{t('saveFailed')}</p>}
    </li>
  );
}
