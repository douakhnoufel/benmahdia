"""Doctor dashboard API (PRD 7, MVP). Every doctor sees the clinic-wide
agenda and every clinic patient's file (PRD 3: one clinic, shared files).
No 2FA yet: to add before launch (PRD 4.1)."""

import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit, checkin, scheduling, schemas, security, selfies, tokens
from ..clock import clock
from ..config import Settings, get_settings
from ..db import get_db
from ..deps import current_user
from ..errors import ApiError
from ..models import (
    BOOKED_STATUSES,
    AccountStatus,
    Appointment,
    AppointmentStatus,
    AuditLog,
    DoctorProfile,
    IdStatus,
    Payment,
    PaymentMethod,
    PaymentStatus,
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
    # When the front desk accepted the patient's booking code, if it did.
    checked_in_at: str | None = None
    # Whose visit it is: the agenda is clinic-wide, but only the visit's own
    # doctor can act on it.
    doctor_name_ar: str = ""
    doctor_name_fr: str = ""
    mine: bool = False


class HoldItem(BaseModel):
    """A slot held while the patient pays: a booking request, not a visit yet."""

    id: uuid.UUID
    patient_id: uuid.UUID
    patient_phone: str | None
    start: str
    end: str
    doctor_name_ar: str
    doctor_name_fr: str
    mine: bool
    # The slot is given back at this time if still unpaid.
    expires_at: str
    # The card chosen at Chargily's checkout, once the patient opened it.
    paying_by: PaymentMethod | None = None


class MeOut(BaseModel):
    id: uuid.UUID
    # "doctor" or "super_admin" (who is also a doctor, PRD 3).
    role: Role
    name_ar: str
    name_fr: str


class CheckinIn(BaseModel):
    code: str = Field(min_length=1, max_length=32)


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
    # "none" (nothing declared yet), "declared", "approved" or "rejected".
    id_status: str = "none"
    # The patient tried an ID that belongs to another account.
    duplicate_attempt: bool = False


class RejectIn(BaseModel):
    reason: str | None = Field(default=None, max_length=200)


def current_doctor(user: User = Depends(current_user), db: Session = Depends(get_db)) -> DoctorProfile:
    # The super admin is one of the doctors and also holds the Doctor role (PRD 3).
    if user.role not in (Role.doctor, Role.super_admin):
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


@router.get("/me", response_model=MeOut)
def me(doctor: DoctorProfile = Depends(current_doctor), db: Session = Depends(get_db)) -> MeOut:
    """Who is signed in to the dashboard, to show the pages their role allows.
    The API still checks the role on every route."""
    user = db.get(User, doctor.user_id)
    return MeOut(id=doctor.user_id, role=user.role, name_ar=doctor.name_ar, name_fr=doctor.name_fr)


def _own(db: Session, doctor: DoctorProfile, appointment_id: uuid.UUID) -> Appointment:
    a = db.get(Appointment, appointment_id)
    if a is None or a.doctor_id != doctor.user_id:
        raise ApiError(404, "appointment_not_found")
    return a


def _item(db: Session, a: Appointment, doctor: DoctorProfile) -> AgendaItem:
    """[a] as one agenda row, seen by [doctor]."""
    patient = db.get(User, a.patient_id)
    owner = doctor if a.doctor_id == doctor.user_id else db.get(DoctorProfile, a.doctor_id)
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
        checked_in_at=utc_iso(a.checked_in_at) if a.checked_in_at else None,
        doctor_name_ar=owner.name_ar if owner else "",
        doctor_name_fr=owner.name_fr if owner else "",
        mine=a.doctor_id == doctor.user_id,
    )


