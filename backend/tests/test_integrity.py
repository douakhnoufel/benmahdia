"""The database itself refuses impossible rows (migration 0017): check
constraints, the doctor foreign keys and RESTRICT on clinical records. The
API validates the same values; these tests write straight to the database to
prove it is the last line. The "HH:MM" regex checks exist on PostgreSQL only."""

import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, datetime

import pytest
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db import Base, engine
from app.models import (
    Addiction,
    AddictionCheck,
    AddictionType,
    Alert,
    Appointment,
    AppointmentNote,
    AppointmentStatus,
    Article,
    ArticleTopic,
    DoctorProfile,
    DoseLog,
    DoseStatus,
    Habit,
    HabitKind,
    Medication,
    Payment,
    PaymentMethod,
    Role,
    User,
)

POSTGRES = engine.dialect.name == "postgresql"
pg_only = pytest.mark.skipif(not POSTGRES, reason="regex checks exist on PostgreSQL only")


@dataclass
class World:
    doctor: uuid.UUID
    patient: uuid.UUID
    appointment: uuid.UUID
    addiction: uuid.UUID
    medication: uuid.UUID


@pytest.fixture
def db():
    if not POSTGRES:
        with engine.connect() as c:
            c.exec_driver_sql("PRAGMA foreign_keys=OFF")
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    if POSTGRES:
        engine.dispose()
    with Session(engine) as s:
        yield s


@pytest.fixture
def foreign_keys(db):
    """SQLite only enforces foreign keys when asked, per connection (the
    tests share one in-memory connection, so it is switched off again)."""
    if not POSTGRES:
        with engine.connect() as c:
            c.exec_driver_sql("PRAGMA foreign_keys=ON")
    yield
    if not POSTGRES:
        db.rollback()
        with engine.connect() as c:
            c.exec_driver_sql("PRAGMA foreign_keys=OFF")


def _world(db: Session) -> World:
    doc = User(role=Role.doctor, email="doc@example.com")
    pat = User(role=Role.patient, phone="+213661234567")
    db.add_all([doc, pat])
    db.flush()
    db.add(DoctorProfile(user_id=doc.id, name_ar="د", name_fr="Dr", price_dzd=2000))
    db.flush()
    appt = Appointment(doctor_id=doc.id, patient_id=pat.id, start_utc=datetime(2026, 10, 20, 8),
                       end_utc=datetime(2026, 10, 20, 8, 15), price_dzd=2000,
                       status=AppointmentStatus.completed)
    add = Addiction(patient_id=pat.id, type=AddictionType.other, sobriety_start=datetime(2026, 9, 1))
    med = Medication(patient_id=pat.id, prescribed_by=doc.id, name="QA-ITEM", amount="1",
                     times=["08:00"], start_date=date(2026, 10, 1))
    db.add_all([appt, add, med])
    db.commit()
    return World(doc.id, pat.id, appt.id, add.id, med.id)


def _refused(db: Session, row) -> None:
    db.add(row)
    with pytest.raises(IntegrityError):
        db.commit()
    db.rollback()


def _article(w: World, **kw) -> Article:
    fields = dict(author_id=w.doctor, title="QA", body="QA", language="fr",
                  topic=ArticleTopic.motivation, published=False)
    return Article(**(fields | kw))


def _addiction(w: World, **kw) -> Addiction:
    return Addiction(patient_id=w.patient, type=AddictionType.other,
                     sobriety_start=datetime(2026, 9, 1), **kw)


