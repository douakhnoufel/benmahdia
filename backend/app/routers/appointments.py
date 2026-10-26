import uuid
from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import audit, checkin, notices, scheduling
from ..clock import clock
from ..config import get_settings
from ..db import get_db
from ..deps import verified_patient
from ..errors import ApiError
from ..models import (
    Appointment,
    AppointmentStatus,
    Availability,
    AvailabilityException,
    DoctorProfile,
    Payment,
    PaymentMethod,
    PaymentStatus,
    User,
)
from .doctors import DoctorOut, doctor_out, utc_iso

router = APIRouter(prefix="/v1/appointments", tags=["appointments"])

FOLLOW_UP_DAYS = 30


class HoldIn(BaseModel):
    doctor_id: uuid.UUID
    # UTC instant of the slot, exactly as the calendar returned it.
    start: datetime


class ConfirmIn(BaseModel):
    method: PaymentMethod


class AppointmentOut(BaseModel):
    id: uuid.UUID
    doctor: DoctorOut
    start: str
    end: str
    status: AppointmentStatus
    price_dzd: int
    method: PaymentMethod | None
    hold_expires_at: str | None
    # Shown to the patient to present at the front desk; only while confirmed.
    checkin_code: str | None = None
    # Paid by card, or marked paid by the doctor for pay-at-clinic: a receipt
    # is available.
    paid: bool = False


class ReceiptOut(BaseModel):
    # Short reference printed on the receipt; it is derived from the
    # appointment id and holds no personal data.
    number: str
    appointment_id: uuid.UUID
    doctor_name_ar: str
    doctor_name_fr: str
    start: str
    amount_dzd: int
    method: PaymentMethod
    paid_at: str
    # Chargily's payment id for a card payment; None when paid at the clinic.
    payment_ref: str | None


class FollowUpOut(BaseModel):
    after: AppointmentOut
    # Suggested clinic day, e.g. 2026-11-20.
    day: str
    days: int


def _out(db: Session, a: Appointment) -> AppointmentOut:
    profile = db.get(DoctorProfile, a.doctor_id)
    return AppointmentOut(
        id=a.id,
        doctor=doctor_out(profile),
        start=utc_iso(a.start_utc),
        end=utc_iso(a.end_utc),
        status=a.status,
        price_dzd=a.price_dzd,
        method=a.method,
        hold_expires_at=utc_iso(a.hold_expires_at) if a.hold_expires_at else None,
        checkin_code=a.checkin_code if a.status == AppointmentStatus.confirmed else None,
        paid=a.paid_at is not None,
    )


def _naive_utc(value: datetime) -> datetime:
    if value.tzinfo is not None:
        value = value.astimezone(timezone.utc).replace(tzinfo=None)
    return value


def _mine(db: Session, patient: User, appointment_id: uuid.UUID) -> Appointment:
    """The patient's own appointment. Someone else's looks like a missing one,
    so ids reveal nothing."""
    a = db.get(Appointment, appointment_id)
    if a is None or a.patient_id != patient.id:
        raise ApiError(404, "appointment_not_found")
    return a


def _drop_expired_holds(db: Session, now: datetime) -> None:
    """An unpaid hold that ran out never became an appointment: remove it so
    its slot is free again (also for the database overlap rule)."""
    db.execute(
        delete(Appointment).where(
            Appointment.status == AppointmentStatus.awaiting_payment,
            Appointment.hold_expires_at <= now,
        )
    )


def _valid_slot(db: Session, profile: DoctorProfile, start: datetime, now: datetime) -> bool:
    """Whether [start] is one of the doctor's real slots, inside the notice
    and the booking horizon."""
    if start < now + timedelta(hours=profile.notice_hours):
        return False
    day: date = start.replace(tzinfo=timezone.utc).astimezone(scheduling.CLINIC_TZ).date()
    today = scheduling.clinic_today(now)
    if day >= today + timedelta(days=get_settings().booking_horizon_days):
        return False
    blocked = db.scalar(
        select(AvailabilityException.id).where(
            AvailabilityException.doctor_id == profile.user_id, AvailabilityException.day == day
        )
    )
    if blocked is not None:
        return False
    windows = list(db.scalars(select(Availability).where(Availability.doctor_id == profile.user_id)))
    return start in scheduling.day_starts(profile, windows, day)


