"""Raises the daily alerts. "missed_doses" (PRD 5.3): a patient who took none
of a medicine's doses on each of the last two full days; at most one per
patient and doctor per day. "craving_high" and "no_checkin" (PRD 5.6): craving
4 or more on one addiction, or no daily check at all, on each of the last
three full days; at most one of each per patient every three days. Run daily,
after midnight in Algiers: `python -m app.alerts_job`. No alert names a
medicine, a substance or an answer."""

import uuid
from datetime import date, datetime, timedelta

from sqlalchemy import Select, select
from sqlalchemy.orm import Session

from . import scheduling
from .clock import clock
from .db import SessionLocal
from .models import (
    Addiction,
    AddictionCheck,
    Alert,
    DailyCheck,
    DoseLog,
    DoseStatus,
    Medication,
    ReviewStatus,
)
from .routers.recovery import _doctor_of
from .substances import reached_milestone

DAYS_IN_A_ROW = 2
# PRD 5.6, fixed in v1.
CHECK_DAYS_IN_A_ROW = 3
HIGH_CRAVING = 4


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


def _check_window() -> tuple[list[date], datetime]:
    """The last three full clinic days, newest first, and the start of the
    window in which an earlier alert of the same kind still counts."""
    today = scheduling.clinic_today(clock.now())
    days = [today - timedelta(days=n) for n in range(1, CHECK_DAYS_IN_A_ROW + 1)]
    return days, scheduling.to_utc(today - timedelta(days=CHECK_DAYS_IN_A_ROW - 1), 0)


def _raise_once(db: Session, patient_id: uuid.UUID, kind: str, since: datetime) -> bool:
    doctor_id = _doctor_of(db, patient_id)
    if doctor_id is None:
        return False
    already = db.scalar(
        select(Alert.id).where(
            Alert.doctor_id == doctor_id,
            Alert.patient_id == patient_id,
            Alert.type == kind,
            Alert.created_at >= since,
        ).limit(1)
    )
    if already is not None:
        return False
    db.add(Alert(doctor_id=doctor_id, patient_id=patient_id, type=kind))
    db.flush()
    return True


def _tracked() -> Select:
    return select(Addiction).where(
        Addiction.active.is_(True), Addiction.review_status != ReviewStatus.rejected
    )


def craving_alerts(db: Session) -> int:
    days, since = _check_window()
    patients = set()
    for a in db.scalars(_tracked()):
        high = db.scalars(
            select(AddictionCheck.day).where(
                AddictionCheck.addiction_id == a.id,
                AddictionCheck.day.in_(days),
                AddictionCheck.craving >= HIGH_CRAVING,
            )
        ).all()
        if len(set(high)) == len(days):
            patients.add(a.patient_id)
    created = sum(_raise_once(db, p, "craving_high", since) for p in patients)
    db.commit()
    return created


def no_checkin_alerts(db: Session) -> int:
    """Only for addictions tracked since before the window: a new one has not
    had three days to be checked yet."""
    days, since = _check_window()
    window_start = scheduling.to_utc(days[-1], 0)
    by_patient: dict[uuid.UUID, list[uuid.UUID]] = {}
    for a in db.scalars(_tracked()):
        if a.created_at < window_start:
            by_patient.setdefault(a.patient_id, []).append(a.id)
    created = 0
    for patient_id, ids in by_patient.items():
        checked = db.scalar(
            select(AddictionCheck.id).where(
                AddictionCheck.addiction_id.in_(ids), AddictionCheck.day.in_(days)
            ).limit(1)
        ) or db.scalar(
            select(DailyCheck.id).where(
                DailyCheck.patient_id == patient_id, DailyCheck.day.in_(days)
            ).limit(1)
        )
        if checked is None and _raise_once(db, patient_id, "no_checkin", since):
            created += 1
    db.commit()
    return created


def milestone_alerts(db: Session) -> int:
    """"milestone" (PRD 5.1): one alert for each milestone a streak reaches,
    even if the patient did not open the app. A streak that starts far back
    (or a missed run) gives one alert for the highest milestone, not one per
    step. It names no addiction."""
    now = clock.now()
    created = 0
    for a in db.scalars(_tracked()):
        reached = reached_milestone(max(0, (now - a.sobriety_start).days))
        if reached <= a.milestone_alerted:
            continue
        a.milestone_alerted = reached
        doctor_id = _doctor_of(db, a.patient_id)
        if doctor_id is not None:
            db.add(Alert(doctor_id=doctor_id, patient_id=a.patient_id, type="milestone"))
            created += 1
        db.flush()
    db.commit()
    return created


if __name__ == "__main__":
    with SessionLocal() as session:
        print(f"Raised {missed_dose_alerts(session)} missed-dose alert(s).")
        print(f"Raised {craving_alerts(session)} craving alert(s).")
        print(f"Raised {no_checkin_alerts(session)} missed-check alert(s).")
        print(f"Raised {milestone_alerts(session)} milestone alert(s).")