BAD_ROWS: dict[str, Callable[[World], object]] = {
    "ck_appointments_price_dzd": lambda w: Appointment(
        doctor_id=w.doctor, patient_id=w.patient, start_utc=datetime(2026, 10, 21, 8),
        end_utc=datetime(2026, 10, 21, 8, 15), price_dzd=-1),
    "ck_payments_amount_dzd": lambda w: Payment(
        patient_id=w.patient, amount_dzd=-1, method=PaymentMethod.cib, chargily_id="qa-1"),
    "ck_addiction_checks_craving_high": lambda w: AddictionCheck(
        addiction_id=w.addiction, day=date(2026, 10, 1), used=False, craving=6),
    "ck_addiction_checks_craving_low": lambda w: AddictionCheck(
        addiction_id=w.addiction, day=date(2026, 10, 1), used=False, craving=0),
    "ck_addictions_goal_days": lambda w: _addiction(w, goal_days=0),
    "ck_addictions_milestone_seen": lambda w: _addiction(w, milestone_seen=-1),
    "ck_addictions_milestone_alerted": lambda w: _addiction(w, milestone_alerted=-1),
    "ck_addictions_longest_past_days": lambda w: _addiction(w, longest_past_days=-1),
    "ck_addictions_past_days": lambda w: _addiction(w, past_days=-1),
    "ck_medications_dates": lambda w: Medication(
        patient_id=w.patient, prescribed_by=w.doctor, name="QA", amount="1", times=["08:00"],
        start_date=date(2026, 10, 10), end_date=date(2026, 10, 9)),
    "ck_articles_language": lambda w: _article(w, language="en"),
    "ck_articles_published_at": lambda w: _article(w, published=True, published_at=None),
    "ck_alerts_priority": lambda w: Alert(
        doctor_id=w.doctor, patient_id=w.patient, type="relapse", priority="urgent"),
}


@pytest.mark.parametrize("constraint", sorted(BAD_ROWS))
def test_the_database_refuses_a_bad_row(db, constraint):
    w = _world(db)
    _refused(db, BAD_ROWS[constraint](w))


@pg_only
@pytest.mark.parametrize("time", ["8:00", "24:00", "08:60", "08h00", "٠٨:٠٠", "08:0x"])
def test_postgres_refuses_a_dose_time_that_is_not_hh_mm(db, time):
    w = _world(db)
    _refused(db, DoseLog(medication_id=w.medication, day=date(2026, 10, 2), time=time,
                         status=DoseStatus.taken))


@pg_only
@pytest.mark.parametrize("time", ["7:30", "25:00", "07:5", "07-30"])
def test_postgres_refuses_a_habit_reminder_that_is_not_hh_mm(db, time):
    w = _world(db)
    _refused(db, Habit(patient_id=w.patient, kind=HabitKind.sport, reminder_time=time))


def test_valid_rows_still_insert(db):
    w = _world(db)
    db.add_all([
        Payment(patient_id=w.patient, appointment_id=w.appointment, amount_dzd=2000,
                method=PaymentMethod.cib, chargily_id="qa-ok"),
        # A doctor's price may be 0 DZD (admin prices accept it), so may a payment.
        Payment(patient_id=w.patient, amount_dzd=0, method=PaymentMethod.clinic,
                chargily_id="qa-free"),
        AddictionCheck(addiction_id=w.addiction, day=date(2026, 10, 1), used=False, craving=1),
        AddictionCheck(addiction_id=w.addiction, day=date(2026, 10, 2), used=True, craving=5),
        _addiction(w, goal_days=7, milestone_seen=30, milestone_alerted=30,
                   longest_past_days=90, past_days=120),
        _addiction(w, goal_days=None),
        Medication(patient_id=w.patient, prescribed_by=w.doctor, name="QA", amount="1",
                   times=["00:00"], start_date=date(2026, 10, 1), end_date=date(2026, 10, 1)),
        _article(w, language="ar", published=True, published_at=datetime(2026, 10, 2)),
        # Unpublished keeps its first publication date.
        _article(w, published=False, published_at=datetime(2026, 10, 2)),
        _article(w, published=False),
        Alert(doctor_id=w.doctor, patient_id=w.patient, type="relapse", priority="high"),
        Alert(doctor_id=w.doctor, patient_id=w.patient, type="milestone", priority="normal"),
        DoseLog(medication_id=w.medication, day=date(2026, 10, 2), time="23:59",
                status=DoseStatus.taken),
        DoseLog(medication_id=w.medication, day=date(2026, 10, 2), time="00:00",
                status=DoseStatus.skipped),
        Habit(patient_id=w.patient, kind=HabitKind.sport, reminder_time="19:05"),
        Habit(patient_id=w.patient, kind=HabitKind.water, reminder_time=None),
        Appointment(doctor_id=w.doctor, patient_id=w.patient, start_utc=datetime(2026, 10, 22, 8),
                    end_utc=datetime(2026, 10, 22, 8, 15), price_dzd=0),
    ])
    db.commit()
    a = db.get(Addiction, w.addiction)
    a.reviewed_by = w.doctor
    db.commit()


