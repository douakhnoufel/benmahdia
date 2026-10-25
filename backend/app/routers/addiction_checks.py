"""Per-substance tracking (PRD 5.6): the profile catalog, the patient's daily
check for each addiction (used or not, craving, the profile's two signals),
and what the doctor sees of those checks. A patient reaches only their own
addictions; a doctor only their own patients' (anyone else looks unknown).
Answers never go to logs, alerts or the audit log."""

import uuid
from datetime import date, timedelta

from fastapi import APIRouter, Depends, Query, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit
from ..clock import clock
from ..db import get_db
from ..errors import ApiError
from ..models import (
    Addiction,
    AddictionCheck,
    AddictionType,
    DoctorProfile,
    ReviewStatus,
    SubstanceProfile,
    User,
)
from ..substances import PROFILES, SIGNALS, Text, signals_of
from .checkins import DAYS_AHEAD, DAYS_BACK, LIST_DAYS
from .medications import _own_patient
from .recovery import _own, patient
from .staff import current_doctor
from .staff_recovery import StaffAddictionOut, _addiction_out

router = APIRouter(prefix="/v1/me", tags=["recovery"])
staff_router = APIRouter(prefix="/v1/staff", tags=["staff"])

MAX_CHART_DAYS = 90


class TextOut(BaseModel):
    ar: str
    fr: str


class SignalOut(BaseModel):
    key: str
    label: TextOut


class NoteOut(BaseModel):
    day: int
    text: TextOut


class ProfileOut(BaseModel):
    key: SubstanceProfile
    type: AddictionType
    name: TextOut
    signals: list[SignalOut]
    notes: list[NoteOut]


def _text(t: Text) -> TextOut:
    return TextOut(ar=t.ar, fr=t.fr)


def _profiles() -> list[ProfileOut]:
    return [
        ProfileOut(
            key=p.key,
            type=p.type,
            name=_text(p.name),
            signals=[SignalOut(key=k, label=_text(SIGNALS[k])) for k in p.signals],
            notes=[NoteOut(day=n.day, text=_text(n.text)) for n in p.notes],
        )
        for p in PROFILES.values()
    ]


class CheckIn(BaseModel):
    used: bool
    craving: int = Field(ge=1, le=5)
    signals: dict[str, int] = Field(default_factory=dict)


class CheckOut(BaseModel):
    addiction_id: uuid.UUID
    day: date
    used: bool
    craving: int
    signals: dict[str, int]


class ChecksOut(BaseModel):
    checks: list[CheckOut]
    # Days on which every addiction the patient tracked then was checked
    # (the home's week strip, PRD 5.4).
    done_days: list[date]


def _check_out(c: AddictionCheck) -> CheckOut:
    return CheckOut(
        addiction_id=c.addiction_id, day=c.day, used=c.used, craving=c.craving, signals=c.signals
    )


def _today() -> date:
    return clock.now().date()


def _tracked(db: Session, patient_id: uuid.UUID) -> list[Addiction]:
    return list(
        db.scalars(
            select(Addiction).where(
                Addiction.patient_id == patient_id,
                Addiction.active.is_(True),
                Addiction.review_status != ReviewStatus.rejected,
            )
        )
    )


@router.get("/recovery/profiles", response_model=list[ProfileOut])
def profiles(user: User = Depends(patient)) -> list[ProfileOut]:
    return _profiles()


