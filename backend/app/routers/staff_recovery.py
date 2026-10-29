"""What a doctor sees of their patients' recovery (PRD 7): the addictions a
patient entered, to confirm or reject (PRD 3), and the alerts raised for
them. Every doctor of the clinic reaches every clinic patient (someone with
a booked visit) and every alert; anyone else looks unknown. Alerts carry a kind of event
and a patient, never medical content."""

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit
from ..clock import clock
from ..db import get_db
from ..errors import ApiError
from ..models import Addiction, Alert, DoctorProfile, Relapse, ReviewStatus, User
from .doctors import utc_iso
from .medications import clinic_patient
from .recovery import AddictionOut, out
from .staff import current_doctor

router = APIRouter(prefix="/v1/staff", tags=["staff"])


class RelapseOut(BaseModel):
    at: str
    note: str | None


class StaffAddictionOut(AddictionOut):
    relapses: list[RelapseOut]


class AlertOut(BaseModel):
    id: uuid.UUID
    patient_id: uuid.UUID
    patient_phone: str | None
    type: str
    priority: str
    read: bool
    created_at: str


def _addiction_out(db: Session, a: Addiction) -> StaffAddictionOut:
    relapses = db.scalars(
        select(Relapse).where(Relapse.addiction_id == a.id).order_by(Relapse.occurred_at)
    )
    return StaffAddictionOut(
        **out(a).model_dump(),
        relapses=[RelapseOut(at=utc_iso(r.occurred_at), note=r.note) for r in relapses],
    )


@router.get("/patients/{patient_id}/addictions", response_model=list[StaffAddictionOut])
def patient_addictions(
    patient_id: uuid.UUID,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> list[StaffAddictionOut]:
    user = clinic_patient(db, doctor, patient_id)
    rows = db.scalars(
        select(Addiction)
        .where(Addiction.patient_id == user.id, Addiction.active.is_(True))
        .order_by(Addiction.created_at)
    )
    return [_addiction_out(db, a) for a in rows]


def _review(
    db: Session,
    request: Request,
    doctor: DoctorProfile,
    patient_id: uuid.UUID,
    addiction_id: uuid.UUID,
    status: ReviewStatus,
) -> StaffAddictionOut:
    user = clinic_patient(db, doctor, patient_id)
    a = db.get(Addiction, addiction_id)
    if a is None or a.patient_id != user.id or not a.active:
        raise ApiError(404, "addiction_not_found")
    a.review_status = status
    a.reviewed_at = clock.now()
    a.reviewed_by = doctor.user_id
    audit.record(db, f"addiction.{status.value}", actor_id=doctor.user_id, target=str(a.id), request=request)
    db.commit()
    db.refresh(a)
    return _addiction_out(db, a)


@router.post("/patients/{patient_id}/addictions/{addiction_id}/confirm", response_model=StaffAddictionOut)
def confirm_addiction(
    patient_id: uuid.UUID,
    addiction_id: uuid.UUID,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> StaffAddictionOut:
    return _review(db, request, doctor, patient_id, addiction_id, ReviewStatus.confirmed)


@router.post("/patients/{patient_id}/addictions/{addiction_id}/reject", response_model=StaffAddictionOut)
def reject_addiction(
    patient_id: uuid.UUID,
    addiction_id: uuid.UUID,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> StaffAddictionOut:
    return _review(db, request, doctor, patient_id, addiction_id, ReviewStatus.rejected)


def _alert_out(db: Session, alert: Alert) -> AlertOut:
    patient = db.get(User, alert.patient_id)
    return AlertOut(
        id=alert.id,
        patient_id=alert.patient_id,
        patient_phone=patient.phone if patient else None,
        type=alert.type,
        priority=alert.priority,
        read=alert.read,
        created_at=utc_iso(alert.created_at),
    )


@router.get("/alerts", response_model=list[AlertOut])
def alerts(
    unread: bool = False,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> list[AlertOut]:
    """The clinic's alerts, newest first: every doctor sees every alert."""
    query = select(Alert)
    if unread:
        query = query.where(Alert.read.is_(False))
    return [_alert_out(db, a) for a in db.scalars(query.order_by(Alert.created_at.desc()))]


@router.post("/alerts/{alert_id}/read", response_model=AlertOut)
def mark_read(
    alert_id: uuid.UUID,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> AlertOut:
    alert = db.get(Alert, alert_id)
    if alert is None:
        raise ApiError(404, "alert_not_found")
    alert.read = True
    db.commit()
    return _alert_out(db, alert)
