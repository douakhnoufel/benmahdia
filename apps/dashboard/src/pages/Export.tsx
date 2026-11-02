import { useState } from 'react';
import { api, type ExportSheet } from '../api';
import { useI18n, type StringKey } from '../i18n';
import { Button, Card, Notice } from '../components/ui';

const SHEETS: { sheet: ExportSheet; title: StringKey; hint: StringKey }[] = [
  { sheet: 'patients', title: 'exportPatients', hint: 'exportPatientsHint' },
  { sheet: 'appointments', title: 'exportAppointments', hint: 'exportAppointmentsHint' },
];

/** Spreadsheet downloads for the super admin: administrative data only,
 * never clinical data. The API refuses anyone else and audits every export. */
export function Export() {
  const { t } = useI18n();
  return (
    <section className="flex flex-col gap-lg">
      <Notice>{t('exportNotice')}</Notice>
      {SHEETS.map((s) => (
        <ExportRow key={s.sheet} {...s} />
      ))}
    </section>
  );
}

function ExportRow({ sheet, title, hint }: { sheet: ExportSheet; title: StringKey; hint: StringKey }) {
  const { t } = useI18n();
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  async function download() {
    setBusy(true);
    setFailed(false);
    try {
      const { blob, filename } = await api.exportSheet(sheet);
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch {
      setFailed(true);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card className="flex flex-wrap items-center gap-md">
      <div className="flex min-w-[14rem] flex-1 flex-col gap-xs">
        <h3 className="text-h3 text-ink-strong">{t(title)}</h3>
        <p className="text-body text-ink-muted">{t(hint)}</p>
        {failed && <p role="alert" className="text-danger">{t('exportFailed')}</p>}
      </div>
      <Button onClick={download} disabled={busy}>{t('exportDownload')}</Button>
    </Card>
  );
}