@router.post("/holds", response_model=AppointmentOut, status_code=201)
def hold_slot(
    body: HoldIn,
    request: Request,
    patient: User = Depends(verified_patient),
    db: Session = Depends(get_db),
) -> AppointmentOut:
    """Holds a free slot while the patient pays (PRD 4.3). Exactly one of
    two simultaneous requests wins."""
    # Locks the patient's row on PostgreSQL so one patient's holds queue up,
    # even on two doctors: that keeps one open hold per patient.
    db.execute(select(User.id).where(User.id == patient.id).with_for_update())
    # Locks the doctor's row on PostgreSQL so bookings for one doctor queue up.
    profile = db.scalar(
        select(DoctorProfile).where(DoctorProfile.user_id == body.doctor_id).with_for_update()
    )
    if profile is None:
        raise ApiError(404, "doctor_not_found")
    now = clock.now()
    start = _naive_utc(body.start)
    if not _valid_slot(db, profile, start, now):
        raise ApiError(409, "slot_unavailable")
    end = start + timedelta(minutes=profile.slot_minutes)

    _drop_expired_holds(db, now)
    # One open hold per patient: starting a new one gives the old one back.
    db.execute(
        delete(Appointment).where(
            Appointment.patient_id == patient.id,
            Appointment.status == AppointmentStatus.awaiting_payment,
        )
    )
    taken = db.scalar(
        select(Appointment.id).where(
            Appointment.doctor_id == profile.user_id,
            Appointment.status.in_((AppointmentStatus.awaiting_payment, AppointmentStatus.confirmed)),
            Appointment.start_utc < end,
            Appointment.end_utc > start,
        )
    )
    if taken is not None:
        db.rollback()
        raise ApiError(409, "slot_unavailable")

    a = Appointment(
        id=uuid.uuid4(),
        doctor_id=profile.user_id,
        patient_id=patient.id,
        start_utc=start,
        end_utc=end,
        status=AppointmentStatus.awaiting_payment,
        price_dzd=profile.price_dzd,
        hold_expires_at=now + timedelta(minutes=profile.hold_minutes),
    )
    db.add(a)
    audit.record(db, "appointment.held", actor_id=patient.id, target=str(a.id), request=request)
    try:
        db.commit()
    except IntegrityError:
        # The database overlap rule caught a race the check above missed.
        db.rollback()
        raise ApiError(409, "slot_unavailable")
    return _out(db, a)


@router.delete("/{appointment_id}/hold", status_code=204)
def release_hold(
    appointment_id: uuid.UUID,
    patient: User = Depends(verified_patient),
    db: Session = Depends(get_db),
) -> Response:
    """Gives a held slot back, e.g. when the patient leaves the payment."""
    a = _mine(db, patient, appointment_id)
    if a.status != AppointmentStatus.awaiting_payment:
        raise ApiError(409, "not_a_hold")
    # Deletes only while it is still a hold: a confirm or a paid webhook may
    # have committed since it was read.
    gone = db.execute(
        delete(Appointment).where(
            Appointment.id == a.id, Appointment.status == AppointmentStatus.awaiting_payment
        )
    )
    if gone.rowcount != 1:
        db.rollback()
        raise ApiError(409, "not_a_hold")
    db.commit()
    return Response(status_code=204)


