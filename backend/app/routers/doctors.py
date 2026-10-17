import uuid
from datetime import timedelta
from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import scheduling
from ..clock import clock
from ..config import get_settings
from ..db import get_db
from ..deps import verified_patient
from ..errors import ApiError
from ..models import (
    Appointment,
    Availability,
    AvailabilityException,
    DoctorProfile,
    User,
)

router = APIRouter(prefix="/v1/doctors", tags=["doctors"])


class DoctorOut(BaseModel):
    id: uuid.UUID
    name_ar: str
    name_fr: str
    slot_minutes: int
    price_dzd: int
    notice_hours: int
    hold_minutes: int
    horizon_days: int


class SlotOut(BaseModel):
    # UTC; the app shows it in Africa/Algiers.
    start: str
    free: bool


class DayOut(BaseModel):
    # Clinic calendar day, e.g. 2026-10-18.
    day: str
    closure: Literal["none", "too_soon", "closed"]
    slots: list[SlotOut]


class CalendarOut(BaseModel):
    doctor_id: uuid.UUID
    days: list[DayOut]


def utc_iso(value) -> str:
    return value.isoformat(timespec="seconds") + "Z"


def doctor_out(profile: DoctorProfile) -> DoctorOut:
    return DoctorOut(
        id=profile.user_id,
        name_ar=profile.name_ar,
        name_fr=profile.name_fr,
        slot_minutes=profile.slot_minutes,
        price_dzd=profile.price_dzd,
        notice_hours=profile.notice_hours,
        hold_minutes=profile.hold_minutes,
        horizon_days=get_settings().booking_horizon_days,
    )


@router.get("", response_model=list[DoctorOut])
def list_doctors(
    _: User = Depends(verified_patient), db: Session = Depends(get_db)
) -> list[DoctorOut]:
    profiles = db.scalars(select(DoctorProfile).order_by(DoctorProfile.name_fr)).all()
    return [doctor_out(p) for p in profiles]


@router.get("/{doctor_id}/calendar", response_model=CalendarOut)
def calendar(
    doctor_id: uuid.UUID,
    _: User = Depends(verified_patient),
    db: Session = Depends(get_db),
) -> CalendarOut:
    """The bookable days from today until the horizon (PRD 4.3)."""
    profile = db.get(DoctorProfile, doctor_id)
    if profile is None:
        raise ApiError(404, "doctor_not_found")
    now = clock.now()
    today = scheduling.clinic_today(now)
    horizon = get_settings().booking_horizon_days
    first = scheduling.to_utc(today, 0)
    last = scheduling.to_utc(today + timedelta(days=horizon), 0)
    windows = list(db.scalars(select(Availability).where(Availability.doctor_id == doctor_id)))
    blocked = scheduling.blocked_set(
        list(db.scalars(select(AvailabilityException).where(AvailabilityException.doctor_id == doctor_id)))
    )
    taken = list(
        db.scalars(
            select(Appointment).where(
                Appointment.doctor_id == doctor_id,
                Appointment.start_utc >= first,
                Appointment.start_utc < last,
            )
        )
    )
    days = []
    for i in range(horizon):
        view = scheduling.build_day(profile, windows, blocked, taken, today + timedelta(days=i), now)
        days.append(
            DayOut(
                day=view.day.isoformat(),
                closure=view.closure,
                slots=[SlotOut(start=utc_iso(s.start), free=s.free) for s in view.slots],
            )
        )
    return CalendarOut(doctor_id=doctor_id, days=days)
