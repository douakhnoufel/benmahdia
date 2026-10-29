import { useEffect, useState } from 'react';
import { isSignedIn, onSessionChange, signOut } from './api';
import { useI18n, type StringKey } from './i18n';
import { api, type Me } from './api';
import { Button } from './components/ui';
import { Alerts } from './pages/Alerts';
import { AvailabilityPage } from './pages/Availability';
import { Login } from './pages/Login';
import { Patients } from './pages/Patients';
import { Prices } from './pages/Prices';
import { Signups } from './pages/Signups';
import { Today } from './pages/Today';

type Page = 'today' | 'patients' | 'signups' | 'alerts' | 'availability' | 'prices';
const doctorPages: Page[] = ['today', 'patients', 'signups', 'alerts', 'availability'];

export function App() {
  const { t, lang, setLang } = useI18n();
  const [signedIn, setSignedIn] = useState(isSignedIn());
  const [page, setPage] = useState<Page>('today');
  // A patient opened from an alert; the patient list shows their file.
  const [opened, setOpened] = useState<{ id: string; phone: string | null } | null>(null);
  const [unread, setUnread] = useState(0);
  // Who is signed in: the super admin also sees the Prices page. The API
  // checks the role on every route either way.
  const [me, setMe] = useState<Me | null>(null);
  const pages: Page[] = me?.role === 'super_admin' ? [...doctorPages, 'prices'] : doctorPages;
  const countUnread = () => {
    api.alerts(true).then((a) => setUnread(a.length), () => undefined);
  };
  useEffect(() => {
    const off = onSessionChange(setSignedIn);
    return () => {
      off();
    };
  }, []);

  useEffect(() => {
    if (!signedIn) {
      setMe(null);
      return;
    }
    let live = true;
    api.me().then((m) => live && setMe(m), () => undefined);
    return () => {
      live = false;
    };
  }, [signedIn]);

  // The badge counts what is still unread, refreshed whenever the doctor changes page.
  useEffect(() => {
    if (signedIn) countUnread();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [signedIn, page]);

  if (!signedIn) return <Login />;

  return (
    <div className="min-h-screen">
      <header className="border-b border-border bg-surface">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-lg px-xl py-md">
          <h1 className="text-h3 text-ink-strong">{t('appName')}</h1>
          <nav className="flex gap-sm">
            {pages.map((p) => (
              <Button key={p} variant={p === page ? 'primary' : 'ghost'} aria-current={p === page ? 'page' : undefined}
                onClick={() => {
                  setOpened(null);
                  setPage(p);
                }}>
                {t(p as StringKey)}
                {p === 'alerts' && unread > 0 && (
                  <span className="ms-sm rounded-pill bg-danger px-sm text-caption text-on-primary" aria-label={String(unread)}>
                    {unread}
                  </span>
                )}
              </Button>
            ))}
          </nav>
          <div className="ms-auto flex gap-sm">
            <Button variant="ghost" onClick={() => setLang(lang === 'ar' ? 'fr' : 'ar')}>{t('switchLang')}</Button>
            <Button variant="ghost" onClick={signOut}>{t('signOut')}</Button>
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-6xl p-xl">
        {page === 'today' && <Today />}
        {page === 'patients' && <Patients open={opened} onClose={() => setOpened(null)} />}
        {page === 'signups' && <Signups />}
        {page === 'availability' && <AvailabilityPage />}
        {page === 'prices' && <Prices />}
        {page === 'alerts' && (
          <Alerts
            onChange={countUnread}
            onOpen={(patient) => {
              setOpened(patient);
              setPage('patients');
            }}
          />
        )}
      </main>
    </div>
  );
}