# --- Foreign keys -------------------------------------------------------------


@pytest.mark.parametrize("record", ["medication", "article", "addiction"])
def test_a_clinical_record_must_name_a_doctor(db, foreign_keys, record):
    w = _world(db)
    stranger = uuid.uuid4()
    if record == "medication":
        _refused(db, Medication(patient_id=w.patient, prescribed_by=stranger, name="QA",
                                amount="1", times=["08:00"], start_date=date(2026, 10, 1)))
    elif record == "article":
        _refused(db, _article(w, author_id=stranger))
    else:
        _refused(db, _addiction(w, reviewed_by=stranger))
    # The patient is not a doctor either.
    if record == "article":
        _refused(db, _article(w, author_id=w.patient))


def _remove_doctor_profile(db: Session, w: World) -> None:
    db.delete(db.get(DoctorProfile, w.doctor))
    db.commit()


def _only(db: Session, w: World, record: str) -> None:
    """Leaves [record] as the one row tying the doctor's profile to the
    clinic's data (the world's visit and prescription are removed first; the
    visit's own foreign key already restricts)."""
    db.query(Medication).delete()
    db.query(Appointment).delete()
    db.commit()
    if record == "note":
        # A colleague's visit, with a note this doctor wrote on it.
        colleague = User(role=Role.doctor, email="colleague@example.com")
        db.add(colleague)
        db.flush()
        db.add(DoctorProfile(user_id=colleague.id, name_ar="د", name_fr="Dr B", price_dzd=2000))
        db.flush()
        appt = Appointment(doctor_id=colleague.id, patient_id=w.patient,
                           start_utc=datetime(2026, 10, 20, 8), end_utc=datetime(2026, 10, 20, 8, 15),
                           price_dzd=2000, status=AppointmentStatus.completed)
        db.add(appt)
        db.flush()
        db.add(AppointmentNote(appointment_id=appt.id, doctor_id=w.doctor, text_enc=b"\x00"))
    elif record == "medication":
        db.add(Medication(patient_id=w.patient, prescribed_by=w.doctor, name="QA", amount="1",
                          times=["08:00"], start_date=date(2026, 10, 1)))
    elif record == "article":
        db.add(_article(w))
    else:
        db.get(Addiction, w.addiction).reviewed_by = w.doctor
    db.commit()


def test_a_doctor_profile_with_no_clinical_records_can_be_removed(db, foreign_keys):
    w = _world(db)
    _only(db, w, "medication")
    db.query(Medication).delete()
    db.commit()
    _remove_doctor_profile(db, w)
    assert db.get(DoctorProfile, w.doctor) is None


@pytest.mark.parametrize("record", ["note", "medication", "article", "addiction"])
def test_removing_a_doctor_profile_that_wrote_a_record_is_refused(db, foreign_keys, record):
    """RESTRICT: a clinical record keeps who wrote it. For the note this was
    ON DELETE CASCADE, which silently erased the doctor's visit notes."""
    w = _world(db)
    _only(db, w, record)
    with pytest.raises(IntegrityError):
        _remove_doctor_profile(db, w)
    db.rollback()
    assert db.get(DoctorProfile, w.doctor) is not None
    if record == "note":
        assert db.query(AppointmentNote).count() == 1
