from datetime import datetime
import uuid

import pytest
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db import Base, engine
from app.models import Appointment, Availability, DoctorProfile, Role, User


@pytest.fixture
def db():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    with Session(engine) as s:
        yield s


def _doctor(db, slot=15) -> DoctorProfile:
    user = User(role=Role.doctor, email="doc@example.com")
    db.add(user)
    db.flush()
    profile = DoctorProfile(user_id=user.id, name_ar="د", name_fr="Dr", slot_minutes=slot, price_dzd=2000)
    db.add(profile)
    db.commit()
    return profile


@pytest.mark.parametrize("slot", [5, 10, 15])
def test_allowed_slot_lengths(db, slot):
    assert _doctor(db, slot).slot_minutes == slot


@pytest.mark.parametrize("slot", [0, 7, 20])
def test_rejects_other_slot_lengths(db, slot):
    with pytest.raises(IntegrityError):
        _doctor(db, slot)


def test_rejects_inverted_window(db):
    doc = _doctor(db)
    db.add(Availability(doctor_id=doc.user_id, weekday=0, start_minute=720, end_minute=540))
    with pytest.raises(IntegrityError):
        db.commit()


def test_rejects_inverted_appointment(db):
    doc = _doctor(db)
    patient = User(role=Role.patient)
    db.add(patient)
    db.flush()
    db.add(Appointment(doctor_id=doc.user_id, patient_id=patient.id, price_dzd=2000,
                       start_utc=datetime(2026, 10, 20, 9, 0), end_utc=datetime(2026, 10, 20, 8, 45)))
    with pytest.raises(IntegrityError):
        db.commit()
