import { useState, type FormEvent } from 'react';
import { api, ApiError, type AgendaItem } from '../api';
import { useI18n, type StringKey } from '../i18n';
import { Button, Card, Input, Notice } from './ui';

// What each error code from POST /v1/staff/checkin tells the doctor.
const errorText: Record<string, StringKey> = {
  checkin_code_invalid: 'checkinInvalid',
  not_today: 'checkinNotToday',
  not_checkable: 'checkinNotCheckable',
  too_many_attempts: 'checkinTooMany',
  offline: 'offline',
};

type Result = { ok: true; item: AgendaItem } | { ok: false; message: StringKey };

/** The front desk types the booking code the patient shows (text or QR) and
 * marks the patient as arrived. The physical ID is still checked by a person. */
export function CheckinBox({ onCheckedIn }: { onCheckedIn: (item: AgendaItem) => void }) {
  const { t, time } = useI18n();
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<Result | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (busy || code.trim() === '') return;
    setBusy(true);
    try {
      const item = await api.checkin(code);
      setResult({ ok: true, item });
      setCode('');
      onCheckedIn(item);
    } catch (error) {
      const known = error instanceof ApiError ? errorText[error.code] : undefined;
      setResult({ ok: false, message: known ?? 'checkinFailed' });
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card className="flex flex-col gap-md">
      <h3 className="text-h3 text-ink-strong">{t('checkinTitle')}</h3>
      <form onSubmit={submit} className="flex flex-wrap items-end gap-md">
        <Input
          label={t('checkinCode')}
          value={code}
          onChange={(e) => setCode(e.target.value)}
          dir="ltr"
          autoComplete="off"
          autoCapitalize="characters"
          spellCheck={false}
          maxLength={32}
        />
        <Button type="submit" disabled={busy || code.trim() === ''}>
          {t('checkinSubmit')}
        </Button>
      </form>
      {result?.ok === false && (
        <p role="alert" className="text-danger">
          {t(result.message)}
        </p>
      )}
      {result?.ok === true && (
        <div role="status" className="flex flex-col gap-sm">
          <p className="text-success">
            {t('checkinDone')}{' '}
            <span dir="ltr">
              {result.item.patient_phone ?? '—'} · {time(result.item.start)}
            </span>
          </p>
          <Notice>{t('checkinIdReminder')}</Notice>
        </div>
      )}
    </Card>
  );
}
