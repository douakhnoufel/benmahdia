import { useState } from 'react';
import { api, type Signup } from '../api';
import { useI18n } from '../i18n';
import { Button, Card, Notice } from '../components/ui';
import { useLoad } from '../useLoad';
import { Failed, Loading } from './Status';

export function Signups() {
  const { t, date } = useI18n();
  const { load, reload, setLoad } = useLoad(() => api.signups(), []);
  const [busy, setBusy] = useState<string | null>(null);

  async function decide(s: Signup, run: (id: string) => Promise<Signup>) {
    setBusy(s.id);
    try {
      await run(s.id);
      if (load.state === 'ready') setLoad({ state: 'ready', data: load.data.filter((x) => x.id !== s.id) });
    } catch {
      reload();
    } finally {
      setBusy(null);
    }
  }

  return (
    <section className="flex flex-col gap-lg">
      <Notice>{t('photosLater')}</Notice>
      <Card className="overflow-x-auto p-0">
        {load.state === 'loading' && <Loading />}
        {load.state === 'error' && <Failed onRetry={reload} />}
        {load.state === 'ready' && load.data.length === 0 && <p className="p-xl text-ink-muted">{t('noSignups')}</p>}
        {load.state === 'ready' && load.data.length > 0 && (
          <table className="w-full">
            <thead className="border-b border-border text-label text-ink-muted">
              <tr>
                <th className="p-md text-start">{t('phone')}</th>
                <th className="p-md text-start">{t('signedUp')}</th>
                <th className="p-md text-start">{t('actions')}</th>
              </tr>
            </thead>
            <tbody>
              {load.data.map((s) => (
                <tr key={s.id} className="border-b border-border last:border-0">
                  <td className="p-md text-ink-strong" dir="ltr">{s.phone ?? '—'}</td>
                  <td className="p-md">{date(s.created_at)}</td>
                  <td className="p-md">
                    <div className="flex gap-sm">
                      <Button disabled={busy === s.id} onClick={() => decide(s, api.approve)}>{t('approve')}</Button>
                      <Button variant="danger" disabled={busy === s.id} onClick={() => decide(s, api.reject)}>
                        {t('reject')}
                      </Button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
    </section>
  );
}
