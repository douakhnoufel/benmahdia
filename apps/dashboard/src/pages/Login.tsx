import { useState, type FormEvent } from 'react';
import { api, ApiError } from '../api';
import { useI18n, type StringKey } from '../i18n';
import { Button, Card, Input } from '../components/ui';

export function Login() {
  const { t, lang, setLang } = useI18n();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<StringKey | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api.login(email, password);
    } catch (err) {
      const code = err instanceof ApiError ? err.code : 'offline';
      setError(code === 'wrong_credentials' ? 'wrongCredentials' : code === 'account_locked' ? 'locked' : 'offline');
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="flex min-h-screen items-center justify-center p-lg">
      <Card className="w-full max-w-sm">
        <div className="mb-xl flex items-center justify-between gap-md">
          <h1 className="text-h2 text-ink-strong">{t('appName')}</h1>
          <Button variant="ghost" onClick={() => setLang(lang === 'ar' ? 'fr' : 'ar')}>
            {t('switchLang')}
          </Button>
        </div>
        <form onSubmit={submit} className="flex flex-col gap-lg">
          <Input label={t('email')} type="email" autoComplete="username" required value={email}
            onChange={(e) => setEmail(e.target.value)} dir="ltr" />
          <Input label={t('password')} type="password" autoComplete="current-password" required value={password}
            onChange={(e) => setPassword(e.target.value)} dir="ltr" />
          {error && (
            <p role="alert" className="text-caption text-danger">
              {t(error)}
            </p>
          )}
          <Button type="submit" disabled={busy}>
            {t('signIn')}
          </Button>
        </form>
      </Card>
    </main>
  );
}
