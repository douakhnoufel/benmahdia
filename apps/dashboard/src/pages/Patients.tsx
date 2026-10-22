import { useState } from 'react';
import { api } from '../api';
import { useI18n } from '../i18n';
import { Button, Card, Input } from '../components/ui';
import { useLoad } from '../useLoad';
import { PatientDetail } from './PatientDetail';
import { Failed, Loading } from './Status';

export function Patients({ open, onClose }: { open?: { id: string; phone: string | null } | null; onClose?: () => void } = {}) {
  const { t, date } = useI18n();
  const [query, setQuery] = useState('');
  const [picked, setPicked] = useState<{ id: string; phone: string | null } | null>(null);
  const selected = open ?? picked;
  const { load, reload } = useLoad(() => api.patients(), []);
  // Local (0772…) or international (+213772…) both match: drop the leading 0.
  const digits = query.replace(/\D/g, '').replace(/^0/, '');
  const shown =
    load.state === 'ready' ? load.data.filter((p) => !digits || (p.phone ?? '').replace(/\D/g, '').includes(digits)) : [];

  if (selected) {
    return (
      <PatientDetail
        patient={selected}
        onBack={() => {
          setPicked(null);
          onClose?.();
        }}
      />
    );
  }

  return (
    <section className="flex flex-col gap-lg">
      <div className="max-w-xs">
        <Input label={t('phone')} type="search" inputMode="tel" dir="ltr" value={query}
          onChange={(e) => setQuery(e.target.value)} />
      </div>
      <Card className="overflow-x-auto p-0">
        {load.state === 'loading' && <Loading />}
        {load.state === 'error' && <Failed onRetry={reload} />}
        {load.state === 'ready' && shown.length === 0 && <p className="p-xl text-ink-muted">{t('noPatients')}</p>}
        {load.state === 'ready' && shown.length > 0 && (
          <table className="w-full">
            <thead className="border-b border-border text-label text-ink-muted">
              <tr>
                <th className="p-md text-start">{t('phone')}</th>
                <th className="p-md text-start">{t('visits')}</th>
                <th className="p-md text-start">{t('lastVisit')}</th>
                <th className="p-md text-start">{t('nextVisit')}</th>
              </tr>
            </thead>
            <tbody>
              {shown.map((p) => (
                <tr key={p.id} className="border-b border-border last:border-0">
                  <td className="p-md text-ink-strong" dir="ltr">
                    <Button variant="ghost" className="px-sm" onClick={() => setPicked({ id: p.id, phone: p.phone })}>
                      {p.phone ?? '—'}
                    </Button>
                  </td>
                  <td className="p-md">{p.visits}</td>
                  <td className="p-md">{p.last_visit ? date(p.last_visit) : '—'}</td>
                  <td className="p-md">{p.next_visit ? date(p.next_visit) : '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
    </section>
  );
}
