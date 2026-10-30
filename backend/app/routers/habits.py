"""Good habits (PRD 5.6): the patient keeps up to five, ticks each one done
once a day and may set a daily reminder the phone schedules itself. A
patient reaches only their own habits; a doctor sees their own patients'
habits as days done out of the last 30."""

import uuid
from datetime import date, timedelta

from fastapi import APIRouter, Depends, Query, Request, Response
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .. import audit, scheduling
from ..clock import clock
from ..db import get_db, insert_once
from ..errors import ApiError
from ..habits import HABITS
from ..models import DoctorProfile, Habit, HabitKind, HabitLog, User
from .addiction_checks import TextOut, _text
from .checkins import DAYS_AHEAD, DAYS_BACK, LIST_DAYS
from .medications import clinic_patient
from .recovery import patient
from .staff import current_doctor

router = APIRouter(prefix="/v1/me/habits", tags=["recovery"])
staff_router = APIRouter(prefix="/v1/staff", tags=["staff"])

MAX_HABITS = 5
SUMMARY_DAYS = 30


def _valid_time(v: str | None) -> str | None:
    if v is not None and not scheduling.is_hhmm(v):
        raise ValueError("time must be HH:MM, 24 h")
    return v


class CatalogItem(BaseModel):
    kind: HabitKind
    label: TextOut


class HabitIn(BaseModel):
    kind: HabitKind
    # Only for "custom": the patient's own words.
    text: str | None = Field(default=None, max_length=60)
    reminder_time: str | None = None

    @field_validator("text")
    @classmethod
    def _trim(cls, v: str | None) -> str | None:
        v = (v or "").strip()
        return v or None

    @field_validator("reminder_time")
    @classmethod
    def _time(cls, v: str | None) -> str | None:
        return _valid_time(v)

    @model_validator(mode="after")
    def _text_only_for_custom(self) -> "HabitIn":
        if (self.kind == HabitKind.custom) != (self.text is not None):
            raise ValueError("text is required for a custom habit, and only for one")
        return self


class ReminderIn(BaseModel):
    # "HH:MM", 24 h, or null to turn the reminder off.
    time: str | None

    @field_validator("time")
    @classmethod
    def _time(cls, v: str | None) -> str | None:
        return _valid_time(v)


class HabitOut(BaseModel):
    id: uuid.UUID
    kind: HabitKind
    text: str | None
    reminder_time: str | None
    # Days it was done, over the last LIST_DAYS days.
    days: list[date]


def _today() -> date:
    return scheduling.clinic_today(clock.now())


def _days(db: Session, habit_id: uuid.UUID, since: date) -> list[date]:
    return list(
        db.scalars(
            select(HabitLog.day)
            .where(HabitLog.habit_id == habit_id, HabitLog.day >= since)
            .order_by(HabitLog.day)
        )
    )


def _out(db: Session, h: Habit) -> HabitOut:
    return HabitOut(
        id=h.id,
        kind=h.kind,
        text=h.text,
        reminder_time=h.reminder_time,
        days=_days(db, h.id, _today() - timedelta(days=LIST_DAYS)),
    )


def _own(db: Session, user: User, habit_id: uuid.UUID) -> Habit:
    h = db.get(Habit, habit_id)
    if h is None or h.patient_id != user.id or not h.active:
        raise ApiError(404, "not_found")
    return h


def _active(db: Session, patient_id: uuid.UUID) -> list[Habit]:
    return list(
        db.scalars(
            select(Habit)
            .where(Habit.patient_id == patient_id, Habit.active.is_(True))
            .order_by(Habit.created_at)
        )
    )


@router.get("/catalog", response_model=list[CatalogItem])
def catalog(user: User = Depends(patient)) -> list[CatalogItem]:
    return [CatalogItem(kind=k, label=_text(t)) for k, t in HABITS.items()]


@router.get("", response_model=list[HabitOut])
def list_habits(user: User = Depends(patient), db: Session = Depends(get_db)) -> list[HabitOut]:
    return [_out(db, h) for h in _active(db, user.id)]


