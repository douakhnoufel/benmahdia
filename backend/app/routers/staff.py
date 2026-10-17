"""Doctor dashboard API (PRD 7, MVP). A doctor sees only their own
appointments and patients. No 2FA yet: to add before launch (PRD 4.1)."""

import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit, scheduling, schemas, security, tokens
from ..clock import clock
from ..config import Settings, get_settings
from ..db import get_db
from ..deps import current_user
from ..errors import ApiError
from ..models import (
    AccountStatus,
    Appointment,
    AppointmentStatus,
    DoctorProfile,
    PaymentMethod,
    Role,
    User,
)
from .doctors import utc_iso

router = APIRouter(prefix="/v1/staff", tags=["staff"])


class StaffLogin(BaseModel):
    email: str = Field(max_length=320)
    password: str = Field(max_length=256)


class AgendaItem(BaseModel):
    id: uuid.UUID
    patient_id: uuid.UUID
    patient_phone: str | None
    start: str
    end: str
    status: AppointmentStatus
    method: PaymentMethod | None
    price_dzd: int
    paid: bool


class StatusIn(BaseModel):
    status: Literal["completed", "no_show"]


class PaidIn(BaseModel):
    paid: bool


class PatientOut(BaseModel):
    id: uuid.UUID
    phone: str | None
    visits: int
    last_visit: str | None
    next_visit: str | None


class SignupOut(BaseModel):
    id: uuid.UUID
    phone: str | None
    created_at: str


def current_doctor(user: User = Depends(current_user), db: Session = Depends(get_db)) -> DoctorProfile:
    if user.role != Role.doctor:
        raise ApiError(403, "forbidden")
    profile = db.get(DoctorProfile, user.id)
    if profile is None:
        raise ApiError(403, "forbidden")
    return profile