@router.put("/addictions/{addiction_id}/checks/{day}", status_code=204)
def save_check(
    addiction_id: uuid.UUID,
    day: date,
    body: CheckIn,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> Response:
    """Saves [day]'s check for one addiction. It can be changed again the day
    it was first saved. "Used" does not restart the counter by itself: the app
    then opens relapse logging (PRD 5.1)."""
    a = _own(db, user, addiction_id)
    if a.review_status == ReviewStatus.rejected:
        raise ApiError(404, "not_found")
    today = _today()
    if not today - timedelta(days=DAYS_BACK) <= day <= today + timedelta(days=DAYS_AHEAD):
        raise ApiError(422, "checkin_day_out_of_range")
    expected = signals_of(a.profile)
    if set(body.signals) != set(expected) or any(not 1 <= v <= 5 for v in body.signals.values()):
        raise ApiError(422, "signals_mismatch")
    now = clock.now()
    check = db.scalar(
        select(AddictionCheck).where(
            AddictionCheck.addiction_id == a.id, AddictionCheck.day == day
        )
    )
    if check is None:
        check = AddictionCheck(addiction_id=a.id, day=day, created_at=now)
        db.add(check)
    elif check.created_at.date() != now.date():
        raise ApiError(409, "check_locked")
    check.used = body.used
    check.craving = body.craving
    check.signals = dict(body.signals)
    check.updated_at = now
    db.commit()
    return Response(status_code=204)


@router.get("/addiction-checks", response_model=ChecksOut)
def list_checks(
    since: date | None = None,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> ChecksOut:
    today = _today()
    start = since or today - timedelta(days=LIST_DAYS)
    tracked = _tracked(db, user.id)
    rows = (
        list(
            db.scalars(
                select(AddictionCheck)
                .where(
                    AddictionCheck.addiction_id.in_([a.id for a in tracked]),
                    AddictionCheck.day >= start,
                )
                .order_by(AddictionCheck.day)
            )
        )
        if tracked
        else []
    )
    checked: dict[date, set[uuid.UUID]] = {}
    for c in rows:
        checked.setdefault(c.day, set()).add(c.addiction_id)
    done = []
    for day, ids in sorted(checked.items()):
        due = {a.id for a in tracked if a.created_at.date() <= day}
        if due <= ids:
            done.append(day)
    return ChecksOut(checks=[_check_out(c) for c in rows], done_days=done)


# --- Doctor -----------------------------------------------------------------


class ChartOut(BaseModel):
    days: int
    checked_days: int
    checks: list[CheckOut]


class ProfileIn(BaseModel):
    # None goes back to generic tracking (the type stays).
    profile: SubstanceProfile | None


def _patient_addiction(
    db: Session, doctor: DoctorProfile, patient_id: uuid.UUID, addiction_id: uuid.UUID
) -> Addiction:
    user = _own_patient(db, doctor, patient_id)
    a = db.get(Addiction, addiction_id)
    if a is None or a.patient_id != user.id or not a.active:
        raise ApiError(404, "addiction_not_found")
    return a


@staff_router.get("/recovery/profiles", response_model=list[ProfileOut])
def staff_profiles(doctor: DoctorProfile = Depends(current_doctor)) -> list[ProfileOut]:
    return _profiles()


@staff_router.put(
    "/patients/{patient_id}/addictions/{addiction_id}/profile", response_model=StaffAddictionOut
)
def set_profile(
    patient_id: uuid.UUID,
    addiction_id: uuid.UUID,
    body: ProfileIn,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> StaffAddictionOut:
    """The doctor corrects the profile the patient chose (PRD 3); it also
    sets the type. Past checks keep the signals they were answered with."""
    a = _patient_addiction(db, doctor, patient_id, addiction_id)
    a.profile = body.profile
    if body.profile is not None:
        a.type = PROFILES[body.profile].type
    audit.record(db, "addiction.profile_set", actor_id=doctor.user_id, target=str(a.id), request=request)
    db.commit()
    db.refresh(a)
    return _addiction_out(db, a)


@staff_router.get(
    "/patients/{patient_id}/addictions/{addiction_id}/checks", response_model=ChartOut
)
def patient_checks(
    patient_id: uuid.UUID,
    addiction_id: uuid.UUID,
    days: int = Query(default=30, ge=1, le=MAX_CHART_DAYS),
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> ChartOut:
    """The last [days] days of checks for one addiction (PRD 5.6, 7): the
    craving and signals chart and how many of those days were checked."""
    a = _patient_addiction(db, doctor, patient_id, addiction_id)
    today = _today()
    start = today - timedelta(days=days - 1)
    rows = list(
        db.scalars(
            select(AddictionCheck)
            .where(
                AddictionCheck.addiction_id == a.id,
                AddictionCheck.day >= start,
                AddictionCheck.day <= today,
            )
            .order_by(AddictionCheck.day)
        )
    )
    return ChartOut(days=days, checked_days=len(rows), checks=[_check_out(c) for c in rows])
