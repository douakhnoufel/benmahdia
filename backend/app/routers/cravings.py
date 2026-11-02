"""Difficult moments (urge surfing): the patient opens the screen at a
craving, rates it 1-10 and may name what is behind it (HALT: hungry, angry,
lonely, tired); once it has passed they rate it again. A patient reaches only
their own moments; every doctor of the clinic reads a clinic patient's
numbers. No free text is stored, and the audit lines carry ids only."""

import uuid
from datetime import datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit
from ..clock import clock
from ..db import get_db
from ..errors import ApiError
from ..models import CravingLog, DoctorProfile, User
from .medications import clinic_patient
from .recovery import patient
from .staff import current_doctor

router = APIRouter(prefix="/v1/me/cravings", tags=["recovery"])
staff_router = APIRouter(prefix="/v1/staff", tags=["staff"])

HaltKey = Literal["hungry", "angry", "lonely", "tired"]
LIST_DAYS = 30
MAX_ROWS = 200


class CravingIn(BaseModel):
    intensity_before: int = Field(ge=1, le=10)
    halt: list[HaltKey] = Field(default_factory=list, max_length=4)

    @field_validator("halt")
    @classmethod
    def _unique(cls, v: list[str]) -> list[str]:
        return list(dict.fromkeys(v))


class PassedIn(BaseModel):
    intensity_after: int = Field(ge=1, le=10)


class CravingOut(BaseModel):
    id: uuid.UUID
    intensity_before: int
    intensity_after: int | None
    halt: list[str]
    created_at: datetime
    passed_at: datetime | None


def _out(c: CravingLog) -> CravingOut:
    return CravingOut(
        id=c.id,
        intensity_before=c.intensity_before,
        intensity_after=c.intensity_after,
        halt=list(c.halt or []),
        created_at=c.created_at,
        passed_at=c.passed_at,
    )


def _recent(db: Session, patient_id: uuid.UUID, days: int) -> list[CravingOut]:
    since = clock.now() - timedelta(days=days)
    rows = db.scalars(
        select(CravingLog)
        .where(CravingLog.patient_id == patient_id, CravingLog.created_at >= since)
        .order_by(CravingLog.created_at.desc())
        .limit(MAX_ROWS)
    )
    return [_out(c) for c in rows]


@router.post("", response_model=CravingOut, status_code=201)
def start(
    body: CravingIn,
    request: Request,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> CravingOut:
    c = CravingLog(
        patient_id=user.id,
        intensity_before=body.intensity_before,
        halt=body.halt,
    )
    db.add(c)
    db.flush()
    audit.record(db, "craving.started", actor_id=user.id, target=str(c.id), request=request)
    db.commit()
    db.refresh(c)
    return _out(c)


@router.post("/{craving_id}/passed", response_model=CravingOut)
def passed(
    craving_id: uuid.UUID,
    body: PassedIn,
    request: Request,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> CravingOut:
    c = db.get(CravingLog, craving_id)
    if c is None or c.patient_id != user.id:
        raise ApiError(404, "not_found")
    if c.passed_at is not None:
        raise ApiError(409, "craving_already_passed")
    c.intensity_after = body.intensity_after
    c.passed_at = clock.now()
    audit.record(db, "craving.passed", actor_id=user.id, target=str(c.id), request=request)
    db.commit()
    db.refresh(c)
    return _out(c)


@router.get("", response_model=list[CravingOut])
def mine(
    days: int = Query(default=LIST_DAYS, ge=1, le=90),
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> list[CravingOut]:
    return _recent(db, user.id, days)


@staff_router.get("/patients/{patient_id}/cravings", response_model=list[CravingOut])
def patient_cravings(
    patient_id: uuid.UUID,
    days: int = Query(default=LIST_DAYS, ge=1, le=90),
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> list[CravingOut]:
    user = clinic_patient(db, doctor, patient_id)
    return _recent(db, user.id, days)
