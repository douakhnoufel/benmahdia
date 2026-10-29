"""A doctor's own consultation hours (PRD 4.3, 7): weekly windows (breaks are
the gaps between them), slot length, booking notice and blocked days.

A change never moves or cancels a booked visit. Every answer lists the
upcoming confirmed visits that fall outside the hours or on a blocked day, so
the clinic can call those patients. Writes lock the doctor's row like a hold
does, so no patient can hold a slot while the hours are being replaced."""

import uuid
from datetime import date, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .. import audit, scheduling
from ..clock import clock
from ..db import get_db
from ..errors import ApiError
from ..models import (
    Appointment,
    AppointmentStatus,
    Availability,
    AvailabilityException,
    DoctorProfile,
    User,
)
from .doctors import utc_iso
from .staff import current_doctor

router = APIRouter(prefix="/v1/staff/availability", tags=["staff"])

MAX_WINDOWS_PER_DAY = 6
# Times are picked on a 5-minute grid, the shortest slot length.
GRID_MINUTES = 5
MAX_NOTICE_HOURS = 168
# Blocked days can be set up to a year ahead.
MAX_BLOCK_AHEAD_DAYS = 366


class Window(BaseModel):
    # Monday = 0 ... Sunday = 6. Minutes after midnight, clinic time.
    weekday: int = Field(ge=0, le=6)
    start_minute: int = Field(ge=0, le=1440)
    end_minute: int = Field(ge=0, le=1440)


class WindowsIn(BaseModel):
    windows: list[Window] = Field(max_length=7 * MAX_WINDOWS_PER_DAY)


class SettingsIn(BaseModel):
    slot_minutes: Literal[5, 10, 15]
    notice_hours: int = Field(ge=0, le=MAX_NOTICE_HOURS)


class BlockIn(BaseModel):
    day: date
    reason: str | None = Field(default=None, max_length=120)


class BlockedDayOut(BaseModel):
    id: uuid.UUID
    day: str
    reason: str | None


class ConflictOut(BaseModel):
    """A booked visit the current hours no longer cover. Booking data only."""

    appointment_id: uuid.UUID
    start: str
    patient_phone: str | None
    reason: Literal["blocked_day", "outside_hours"]


class AvailabilityOut(BaseModel):
    slot_minutes: int
    notice_hours: int
    windows: list[Window]
    # From today on, soonest first.
    blocked_days: list[BlockedDayOut]
    conflicts: list[ConflictOut]


def _locked(db: Session, doctor: DoctorProfile) -> DoctorProfile:
    """The doctor's row, locked on PostgreSQL until the commit."""
    return db.scalar(
        select(DoctorProfile).where(DoctorProfile.user_id == doctor.user_id).with_for_update()
    )


