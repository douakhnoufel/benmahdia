"""Raises the "missed doses" alert (PRD 5.3): a patient who took none of a
medicine's doses on each of the last two full days. Run daily, after
midnight in Algiers: `python -m app.alerts_job`. At most one such alert per
patient and doctor per day, and no alert text names the medicine."""

from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import scheduling
from .clock import clock
from .db import SessionLocal
from .models import Alert, DoseLog, DoseStatus, Medication

DAYS_IN_A_ROW = 2


def _taken_on(db: Session, medication_id, day) -> bool:
    return (
        db.scalar(
            select(DoseLog.id).where(
                DoseLog.medication_id == medication_id,
                DoseLog.day == day,
                DoseLog.status == DoseStatus.taken,
            ).limit(1)
        )
        is not None
    )


def missed_dose_alerts(db: Session) -> int:
    now = clock.now()
    today = scheduling.clinic_today(now)
    days = [today - timedelta(days=n) for n in range(1, DAYS_IN_A_ROW + 1)]
    day_start = scheduling.to_utc(today, 0)
    created = 0
    for m in db.scalars(select(Medication).where(Medication.active.is_(True))):
        runs = all(
            m.start_date <= d and (m.end_date is None or d <= m.end_date) for d in days
        )
        if not runs or any(_taken_on(db, m.id, d) for d in days):
            continue
        already = db.scalar(
            select(Alert.id).where(
                Alert.doctor_id == m.prescribed_by,
                Alert.patient_id == m.patient_id,
                Alert.type == "missed_doses",
                Alert.created_at >= day_start,
            ).limit(1)
        )
        if already is not None:
            continue
        db.add(Alert(doctor_id=m.prescribed_by, patient_id=m.patient_id, type="missed_doses"))
        db.flush()
        created += 1
    db.commit()
    return created


if __name__ == "__main__":
    with SessionLocal() as session:
        print(f"Raised {missed_dose_alerts(session)} missed-dose alert(s).")