@router.get("/agenda", response_model=list[AgendaItem])
def agenda(
    day: date | None = None,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> list[AgendaItem]:
    """Every doctor's booked visits of one clinic day (default: today): the
    agenda is shared clinic-wide (PRD 3) and carries no clinical fields. Open
    holds are left out: they are not appointments yet."""
    day = day or scheduling.clinic_today(clock.now())
    first, last = scheduling.to_utc(day, 0), scheduling.to_utc(day + timedelta(days=1), 0)
    rows = db.scalars(
        select(Appointment)
        .where(
            Appointment.start_utc >= first,
            Appointment.start_utc < last,
            Appointment.status != AppointmentStatus.awaiting_payment,
        )
        .order_by(Appointment.start_utc)
    ).all()
    return [_item(db, a, doctor) for a in rows]


@router.get("/holds", response_model=list[HoldItem])
def holds(
    day: date | None = None,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> list[HoldItem]:
    """The clinic's open holds of one day (default: today): the pending
    booking requests of the Today page (PRD 7). Read only: a card hold is
    confirmed only by Chargily's signed webhook, a pay-at-clinic hold only by
    the patient. A hold that ran out is left out: its slot is free again."""
    now = clock.now()
    day = day or scheduling.clinic_today(now)
    first, last = scheduling.to_utc(day, 0), scheduling.to_utc(day + timedelta(days=1), 0)
    rows = db.scalars(
        select(Appointment)
        .where(
            Appointment.start_utc >= first,
            Appointment.start_utc < last,
            Appointment.status == AppointmentStatus.awaiting_payment,
            Appointment.hold_expires_at > now,
        )
        .order_by(Appointment.start_utc)
    ).all()
    out = []
    for a in rows:
        row = _item(db, a, doctor)
        paying_by = db.scalar(
            select(Payment.method)
            .where(Payment.appointment_id == a.id, Payment.status == PaymentStatus.pending)
            .order_by(Payment.created_at.desc())
            .limit(1)
        )
        out.append(
            HoldItem(
                id=a.id,
                patient_id=a.patient_id,
                patient_phone=row.patient_phone,
                start=row.start,
                end=row.end,
                doctor_name_ar=row.doctor_name_ar,
                doctor_name_fr=row.doctor_name_fr,
                mine=row.mine,
                expires_at=utc_iso(a.hold_expires_at),
                paying_by=paying_by,
            )
        )
    return out


@router.post("/checkin", response_model=AgendaItem)
def check_in(
    body: CheckinIn,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> AgendaItem:
    """The patient shows their booking code at the front desk: mark them as
    arrived. Only this doctor's own confirmed appointments of today match; any
    other code looks like an unknown one. Repeating a check-in changes
    nothing. Too many wrong codes make the account wait. The desk must still
    look at the patient's physical ID."""
    now = clock.now()
    window = timedelta(minutes=settings.checkin_window_minutes)
    failures = db.scalars(
        select(AuditLog.created_at)
        .where(
            AuditLog.actor_id == doctor.user_id,
            AuditLog.action == "checkin.failed",
            AuditLog.created_at > now - window,
        )
        .order_by(AuditLog.created_at)
    ).all()
    if len(failures) >= settings.checkin_max_failures:
        wait = failures[0] + window - now
        raise ApiError(429, "too_many_attempts", retry_after=max(1, int(wait.total_seconds())))

    code = checkin.normalize(body.code)
    a = (
        db.scalar(
            select(Appointment).where(
                Appointment.checkin_code == code, Appointment.doctor_id == doctor.user_id
            )
        )
        if code
        else None
    )
    if a is None:
        # Never log the code itself, only that a wrong one was tried.
        audit.record(db, "checkin.failed", actor_id=doctor.user_id, request=request)
        db.commit()
        raise ApiError(404, "checkin_code_invalid")

    if a.checked_in_at is None:
        if a.status != AppointmentStatus.confirmed:
            raise ApiError(409, "not_checkable")
        # The clinic day the visit falls on (clinic_today converts any UTC instant).
        if scheduling.clinic_today(a.start_utc) != scheduling.clinic_today(now):
            raise ApiError(409, "not_today")
        a.checked_in_at = now
        audit.record(db, "appointment.checked_in", actor_id=doctor.user_id, target=str(a.id), request=request)
        db.commit()
    return _item(db, a, doctor)


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
    return _item(db, a, doctor)


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
    return _item(db, a, doctor)


@router.get("/patients", response_model=list[PatientOut])
def patients(
    doctor: DoctorProfile = Depends(current_doctor), db: Session = Depends(get_db)
) -> list[PatientOut]:
    """The clinic's patients (a booked visit with any doctor), most recent
    activity first."""
    now = clock.now()
    rows = db.scalars(
        select(Appointment).where(Appointment.status.in_(BOOKED_STATUSES))
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


def _signup_out(u: User, duplicates: set[uuid.UUID] | None = None) -> SignupOut:
    return SignupOut(
        id=u.id,
        phone=u.phone,
        created_at=utc_iso(u.created_at),
        id_status=tokens.id_status(u),
        duplicate_attempt=u.id in (duplicates or set()),
    )


@router.get("/signups", response_model=list[SignupOut])
def signups(
    _: DoctorProfile = Depends(current_doctor), db: Session = Depends(get_db)
) -> list[SignupOut]:
    """Patients waiting for the clinic to approve their identity (PRD 4.2),
    oldest first. Someone whose declaration was rejected waits for the patient
    to resubmit, so they are not in the queue."""
    rows = db.scalars(
        select(User)
        .where(
            User.role == Role.patient,
            User.status == AccountStatus.pending_verification,
            User.deleted_at.is_(None),
        )
        .order_by(User.created_at)
    ).all()
    duplicates = set(
        db.scalars(select(AuditLog.actor_id).where(AuditLog.action == "identity.duplicate"))
    )
    return [
        _signup_out(u, duplicates)
        for u in rows
        if u.id_declaration is None or u.id_declaration.status == IdStatus.declared
    ]


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
    """Approves a declared ID, which unlocks booking (PRD 4.2). A sign-up with
    nothing declared yet cannot be approved, only rejected."""
    user = _signup(db, user_id)
    declaration = user.id_declaration
    if declaration is None or declaration.status != IdStatus.declared:
        raise ApiError(409, "id_not_declared")
    user.status = AccountStatus.verified
    declaration.status = IdStatus.approved
    declaration.reject_reason = None
    declaration.decided_at = clock.now()
    declaration.decided_by = doctor.user_id
    audit.record(db, "signup.approved", actor_id=doctor.user_id, target=str(user.id), request=request)
    db.commit()
    return _signup_out(user)


@router.post("/signups/{user_id}/reject", response_model=SignupOut)
def reject(
    user_id: uuid.UUID,
    request: Request,
    body: RejectIn | None = None,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> SignupOut:
    """Refuses a declaration. The patient may submit again (up to the limit);
    the stored selfie is deleted. A sign-up with no declaration is rejected
    outright."""
    user = _signup(db, user_id)
    declaration = user.id_declaration
    if declaration is None:
        user.status = AccountStatus.rejected
    else:
        reason = (body.reason.strip() if body and body.reason else None) or None
        declaration.status = IdStatus.rejected
        declaration.reject_reason = reason
        declaration.decided_at = clock.now()
        declaration.decided_by = doctor.user_id
        old_file, declaration.selfie_file = declaration.selfie_file, None
    audit.record(db, "signup.rejected", actor_id=doctor.user_id, target=str(user.id), request=request)
    db.commit()
    if declaration is not None:
        selfies.delete(old_file)
    return _signup_out(user)
