"""Medications and doses (PRD 5.3) and the quote of the day (PRD 5.2).

The doctor prescribes; the patient answers each dose. A patient reaches only
their own rows; any doctor of the clinic reaches a clinic patient's rows (a
patient with a booked visit, with any doctor). The phone schedules
reminders locally with neutral text, so the drug name is never sent through
a push service."""

import uuid
from datetime import date, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit, scheduling
from ..clock import clock
from ..db import get_db, insert_once
from ..errors import ApiError
from ..models import (
    Addiction,
    Appointment,
    AppointmentStatus,
    DoctorProfile,
    DoseLog,
    DoseStatus,
    Medication,
    Quote,
    User,
)
from .recovery import patient
from .staff import current_doctor

router = APIRouter(prefix="/v1/me", tags=["recovery"])
staff_router = APIRouter(prefix="/v1/staff/patients", tags=["staff"])

MAX_TIMES = 6
# Same window as the daily check: a late answer or a phone already past midnight.
DAYS_BACK = 2
DAYS_AHEAD = 1


def _today() -> date:
    return scheduling.clinic_today(clock.now())


# --- doctor ---------------------------------------------------------------


class MedicationIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    amount: str = Field(min_length=1, max_length=50)
    times: list[str] = Field(min_length=1, max_length=MAX_TIMES)
    start_date: date
    end_date: date | None = None
    instructions: str | None = Field(default=None, max_length=300)

    @field_validator("name", "amount")
    @classmethod
    def _text(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v

    @field_validator("instructions")
    @classmethod
    def _instr(cls, v: str | None) -> str | None:
        return (v or "").strip() or None

    @field_validator("times")
    @classmethod
    def _times(cls, v: list[str]) -> list[str]:
        if any(not scheduling.is_hhmm(t) for t in v) or len(set(v)) != len(v):
            raise ValueError("times must be distinct HH:MM, 24 h")
        return sorted(v)

    @model_validator(mode="after")
    def _range(self) -> "MedicationIn":
        if self.end_date is not None and self.end_date < self.start_date:
            raise ValueError("end_date before start_date")
        return self


class MedicationOut(BaseModel):
    id: uuid.UUID
    name: str
    amount: str
    times: list[str]
    start_date: date
    end_date: date | None
    instructions: str | None


def _med_out(m: Medication) -> MedicationOut:
    return MedicationOut(
        id=m.id,
        name=m.name,
        amount=m.amount,
        times=list(m.times),
        start_date=m.start_date,
        end_date=m.end_date,
        instructions=m.instructions,
    )


def clinic_patient(db: Session, doctor: DoctorProfile, patient_id: uuid.UUID) -> User:
    """A patient of the clinic: someone with a booked visit, with any doctor.
    Every doctor of the clinic opens their file; anyone else looks unknown.
    [doctor] is the signed-in doctor, kept so callers prove one is signed in."""
    booked = db.scalar(
        select(Appointment.id)
        .where(
            Appointment.patient_id == patient_id,
            Appointment.status != AppointmentStatus.awaiting_payment,
        )
        .limit(1)
    )
    user = db.get(User, patient_id)
    if booked is None or user is None or not user.active:
        raise ApiError(404, "patient_not_found")
    mine = db.scalar(
        select(Appointment.id)
        .where(
            Appointment.patient_id == patient_id,
            Appointment.doctor_id == doctor.user_id,
            Appointment.status != AppointmentStatus.awaiting_payment,
        )
        .limit(1)
    )
    if mine is None:
        # A colleague's patient: keep a trace of who opened the file (ids only).
        audit.record(db, "patient_file.opened", actor_id=doctor.user_id, target=str(patient_id))
        db.commit()
    return user


@staff_router.post("/{patient_id}/medications", response_model=MedicationOut, status_code=201)
def prescribe(
    patient_id: uuid.UUID,
    body: MedicationIn,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> MedicationOut:
    user = clinic_patient(db, doctor, patient_id)
    m = Medication(
        patient_id=user.id,
        prescribed_by=doctor.user_id,
        name=body.name,
        amount=body.amount,
        times=body.times,
        start_date=body.start_date,
        end_date=body.end_date,
        instructions=body.instructions,
    )
    db.add(m)
    db.flush()
    # The audit target is the row id: never the drug name or the dose.
    audit.record(db, "medication.prescribed", actor_id=doctor.user_id, target=str(m.id), request=request)
    db.commit()
    db.refresh(m)
    return _med_out(m)


@staff_router.get("/{patient_id}/medications", response_model=list[MedicationOut])
def list_medications(
    patient_id: uuid.UUID,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> list[MedicationOut]:
    user = clinic_patient(db, doctor, patient_id)
    rows = db.scalars(
        select(Medication)
        .where(Medication.patient_id == user.id, Medication.active.is_(True))
        .order_by(Medication.created_at)
    )
    return [_med_out(m) for m in rows]


@staff_router.delete("/{patient_id}/medications/{medication_id}", status_code=204)
def stop_medication(
    patient_id: uuid.UUID,
    medication_id: uuid.UUID,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> Response:
    """Stops a medicine: it leaves the patient's list, past answers stay."""
    user = clinic_patient(db, doctor, patient_id)
    m = db.get(Medication, medication_id)
    if m is None or m.patient_id != user.id or not m.active:
        raise ApiError(404, "medication_not_found")
    m.active = False
    audit.record(db, "medication.stopped", actor_id=doctor.user_id, target=str(m.id), request=request)
    db.commit()
    return Response(status_code=204)


# --- patient --------------------------------------------------------------


class DoseOut(BaseModel):
    medication_id: uuid.UUID
    name: str
    amount: str
    instruction: str | None
    time: str
    # "due" (not answered yet), "taken", "skipped" or "missed" (a past day
    # with no answer).
    status: Literal["due", "taken", "skipped", "missed"]


class DoseIn(BaseModel):
    medication_id: uuid.UUID
    day: date
    time: str
    status: DoseStatus

    @field_validator("time")
    @classmethod
    def _time(cls, v: str) -> str:
        if not scheduling.is_hhmm(v):
            raise ValueError("time must be HH:MM, 24 h")
        return v


def _dose(m: Medication, time: str, day: date, log: DoseLog | None) -> DoseOut:
    if log is not None:
        status = log.status.value
    else:
        status = "missed" if day < _today() else "due"
    return DoseOut(
        medication_id=m.id,
        name=m.name,
        amount=m.amount,
        instruction=m.instructions,
        time=time,
        status=status,
    )


def _runs_on(m: Medication, day: date) -> bool:
    return m.active and m.start_date <= day and (m.end_date is None or day <= m.end_date)


@router.get("/doses", response_model=list[DoseOut])
def list_doses(
    day: date | None = None,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> list[DoseOut]:
    """The patient's doses for [day] (default: today, clinic time), earliest
    first."""
    day = day or _today()
    meds = [
        m
        for m in db.scalars(select(Medication).where(Medication.patient_id == user.id))
        if _runs_on(m, day)
    ]
    logs = {
        (log.medication_id, log.time): log
        for log in db.scalars(
            select(DoseLog).where(
                DoseLog.day == day, DoseLog.medication_id.in_([m.id for m in meds])
            )
        )
    }
    out = [_dose(m, t, day, logs.get((m.id, t))) for m in meds for t in m.times]
    return sorted(out, key=lambda d: (d.time, d.name))


@router.put("/doses", response_model=DoseOut)
def answer_dose(
    body: DoseIn,
    request: Request,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> DoseOut:
    """Taken or skipped for one dose; answering again replaces the answer."""
    m = db.get(Medication, body.medication_id)
    if m is None or m.patient_id != user.id or not m.active:
        raise ApiError(404, "medication_not_found")
    today = _today()
    if not today - timedelta(days=DAYS_BACK) <= body.day <= today + timedelta(days=DAYS_AHEAD):
        raise ApiError(422, "dose_day_out_of_range")
    if not _runs_on(m, body.day) or body.time not in m.times:
        raise ApiError(422, "dose_not_scheduled")

    def stored() -> DoseLog | None:
        return db.scalar(
            select(DoseLog).where(
                DoseLog.medication_id == m.id, DoseLog.day == body.day, DoseLog.time == body.time
            )
        )

    log = stored()
    inserted = False
    if log is None:
        log, inserted = insert_once(
            db, DoseLog(medication_id=m.id, day=body.day, time=body.time, status=body.status), stored
        )
    if not inserted:  # answering again (or losing the race) replaces the answer
        log.status = body.status
        log.logged_at = clock.now()
    db.commit()
    return _dose(m, body.time, body.day, log)


# --- quote of the day -----------------------------------------------------


class QuoteOut(BaseModel):
    text_ar: str
    text_fr: str


@router.get("/quote", response_model=QuoteOut)
def quote_of_the_day(
    user: User = Depends(patient), db: Session = Depends(get_db)
) -> QuoteOut:
    """One quote per day: the same all day, a new one tomorrow. Quotes made
    for one of the patient's addiction types or for everyone qualify."""
    mine = set(
        db.scalars(
            select(Addiction.type).where(Addiction.patient_id == user.id, Addiction.active.is_(True))
        )
    )
    types = {t.value for t in mine}
    pool = [
        q
        for q in db.scalars(
            select(Quote).where(Quote.active.is_(True)).order_by(Quote.created_at, Quote.id)
        )
        if q.addiction_type is None or q.addiction_type in types
    ]
    if not pool:
        raise ApiError(404, "no_quote")
    q = pool[_today().toordinal() % len(pool)]
    return QuoteOut(text_ar=q.text_ar, text_fr=q.text_fr)
