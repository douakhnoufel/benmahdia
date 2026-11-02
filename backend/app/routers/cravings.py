"""Difficult moments (habit-tracking design, step 1): the patient logs how
strong a craving is when it starts (1–10) and which HALT triggers are behind
it, then how strong it is once it has passed. A patient reaches only their own
logs; every doctor of the clinic sees a clinic patient's logs (PRD 3), and
opening a colleague's patient is audited. No free text is stored."""

import uuid
from datetime import timedelta
from enum import Enum

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..clock import clock
from ..db import get_db
from ..errors import ApiError
from ..models import CravingLog, DoctorProfile, User
from .doctors import utc_iso
from .medications import clinic_patient
from .recovery import patient
from .staff import current_doctor

router = APIRouter(prefix="/v1/me/cravings", tags=["recovery"])
staff_router = APIRouter(prefix="/v1/staff", tags=["staff"])

LIST_DAYS = 30


class Trigger(str, Enum):
    hungry = "hungry"
    angry = "angry"
    lonely = "lonely"
    tired = "tired"
    other = "other"


class CravingIn(BaseModel):
    intensity: int = Field(ge=1, le=10)
    triggers: list[Trigger] = Field(default_factory=list, max_length=5)

    @field_validator("triggers")
    @classmethod
    def _unique(cls, v: list[Trigger]) -> list[Trigger]:
        return list(dict.fromkeys(v))


class PassedIn(BaseModel):
    intensity: int = Field(ge=1, le=10)


class CravingOut(BaseModel):
    id: uuid.UUID
    started_at: str
    intensity_before: int
    triggers: list[Trigger]
    passed_at: str | None
    intensity_after: int | None


def _out(c: CravingLog) -> CravingOut:
    return CravingOut(
        id=c.id,
        started_at=utc_iso(c.started_at),
        intensity_before=c.intensity_before,
        triggers=[Trigger(t) for t in c.triggers],
        passed_at=utc_iso(c.passed_at) if c.passed_at else None,
        intensity_after=c.intensity_after,
    )


def _recent(db: Session, patient_id: uuid.UUID, days: int) -> list[CravingOut]:
    since = clock.now() - timedelta(days=days)
    rows = db.scalars(
        select(CravingLog)
        .where(CravingLog.patient_id == patient_id, CravingLog.started_at >= since)
        .order_by(CravingLog.started_at.desc())
    )
    return [_out(c) for c in rows]


@router.post("", response_model=CravingOut, status_code=201)
def start(
    body: CravingIn, user: User = Depends(patient), db: Session = Depends(get_db)
) -> CravingOut:
    c = CravingLog(
        patient_id=user.id,
        started_at=clock.now(),
        intensity_before=body.intensity,
        triggers=[t.value for t in body.triggers],
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    return _out(c)


@router.patch("/{craving_id}", response_model=CravingOut)
def passed(
    craving_id: uuid.UUID,
    body: PassedIn,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> CravingOut:
    """The craving has passed: records how strong it is now. Once only."""
    c = db.get(CravingLog, craving_id)
    if c is None or c.patient_id != user.id:
        raise ApiError(404, "not_found")
    if c.passed_at is not None:
        raise ApiError(409, "craving_already_passed")
    c.passed_at = clock.now()
    c.intensity_after = body.intensity
    db.commit()
    return _out(c)


@router.get("", response_model=list[CravingOut])
def mine(
    days: int = Query(default=LIST_DAYS, ge=1, le=90),
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> list[CravingOut]:
    """The patient's own difficult moments over the last [days], newest first."""
    return _recent(db, user.id, days)


@staff_router.get("/patients/{patient_id}/cravings", response_model=list[CravingOut])
def patient_cravings(
    patient_id: uuid.UUID,
    days: int = Query(default=LIST_DAYS, ge=1, le=90),
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> list[CravingOut]:
    """A clinic patient's difficult moments over the last [days], newest first."""
    user = clinic_patient(db, doctor, patient_id)
    return _recent(db, user.id, days)