@router.post("", response_model=HabitOut, status_code=201)
def add_habit(
    body: HabitIn,
    request: Request,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> HabitOut:
    active = _active(db, user.id)
    if len(active) >= MAX_HABITS:
        raise ApiError(409, "too_many_habits")
    if body.kind != HabitKind.custom and any(h.kind == body.kind for h in active):
        raise ApiError(409, "habit_exists")
    h = Habit(patient_id=user.id, kind=body.kind, text=body.text, reminder_time=body.reminder_time)
    db.add(h)
    db.flush()
    audit.record(db, "habit.added", actor_id=user.id, target=str(h.id), request=request)
    db.commit()
    db.refresh(h)
    return _out(db, h)


@router.put("/{habit_id}/reminder", response_model=HabitOut)
def set_reminder(
    habit_id: uuid.UUID,
    body: ReminderIn,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> HabitOut:
    h = _own(db, user, habit_id)
    h.reminder_time = body.time
    db.commit()
    return _out(db, h)


@router.delete("/{habit_id}", status_code=204)
def remove_habit(
    habit_id: uuid.UUID,
    request: Request,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> Response:
    """Stops the habit; the days it was done stay for the doctor's summary."""
    h = _own(db, user, habit_id)
    h.active = False
    audit.record(db, "habit.removed", actor_id=user.id, target=str(h.id), request=request)
    db.commit()
    return Response(status_code=204)


def _check_day(day: date) -> None:
    today = _today()
    if not today - timedelta(days=DAYS_BACK) <= day <= today + timedelta(days=DAYS_AHEAD):
        raise ApiError(422, "checkin_day_out_of_range")


@router.put("/{habit_id}/days/{day}", status_code=204)
def mark_done(
    habit_id: uuid.UUID, day: date, user: User = Depends(patient), db: Session = Depends(get_db)
) -> Response:
    """Ticks the habit done for [day]; ticking twice changes nothing."""
    h = _own(db, user, habit_id)
    _check_day(day)

    def stored() -> uuid.UUID | None:
        return db.scalar(select(HabitLog.id).where(HabitLog.habit_id == h.id, HabitLog.day == day))

    if stored() is None:
        insert_once(db, HabitLog(habit_id=h.id, day=day), stored)
        db.commit()
    return Response(status_code=204)


@router.delete("/{habit_id}/days/{day}", status_code=204)
def unmark_done(
    habit_id: uuid.UUID, day: date, user: User = Depends(patient), db: Session = Depends(get_db)
) -> Response:
    """Undoes a tick made by mistake, within the same recent days."""
    h = _own(db, user, habit_id)
    _check_day(day)
    log = db.scalar(select(HabitLog).where(HabitLog.habit_id == h.id, HabitLog.day == day))
    if log is not None:
        db.delete(log)
        db.commit()
    return Response(status_code=204)


# --- Doctor -----------------------------------------------------------------


class HabitSummaryOut(BaseModel):
    id: uuid.UUID
    kind: HabitKind
    text: str | None
    days: int
    done_days: int


@staff_router.get("/patients/{patient_id}/habits", response_model=list[HabitSummaryOut])
def patient_habits(
    patient_id: uuid.UUID,
    days: int = Query(default=SUMMARY_DAYS, ge=1, le=90),
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> list[HabitSummaryOut]:
    """Each active habit with the days it was done in the last [days]."""
    user = clinic_patient(db, doctor, patient_id)
    today = _today()
    start = today - timedelta(days=days - 1)
    result = []
    for h in _active(db, user.id):
        done = db.scalar(
            select(func.count())
            .select_from(HabitLog)
            .where(HabitLog.habit_id == h.id, HabitLog.day >= start, HabitLog.day <= today)
        )
        result.append(HabitSummaryOut(id=h.id, kind=h.kind, text=h.text, days=days, done_days=done))
    return result