@router.post("/{appointment_id}/confirm", response_model=AppointmentOut)
def confirm(
    appointment_id: uuid.UUID,
    body: ConfirmIn,
    request: Request,
    patient: User = Depends(verified_patient),
    db: Session = Depends(get_db),
) -> AppointmentOut:
    """Books a held slot. Only the pilot's pay-at-the-clinic method can be
    confirmed from the app: a card payment is confirmed solely by Chargily's
    signed webhook (PRD 4.4)."""
    _mine(db, patient, appointment_id)
    # Re-reads under a row lock so a release or webhook running now either
    # finishes first or waits for this one.
    a = db.scalar(
        select(Appointment)
        .where(Appointment.id == appointment_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )
    if a is None:
        raise ApiError(404, "appointment_not_found")
    if body.method != PaymentMethod.clinic:
        raise ApiError(400, "payment_method_unavailable")
    if a.status != AppointmentStatus.awaiting_payment:
        raise ApiError(409, "not_a_hold")
    if a.hold_expires_at is None or a.hold_expires_at <= clock.now():
        db.delete(a)
        db.commit()
        raise ApiError(409, "hold_expired")
    a.status = AppointmentStatus.confirmed
    a.method = body.method
    a.hold_expires_at = None
    checkin.issue(db, a)
    notices.booking_alert(db, a, notices.CONFIRMED)
    audit.record(db, "appointment.confirmed", actor_id=patient.id, target=str(a.id), request=request)
    db.commit()
    return _out(db, a)


@router.get("", response_model=list[AppointmentOut])
def mine(
    patient: User = Depends(verified_patient), db: Session = Depends(get_db)
) -> list[AppointmentOut]:
    """Only this patient's appointments, oldest first."""
    now = clock.now()
    rows = db.scalars(
        select(Appointment)
        .where(Appointment.patient_id == patient.id)
        .order_by(Appointment.start_utc)
    ).all()
    return [
        _out(db, a)
        for a in rows
        if a.status != AppointmentStatus.awaiting_payment
        or (a.hold_expires_at is not None and a.hold_expires_at > now)
    ]


@router.get("/follow-up", response_model=FollowUpOut | None)
def follow_up(
    patient: User = Depends(verified_patient), db: Session = Depends(get_db)
) -> FollowUpOut | None:
    """The next visit the app suggests: 30 days after the latest one (PRD 4.3).
    The patient may still pick an earlier or later day."""
    last = db.scalar(
        select(Appointment)
        .where(
            Appointment.patient_id == patient.id,
            Appointment.status.in_((AppointmentStatus.completed, AppointmentStatus.confirmed)),
        )
        .order_by(Appointment.start_utc.desc())
        .limit(1)
    )
    if last is None:
        return None
    visit_day = last.start_utc.replace(tzinfo=timezone.utc).astimezone(scheduling.CLINIC_TZ).date()
    return FollowUpOut(
        after=_out(db, last),
        day=(visit_day + timedelta(days=FOLLOW_UP_DAYS)).isoformat(),
        days=FOLLOW_UP_DAYS,
    )


@router.get("/{appointment_id}/receipt", response_model=ReceiptOut)
def receipt(
    appointment_id: uuid.UUID,
    patient: User = Depends(verified_patient),
    db: Session = Depends(get_db),
) -> ReceiptOut:
    """Proof of payment for one of the patient's own paid appointments
    (PRD 4.4). It is a payment receipt, not a tax invoice, and carries no
    medical content."""
    a = _mine(db, patient, appointment_id)
    if a.paid_at is None or a.method is None:
        raise ApiError(409, "not_paid")
    profile = db.get(DoctorProfile, a.doctor_id)
    ref = db.scalar(
        select(Payment.chargily_id).where(
            Payment.appointment_id == a.id, Payment.status == PaymentStatus.paid
        )
    )
    return ReceiptOut(
        number="BM-" + a.id.hex[:8].upper(),
        appointment_id=a.id,
        doctor_name_ar=profile.name_ar,
        doctor_name_fr=profile.name_fr,
        start=utc_iso(a.start_utc),
        amount_dzd=a.price_dzd,
        method=a.method,
        paid_at=utc_iso(a.paid_at),
        payment_ref=ref,
    )


@router.post("/{appointment_id}/cancel", response_model=AppointmentOut)
def cancel(
    appointment_id: uuid.UUID,
    request: Request,
    patient: User = Depends(verified_patient),
    db: Session = Depends(get_db),
) -> AppointmentOut:
    """Cancels a confirmed appointment, unless it is inside the notice."""
    a = _mine(db, patient, appointment_id)
    if a.status != AppointmentStatus.confirmed:
        raise ApiError(409, "not_cancellable")
    profile = db.get(DoctorProfile, a.doctor_id)
    now = clock.now()
    if a.start_utc - now < timedelta(hours=profile.notice_hours):
        raise ApiError(409, "too_late_to_cancel")
    a.status = AppointmentStatus.cancelled
    a.cancelled_at = now
    notices.booking_alert(db, a, notices.CANCELLED)
    audit.record(db, "appointment.cancelled", actor_id=patient.id, target=str(a.id), request=request)
    db.commit()
    return _out(db, a)