@router.post("/login", response_model=schemas.Session)
def staff_login(
    body: StaffLogin,
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> schemas.Session:
    """Email + password for doctors and admins. Five failures lock the account."""
    email = body.email.strip().lower()
    user = db.scalar(
        select(User).where(User.email == email, User.role.in_((Role.doctor, Role.super_admin)))
    )
    now = clock.now()
    if user is not None and user.locked_until is not None and user.locked_until > now:
        raise ApiError(423, "account_locked", retry_after=int((user.locked_until - now).total_seconds()))
    ok = security.verify_password(body.password, user.password_hash if user else None)
    if user is None or not ok or not user.active:
        if user is not None:
            user.failed_logins += 1
            if user.failed_logins >= settings.login_max_failures:
                user.failed_logins = 0
                user.locked_until = now + timedelta(minutes=settings.lock_minutes)
        audit.record(db, "staff.login.failed", actor_id=user.id if user else None, request=request)
        db.commit()
        raise ApiError(401, "wrong_credentials")
    user.failed_logins = 0
    user.locked_until = None
    audit.record(db, "staff.login.succeeded", actor_id=user.id, request=request)
    session = tokens.issue(db, user)
    db.commit()
    return session


def _own(db: Session, doctor: DoctorProfile, appointment_id: uuid.UUID) -> Appointment:
    a = db.get(Appointment, appointment_id)
    if a is None or a.doctor_id != doctor.user_id:
        raise ApiError(404, "appointment_not_found")
    return a


def _item(db: Session, a: Appointment) -> AgendaItem:
    patient = db.get(User, a.patient_id)
    return AgendaItem(
        id=a.id,
        patient_id=a.patient_id,
        patient_phone=patient.phone if patient else None,
        start=utc_iso(a.start_utc),
        end=utc_iso(a.end_utc),
        status=a.status,
        method=a.method,
        price_dzd=a.price_dzd,
        paid=a.paid_at is not None,
    )


@router.get("/agenda", response_model=list[AgendaItem])
def agenda(
    day: date | None = None,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> list[AgendaItem]:
    """The doctor's booked visits of one clinic day (default: today). Open
    holds are left out: they are not appointments yet."""
    day = day or scheduling.clinic_today(clock.now())
    first, last = scheduling.to_utc(day, 0), scheduling.to_utc(day + timedelta(days=1), 0)
    rows = db.scalars(
        select(Appointment)
        .where(
            Appointment.doctor_id == doctor.user_id,
            Appointment.start_utc >= first,
            Appointment.start_utc < last,
            Appointment.status != AppointmentStatus.awaiting_payment,
        )
        .order_by(Appointment.start_utc)
    ).all()
    return [_item(db, a) for a in rows]


@router.post("/appointments/{appointment_id}/status", response_model=AgendaItem)
def set_status(
    appointment_id: uuid.UUID,
    body: StatusIn,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> AgendaItem:
    """Marks a visit that has started as completed or no-show (PRD 12.2)."""
    a = _own(db, doctor, appointment_id)
    if a.status not in (AppointmentStatus.confirmed, AppointmentStatus.completed, AppointmentStatus.no_show):
        raise ApiError(409, "not_markable")
    if a.start_utc > clock.now():
        raise ApiError(409, "not_started")
    a.status = AppointmentStatus(body.status)
    audit.record(db, f"appointment.{body.status}", actor_id=doctor.user_id, target=str(a.id), request=request)
    db.commit()
    return _item(db, a)


@router.post("/appointments/{appointment_id}/paid", response_model=AgendaItem)
def set_paid(
    appointment_id: uuid.UUID,
    body: PaidIn,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> AgendaItem:
    """Records payment at the clinic. Card payments are set only by Chargily."""
    a = _own(db, doctor, appointment_id)
    if a.method != PaymentMethod.clinic:
        raise ApiError(409, "paid_by_card")
    if a.status == AppointmentStatus.awaiting_payment:
        raise ApiError(409, "not_markable")
    a.paid_at = clock.now() if body.paid else None
    audit.record(db, "appointment.paid" if body.paid else "appointment.unpaid",
                 actor_id=doctor.user_id, target=str(a.id), request=request)
    db.commit()
    return _item(db, a)


@router.get("/patients", response_model=list[PatientOut])
def patients(
    doctor: DoctorProfile = Depends(current_doctor), db: Session = Depends(get_db)
) -> list[PatientOut]:
    """Patients who booked with this doctor, most recent activity first."""
    now = clock.now()
    rows = db.scalars(
        select(Appointment).where(
            Appointment.doctor_id == doctor.user_id,
            Appointment.status != AppointmentStatus.awaiting_payment,
        )
    ).all()
    by_patient: dict[uuid.UUID, list[Appointment]] = {}
    for a in rows:
        by_patient.setdefault(a.patient_id, []).append(a)
    out = []
    for pid, items in by_patient.items():
        user = db.get(User, pid)
        if user is None or not user.active:
            continue
        done = [a.start_utc for a in items if a.status == AppointmentStatus.completed]
        ahead = [a.start_utc for a in items if a.status == AppointmentStatus.confirmed and a.start_utc > now]
        out.append(
            PatientOut(
                id=pid,
                phone=user.phone,
                visits=len(done),
                last_visit=utc_iso(max(done)) if done else None,
                next_visit=utc_iso(min(ahead)) if ahead else None,
            )
        )
    epoch = datetime(1970, 1, 1, tzinfo=timezone.utc).isoformat()
    out.sort(key=lambda p: p.next_visit or p.last_visit or epoch, reverse=True)
    return out


@router.get("/signups", response_model=list[SignupOut])
def signups(
    _: DoctorProfile = Depends(current_doctor), db: Session = Depends(get_db)
) -> list[SignupOut]:
    """Patients waiting for the clinic to approve their identity (PRD 4.2),
    oldest first. ID photos are not collected yet."""
    rows = db.scalars(
        select(User)
        .where(
            User.role == Role.patient,
            User.status == AccountStatus.pending_verification,
            User.deleted_at.is_(None),
        )
        .order_by(User.created_at)
    ).all()
    return [SignupOut(id=u.id, phone=u.phone, created_at=utc_iso(u.created_at)) for u in rows]


def _signup(db: Session, user_id: uuid.UUID) -> User:
    user = db.get(User, user_id)
    if user is None or user.role != Role.patient or user.status != AccountStatus.pending_verification:
        raise ApiError(404, "signup_not_found")
    return user


@router.post("/signups/{user_id}/approve", response_model=SignupOut)
def approve(
    user_id: uuid.UUID,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> SignupOut:
    user = _signup(db, user_id)
    user.status = AccountStatus.verified
    audit.record(db, "signup.approved", actor_id=doctor.user_id, target=str(user.id), request=request)
    db.commit()
    return SignupOut(id=user.id, phone=user.phone, created_at=utc_iso(user.created_at))


@router.post("/signups/{user_id}/reject", response_model=SignupOut)
def reject(
    user_id: uuid.UUID,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> SignupOut:
    user = _signup(db, user_id)
    user.status = AccountStatus.rejected
    audit.record(db, "signup.rejected", actor_id=doctor.user_id, target=str(user.id), request=request)
    db.commit()
    return SignupOut(id=user.id, phone=user.phone, created_at=utc_iso(user.created_at))
