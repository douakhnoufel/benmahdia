import { Fragment, useEffect, useState } from 'react';
import { api, type Signup } from '../api';
import { useI18n } from '../i18n';
import { Badge, Button, Card, Input, Notice } from '../components/ui';
import { useLoad } from '../useLoad';
import { Failed, Loading } from './Status';

export function Signups() {
  const { t, date } = useI18n();
  const { load, reload, setLoad } = useLoad(() => api.signups(), []);
  const [busy, setBusy] = useState<string | null>(null);
  const [open, setOpen] = useState<string | null>(null);

  async function decide(s: Signup, run: () => Promise<Signup>) {
    setBusy(s.id);
    try {
      await run();
      if (load.state === 'ready') setLoad({ state: 'ready', data: load.data.filter((x) => x.id !== s.id) });
      setOpen(null);
    } catch {
      reload();
    } finally {
      setBusy(null);
    }
  }

  return (
    <section className="flex flex-col gap-lg">
      <Notice>{t('declaredNotice')}</Notice>
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
                <th className="p-md text-start">{t('status')}</th>
                <th className="p-md text-start">{t('actions')}</th>
              </tr>
            </thead>
            <tbody>
              {load.data.map((s) => {
                const declared = s.id_status === 'declared';
                return (
                  <Fragment key={s.id}>
                    <tr className="border-b border-border last:border-0">
                      <td className="p-md text-ink-strong" dir="ltr">{s.phone ?? '—'}</td>
                      <td className="p-md">{date(s.created_at)}</td>
                      <td className="p-md">
                        <div className="flex flex-wrap items-center gap-sm">
                          <Badge tone={declared ? 'info' : 'neutral'}>{t(declared ? 'idDeclared' : 'idNone')}</Badge>
                          {s.duplicate_attempt && <Badge tone="danger">{t('idDuplicate')}</Badge>}
                        </div>
                      </td>
                      <td className="p-md">
                        {declared ? (
                          // The doctor looks at what was declared before deciding.
                          <Button variant="secondary" onClick={() => setOpen(open === s.id ? null : s.id)}>
                            {t(open === s.id ? 'close' : 'review')}
                          </Button>
                        ) : (
                          <div className="flex gap-sm">
                            <Button disabled={busy === s.id} onClick={() => decide(s, () => api.approve(s.id))}>
                              {t('approve')}
                            </Button>
                            <Button variant="danger" disabled={busy === s.id} onClick={() => decide(s, () => api.reject(s.id))}>
                              {t('reject')}
                            </Button>
                          </div>
                        )}
                      </td>
                    </tr>
                    {open === s.id && (
                      <tr className="border-b border-border bg-sand-50">
                        <td colSpan={4} className="p-lg">
                          <Review
                            signup={s}
                            busy={busy === s.id}
                            onApprove={() => decide(s, () => api.approve(s.id))}
                            onReject={(reason) => decide(s, () => api.reject(s.id, reason))}
                          />
                        </td>
                      </tr>
                    )}
                  </Fragment>
                );
              })}
            </tbody>
          </table>
        )}
      </Card>
    </section>
  );
}

/** The declared name, birth date and selfie of one patient, with the decision.
 * Opening it is logged by the server; the ID number and any card image do not exist. */
function Review({
  signup,
  busy,
  onApprove,
  onReject,
}: {
  signup: Signup;
  busy: boolean;
  onApprove: () => void;
  onReject: (reason?: string) => void;
}) {
  const { t } = useI18n();
  const { load, reload } = useLoad(() => api.identity(signup.id), [signup.id]);
  const [photo, setPhoto] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const hasSelfie = load.state === 'ready' && load.data.has_selfie;

  useEffect(() => {
    if (!hasSelfie) return;
    let live = true;
    let url: string | null = null;
    api.selfie(signup.id).then(
      (u) => {
        if (live) {
          url = u;
          setPhoto(u);
        } else {
          URL.revokeObjectURL(u);
        }
      },
      () => undefined,
    );
    return () => {
      live = false;
      if (url) URL.revokeObjectURL(url);
    };
  }, [hasSelfie, signup.id]);

  if (load.state === 'loading') return <Loading />;
  if (load.state === 'error') return <Failed onRetry={reload} />;
  const d = load.data;

  return (
    <div className="flex flex-col gap-lg">
      <div className="flex flex-wrap items-start gap-xl">
        {photo ? (
          <img src={photo} alt={t('selfiePhoto')} className="h-48 w-48 rounded-card object-cover shadow-card" />
        ) : (
          <p className="flex h-48 w-48 items-center justify-center rounded-card bg-sand-100 p-md text-center text-ink-muted">
            {t('selfieMissing')}
          </p>
        )}
        <dl className="grid grid-cols-[auto_1fr] gap-x-xl gap-y-sm">
          <dt className="text-label text-ink-muted">{t('document')}</dt>
          <dd className="text-body-lg text-ink-strong">
            {d.id_type === 'passport' ? t('docPassport') : t('docNationalId')}
          </dd>
          <dt className="text-label text-ink-muted">{t('fullName')}</dt>
          <dd className="text-body-lg text-ink-strong">{d.full_name}</dd>
          <dt className="text-label text-ink-muted">{t('birthDate')}</dt>
          <dd className="text-body-lg text-ink-strong" dir="ltr">{d.birth_date}</dd>
          <dt className="text-label text-ink-muted">{t('submissionsCount')}</dt>
          <dd className="text-body-lg text-ink-strong">{d.submissions}</dd>
        </dl>
      </div>
      <Notice>{t('reviewReminder')}</Notice>
      <div className="flex flex-wrap items-end gap-md">
        <Input label={t('rejectReason')} value={reason} maxLength={200} onChange={(e) => setReason(e.target.value)} />
        <Button disabled={busy} onClick={onApprove}>{t('approve')}</Button>
        <Button variant="danger" disabled={busy} onClick={() => onReject(reason.trim() || undefined)}>
          {t('reject')}
        </Button>
      </div>
    </div>
  );
}
