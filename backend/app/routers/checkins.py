"""Patient daily check and reminder time (PRD 5.4). A patient reaches only
their own days. The server never sees what the reminder says: the phone
schedules it locally, with neutral text."""

import uuid
from datetime import date, timedelta

from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import scheduling
from ..clock import clock
from ..db import get_db, insert_once
from ..errors import ApiError
from ..models import DailyCheck, User
from .recovery import patient

router = APIRouter(prefix="/v1/me", tags=["recovery"])

# The phone's own "today" can be a day ahead of UTC (Algeria is UTC+1) and a
# late tick can arrive the next morning; anything else is a mistake.
DAYS_BACK = 2
DAYS_AHEAD = 1
# How far back the list goes by default (covers the week view and more).
LIST_DAYS = 60



def _today() -> date:
    return scheduling.clinic_today(clock.now())


@router.get("/checkins", response_model=list[date])
def list_checkins(
    since: date | None = None,
    user: User = Depends(patient),
    db: Session = Depends(get_db),
) -> list[date]:
    start = since or _today() - timedelta(days=LIST_DAYS)
    return list(
        db.scalars(
            select(DailyCheck.day)
            .where(DailyCheck.patient_id == user.id, DailyCheck.day >= start)
            .order_by(DailyCheck.day)
        )
    )


@router.put("/checkins/{day}", status_code=204)
def tick(
    day: date, user: User = Depends(patient), db: Session = Depends(get_db)
) -> Response:
    """Ticks [day] as a day without use. Ticking twice changes nothing."""
    today = _today()
    if not today - timedelta(days=DAYS_BACK) <= day <= today + timedelta(days=DAYS_AHEAD):
        raise ApiError(422, "checkin_day_out_of_range")

    def stored() -> uuid.UUID | None:
        return db.scalar(
            select(DailyCheck.id).where(DailyCheck.patient_id == user.id, DailyCheck.day == day)
        )

    if stored() is None:
        insert_once(db, DailyCheck(patient_id=user.id, day=day), stored)
        db.commit()
    return Response(status_code=204)


class ReminderBody(BaseModel):
    # "HH:MM", 24 h, or null to turn the reminder off.
    time: str | None

    @field_validator("time")
    @classmethod
    def _valid(cls, v: str | None) -> str | None:
        if v is not None and not scheduling.is_hhmm(v):
            raise ValueError("time must be HH:MM, 24 h")
        return v


@router.get("/reminder", response_model=ReminderBody)
def read_reminder(user: User = Depends(patient)) -> ReminderBody:
    return ReminderBody(time=user.reminder_time)


@router.put("/reminder", response_model=ReminderBody)
def set_reminder(
    body: ReminderBody, user: User = Depends(patient), db: Session = Depends(get_db)
) -> ReminderBody:
    user.reminder_time = body.time
    db.commit()
    return ReminderBody(time=user.reminder_time)
