"""Slot arithmetic for the clinic agenda (PRD 4.3).

The database stores UTC; consultation windows are kept as minutes after
midnight in clinic time. Algeria has no daylight saving, but the conversion
still goes through the zone so a rule change cannot silently shift slots."""

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from .models import Appointment, Availability, AvailabilityException, DoctorProfile

CLINIC_TZ = ZoneInfo("Africa/Algiers")


def to_utc(day: date, minute: int) -> datetime:
    """Clinic wall time (a day and minutes after midnight) as naive UTC."""
    local = datetime.combine(day, time(minute // 60, minute % 60), tzinfo=CLINIC_TZ)
    return local.astimezone(timezone.utc).replace(tzinfo=None)


def clinic_today(now_utc: datetime) -> date:
    return now_utc.replace(tzinfo=timezone.utc).astimezone(CLINIC_TZ).date()


def day_starts(profile: DoctorProfile, windows: list[Availability], day: date) -> list[datetime]:
    """Every slot start (naive UTC) the doctor offers on [day], in order. A
    slot must fit entirely inside a window."""
    starts: list[datetime] = []
    step = profile.slot_minutes
    for w in sorted((w for w in windows if w.weekday == day.weekday()), key=lambda w: w.start_minute):
        for m in range(w.start_minute, w.end_minute - step + 1, step):
            starts.append(to_utc(day, m))
    return starts


def blocks(appointment: Appointment, now_utc: datetime) -> bool:
    """Whether [appointment] still occupies its slot. An unpaid hold stops
    blocking the moment it expires."""
    status = appointment.status.value
    if status == "confirmed":
        return True
    if status == "awaiting_payment":
        return appointment.hold_expires_at is not None and appointment.hold_expires_at > now_utc
    return False


@dataclass(frozen=True)
class SlotView:
    start: datetime
    free: bool


@dataclass(frozen=True)
class DayView:
    day: date
    closure: str  # "none" | "too_soon" | "closed"
    slots: list[SlotView]


def build_day(
    profile: DoctorProfile,
    windows: list[Availability],
    blocked_days: set[date],
    taken: list[Appointment],
    day: date,
    now_utc: datetime,
) -> DayView:
    """The slots of one day, or why there are none. Patients only learn
    whether a slot is free, never who holds it."""
    if day in blocked_days:
        return DayView(day, "closed", [])
    starts = day_starts(profile, windows, day)
    if not starts:
        return DayView(day, "closed", [])
    earliest = now_utc + timedelta(hours=profile.notice_hours)
    if all(s < earliest for s in starts):
        return DayView(day, "too_soon", [])
    length = timedelta(minutes=profile.slot_minutes)
    busy = [(a.start_utc, a.end_utc) for a in taken if blocks(a, now_utc)]
    slots = [
        SlotView(s, s >= earliest and not any(b0 < s + length and s < b1 for b0, b1 in busy))
        for s in starts
    ]
    return DayView(day, "none", slots)


def blocked_set(exceptions: list[AvailabilityException]) -> set[date]:
    return {e.day for e in exceptions}
