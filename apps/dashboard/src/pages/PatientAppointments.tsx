import { api, type Visit } from '../api';
import { useI18n } from '../i18n';
import { Badge, Card } from '../components/ui';
import { useLoad } from '../useLoad';
import { Failed, Loading } from './Status';
import { fill } from './Tracking';

const statusTone = { confirmed: 'info', completed: 'success', no_show: 'danger', cancelled: 'neutral', awaiting_payment: 'warning' } as const;

/** The patient's visits in the clinic, newest first, and how many they
 * attended (PRD 4.3). Other doctors' visits are booking data only. */
export function PatientAppointments({ patientId }: { patientId: string }) {
  const { t } = useI18n();
  const { load, reload } = useLoad(() => api.patientAppointments(patientId), [patientId]);
  return (
    <section aria-labelledby="appointments">
      <Card className="flex flex-col gap-md">
        <h3 id="appointments" className="text-h3 text-ink-strong">{t('appointmentsTitle')}</h3>
        {load.state === 'loading' && <Loading />}
        {load.state === 'error' && <Failed onRetry={reload} />}
        {load.state === 'ready' && (
          <>
            <Attendance {...load.data.attendance} />
            {load.data.appointments.length === 0 ? (
              <p className="text-ink-muted">{t('noAppointments')}</p>
            ) : (
              <ul className="flex flex-col">
                {load.data.appointments.map((v) => (
                  <VisitRow key={v.id} visit={v} />
                ))}
              </ul>
            )}
          </>
        )}
      </Card>
    </section>
  );
}

function Attendance({ completed, no_show, rate }: { completed: number; no_show: number; rate: number | null }) {
  const { t } = useI18n();
  if (rate === null) return <p className="text-ink-muted">{t('noAttendance')}</p>;
  return (
    <p className="text-body-lg text-ink-strong">
      {fill(t('attendance'), { rate: Math.round(rate * 100), done: completed, missed: no_show })}
    </p>
  );
}

function VisitRow({ visit }: { visit: Visit }) {
  const { t, lang, date, time } = useI18n();
  return (
    <li className="flex flex-wrap items-center gap-md border-b border-border py-sm last:border-0">
      <span className="min-w-[10rem] text-ink-strong">
        {date(visit.start)} · <span dir="ltr">{time(visit.start)}</span>
      </span>
      <span className="text-ink-body">{lang === 'ar' ? visit.doctor_name_ar : visit.doctor_name_fr}</span>
      <Badge tone={statusTone[visit.status]}>{t(visit.status)}</Badge>
      {visit.status !== 'cancelled' && <Badge tone={visit.paid ? 'success' : 'warning'}>{t(visit.paid ? 'paid' : 'unpaid')}</Badge>}
    </li>
  );
}
