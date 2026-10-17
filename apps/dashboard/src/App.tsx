import { useEffect, useState } from 'react';
import { isSignedIn, onSessionChange, signOut } from './api';
import { useI18n, type StringKey } from './i18n';
import { Button } from './components/ui';
import { Login } from './pages/Login';
import { Patients } from './pages/Patients';
import { Signups } from './pages/Signups';
import { Today } from './pages/Today';

type Page = 'today' | 'patients' | 'signups';
const pages: Page[] = ['today', 'patients', 'signups'];

export function App() {
  const { t, lang, setLang } = useI18n();
  const [signedIn, setSignedIn] = useState(isSignedIn());
  const [page, setPage] = useState<Page>('today');
  useEffect(() => {
    const off = onSessionChange(setSignedIn);
    return () => {
      off();
    };
  }, []);

  if (!signedIn) return <Login />;

  return (
    <div className="min-h-screen">
      <header className="border-b border-border bg-surface">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-lg px-xl py-md">
          <h1 className="text-h3 text-ink-strong">{t('appName')}</h1>
          <nav className="flex gap-sm">
            {pages.map((p) => (
              <Button key={p} variant={p === page ? 'primary' : 'ghost'} aria-current={p === page ? 'page' : undefined}
                onClick={() => setPage(p)}>
                {t(p as StringKey)}
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
        {page === 'patients' && <Patients />}
        {page === 'signups' && <Signups />}
      </main>
    </div>
  );
}
