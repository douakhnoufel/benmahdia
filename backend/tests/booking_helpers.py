from datetime import date, datetime, timedelta

from sqlalchemy.orm import Session

from app.db import engine
from app.models import (
    AccountStatus,
    Appointment,
    AppointmentStatus,
    Availability,
    AvailabilityException,
    DoctorProfile,
    PaymentMethod,
    Role,
    User,
)
from app.seed import seed

from .conftest import bearer, register


def make_doctor(slot_minutes: int = 15) -> DoctorProfile:
    with Session(engine) as db:
        profile = seed(db)
        if profile.slot_minutes != slot_minutes:
            profile.slot_minutes = slot_minutes
            db.commit()
        db.refresh(profile)
        db.expunge(profile)
        return profile


def verified_patient(client, sms, phone="0661234567") -> dict:
    """Registers a patient and has the clinic approve the identity check."""
    session = register(client, sms, phone)
    with Session(engine) as db:
        user = db.query(User).filter(User.phone == "+213" + phone.lstrip("0")).one()
        user.status = AccountStatus.verified
        db.commit()
    return session


def headers(session: dict) -> dict:
    return bearer(session)


def block_day(doctor_id, day: date) -> None:
    with Session(engine) as db:
        db.add(AvailabilityException(doctor_id=doctor_id, day=day, reason="holiday"))
        db.commit()


def add_appointment(
    doctor_id,
    patient_id,
    start_utc: datetime,
    *,
    status=AppointmentStatus.confirmed,
    minutes=15,
    hold_expires_at=None,
    method=PaymentMethod.clinic,
) -> Appointment:
    with Session(engine) as db:
        a = Appointment(
            doctor_id=doctor_id,
            patient_id=patient_id,
            start_utc=start_utc,
            end_utc=start_utc + timedelta(minutes=minutes),
            status=status,
            price_dzd=2000,
            method=method,
            hold_expires_at=hold_expires_at,
        )
        db.add(a)
        db.commit()
        db.expunge(a)
        return a


def user_id(phone="0661234567"):
    with Session(engine) as db:
        return db.query(User).filter(User.phone == "+213" + phone.lstrip("0")).one().id