def _conflicts(
    db: Session, doctor_id: uuid.UUID, windows: list[Availability], blocked: set[date]
) -> list[ConflictOut]:
    rows = db.scalars(
        select(Appointment)
        .where(
            Appointment.doctor_id == doctor_id,
            Appointment.status == AppointmentStatus.confirmed,
            Appointment.start_utc >= clock.now(),
        )
        .order_by(Appointment.start_utc)
    )
    out = []
    for a in rows:
        local = a.start_utc.replace(tzinfo=timezone.utc).astimezone(scheduling.CLINIC_TZ)
        start = local.hour * 60 + local.minute
        end = start + int((a.end_utc - a.start_utc).total_seconds() // 60)
        if local.date() in blocked:
            reason = "blocked_day"
        elif not any(
            w.weekday == local.weekday() and w.start_minute <= start and end <= w.end_minute
            for w in windows
        ):
            reason = "outside_hours"
        else:
            continue
        patient = db.get(User, a.patient_id)
        out.append(
            ConflictOut(
                appointment_id=a.id,
                start=utc_iso(a.start_utc),
                patient_phone=patient.phone if patient else None,
                reason=reason,
            )
        )
    return out


def _state(db: Session, profile: DoctorProfile) -> AvailabilityOut:
    windows = list(
        db.scalars(
            select(Availability)
            .where(Availability.doctor_id == profile.user_id)
            .order_by(Availability.weekday, Availability.start_minute)
        )
    )
    exceptions = list(
        db.scalars(
            select(AvailabilityException)
            .where(AvailabilityException.doctor_id == profile.user_id)
            .order_by(AvailabilityException.day)
        )
    )
    today = scheduling.clinic_today(clock.now())
    return AvailabilityOut(
        slot_minutes=profile.slot_minutes,
        notice_hours=profile.notice_hours,
        windows=[
            Window(weekday=w.weekday, start_minute=w.start_minute, end_minute=w.end_minute)
            for w in windows
        ],
        blocked_days=[
            BlockedDayOut(id=e.id, day=e.day.isoformat(), reason=e.reason)
            for e in exceptions
            if e.day >= today
        ],
        conflicts=_conflicts(db, profile.user_id, windows, scheduling.blocked_set(exceptions)),
    )


def _check(windows: list[Window]) -> None:
    by_day: dict[int, list[Window]] = {}
    for w in windows:
        if w.start_minute % GRID_MINUTES or w.end_minute % GRID_MINUTES:
            raise ApiError(400, "off_grid")
        if w.start_minute >= w.end_minute:
            raise ApiError(400, "empty_window")
        by_day.setdefault(w.weekday, []).append(w)
    for day in by_day.values():
        if len(day) > MAX_WINDOWS_PER_DAY:
            raise ApiError(400, "too_many_windows")
        day.sort(key=lambda w: w.start_minute)
        if any(a.end_minute > b.start_minute for a, b in zip(day, day[1:])):
            raise ApiError(400, "overlapping_windows")


@router.get("", response_model=AvailabilityOut)
def get_availability(
    doctor: DoctorProfile = Depends(current_doctor), db: Session = Depends(get_db)
) -> AvailabilityOut:
    return _state(db, doctor)


@router.put("/windows", response_model=AvailabilityOut)
def replace_windows(
    body: WindowsIn,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> AvailabilityOut:
    """Replaces the whole weekly schedule at once."""
    _check(body.windows)
    profile = _locked(db, doctor)
    db.execute(delete(Availability).where(Availability.doctor_id == profile.user_id))
    for w in body.windows:
        db.add(Availability(doctor_id=profile.user_id, **w.model_dump()))
    audit.record(db, "availability.windows", actor_id=profile.user_id, target=str(profile.user_id), request=request)
    db.commit()
    return _state(db, profile)


@router.put("/settings", response_model=AvailabilityOut)
def update_settings(
    body: SettingsIn,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> AvailabilityOut:
    """Slot length and booking notice. Booked visits keep their length."""
    profile = _locked(db, doctor)
    profile.slot_minutes = body.slot_minutes
    profile.notice_hours = body.notice_hours
    audit.record(db, "availability.settings", actor_id=profile.user_id, target=str(profile.user_id), request=request)
    db.commit()
    return _state(db, profile)


@router.post("/blocked-days", response_model=AvailabilityOut, status_code=201)
def block_day(
    body: BlockIn,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> AvailabilityOut:
    """A holiday or a one-off day off."""
    today = scheduling.clinic_today(clock.now())
    if body.day < today:
        raise ApiError(400, "day_in_past")
    if body.day > today + timedelta(days=MAX_BLOCK_AHEAD_DAYS):
        raise ApiError(400, "day_too_far")
    profile = _locked(db, doctor)
    exists = db.scalar(
        select(AvailabilityException.id).where(
            AvailabilityException.doctor_id == profile.user_id, AvailabilityException.day == body.day
        )
    )
    if exists is not None:
        db.rollback()
        raise ApiError(409, "already_blocked")
    reason = (body.reason or "").strip() or None
    blocked = AvailabilityException(id=uuid.uuid4(), doctor_id=profile.user_id, day=body.day, reason=reason)
    db.add(blocked)
    audit.record(db, "availability.blocked", actor_id=profile.user_id, target=str(blocked.id), request=request)
    db.commit()
    return _state(db, profile)


@router.delete("/blocked-days/{blocked_id}", response_model=AvailabilityOut)
def unblock_day(
    blocked_id: uuid.UUID,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> AvailabilityOut:
    profile = _locked(db, doctor)
    blocked = db.get(AvailabilityException, blocked_id)
    if blocked is None or blocked.doctor_id != profile.user_id:
        db.rollback()
        raise ApiError(404, "blocked_day_not_found")
    db.delete(blocked)
    audit.record(db, "availability.unblocked", actor_id=profile.user_id, target=str(blocked_id), request=request)
    db.commit()
    return _state(db, profile)
