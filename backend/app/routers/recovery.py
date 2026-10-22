"""Patient recovery API (PRD 5): the addictions a patient tracks and their
relapses. A patient reaches only their own rows; another patient's id looks
like it does not exist. Tracking does not need the clinic's ID approval
(booking does)."""

import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .. import audit
from ..clock import clock
from ..db import get_db
from ..deps import current_user
from ..errors import ApiError
from ..models import (
    Addiction,
    AddictionType,
    Alert,
    Appointment,
    Relapse,
    ReviewStatus,
    Role,
    User,
)
from .doctors import utc_iso

router = APIRouter(prefix="/v1/me/addictions", tags=["recovery"])

MAX_ADDICTIONS = 10
# A phone's clock can run a little ahead of the server's.
CLOCK_SLACK = timedelta(minutes=5)


def patient(user: User = Depends(current_user)) -> User:
    if user.role != Role.patient:
        raise ApiError(403, "forbidden")
    return user


def _utc(value: datetime) -> datetime:
    """Naive UTC, which is how every timestamp is stored."""
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


class AddictionIn(BaseModel):
    type: AddictionType
    substance: str | None = Field(default=None, max_length=100)
    clean_since: datetime

    @field_validator("substance")
    @classmethod
    def _trim(cls, v: str | None) -> str | None:
        v = (v or "").strip()
        return v or None


class RelapseIn(BaseModel):
    # Defaults to now.
    at: datetime | None = None
    note: str | None = Field(default=None, max_length=500)

    @field_validator("note")
    @classmethod
    def _trim(cls, v: str | None) -> str | None:
        v = (v or "").strip()
        return v or None


class AddictionOut(BaseModel):
    id: uuid.UUID
    type: AddictionType
    substance: str | None
    clean_since: str
    longest_past_days: int
    past_days: int
    review_status: ReviewStatus


def out(a: Addiction) -> AddictionOut:
    return AddictionOut(
        id=a.id,
        type=a.type,
        substance=a.substance,
        clean_since=utc_iso(a.sobriety_start),
        longest_past_days=a.longest_past_days,
        past_days=a.past_days,
        review_status=a.review_status,
    )


def _own(db: Session, user: User, addiction_id: uuid.UUID) -> Addiction:
    a = db.get(Addiction, addiction_id)
    if a is None or a.patient_id != user.id or not a.active:
        raise ApiError(404, "not_found")
    return a


@router.get("", response_model=list[AddictionOut])
def list_addictions(
    user: User = Depends(patient), db: Session = Depends(get_db)
) -> list[AddictionOut]:
    rows = db.scalars(
        select(Addiction)
        .where(
            Addiction.patient_id == user.id,
            Addiction.active.is_(True),
            Addiction.review_status != ReviewStatus.rejected,
        )
        .order_by(Addiction.created_at)
    )
    return [out(a) for a in rows]


@router.post("", response_model=AddictionOut, status_code=201)
def add_addiction(
    body: AddictionIn,
    request: Request,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> AddictionOut:
    """The patient declares an addiction; it stays "pending" until the
    doctor reviews it."""
    start = _utc(body.clean_since)
    if start > clock.now() + CLOCK_SLACK:
        raise ApiError(422, "clean_since_in_future")
    count = db.scalar(
        select(func.count())
        .select_from(Addiction)
        .where(Addiction.patient_id == user.id, Addiction.active.is_(True))
    )
    if count >= MAX_ADDICTIONS:
        raise ApiError(409, "too_many_addictions")
    a = Addiction(
        patient_id=user.id, type=body.type, substance=body.substance, sobriety_start=start
    )
    db.add(a)
    db.flush()
    # The audit target is the row id only: never the type, product or note.
    audit.record(db, "addiction.added", actor_id=user.id, target=str(a.id), request=request)
    db.commit()
    db.refresh(a)
    return out(a)


@router.post("/{addiction_id}/relapses", response_model=AddictionOut, status_code=201)
def log_relapse(
    addiction_id: uuid.UUID,
    body: RelapseIn,
    request: Request,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> AddictionOut:
    """Restarts the counter at the relapse time, keeping the past streaks
    (PRD 5.1), and tells the patient's doctor (PRD 12.3)."""
    a = _own(db, user, addiction_id)
    now = clock.now()
    at = _utc(body.at) if body.at is not None else now
    if at > now + CLOCK_SLACK:
        raise ApiError(422, "relapse_in_future")
    if at < a.sobriety_start:
        raise ApiError(422, "relapse_before_start")
    streak = (at - a.sobriety_start).days
    a.past_days += streak
    a.longest_past_days = max(a.longest_past_days, streak)
    a.sobriety_start = at
    db.add(Relapse(addiction_id=a.id, occurred_at=at, note=body.note))
    doctor_id = _doctor_of(db, user.id)
    if doctor_id is not None:
        db.add(Alert(doctor_id=doctor_id, patient_id=user.id, type="relapse", priority="high"))
    audit.record(db, "relapse.logged", actor_id=user.id, target=str(a.id), request=request)
    db.commit()
    db.refresh(a)
    return out(a)


def _doctor_of(db: Session, patient_id: uuid.UUID) -> uuid.UUID | None:
    """The doctor the patient last booked with. Patients have no other link
    to a doctor yet; with none, nobody is alerted."""
    return db.scalar(
        select(Appointment.doctor_id)
        .where(Appointment.patient_id == patient_id)
        .order_by(Appointment.start_utc.desc())
        .limit(1)
    )
