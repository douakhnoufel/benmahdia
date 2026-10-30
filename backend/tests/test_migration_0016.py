"""Migration 0016 (milestones) on a real PostgreSQL database: existing
addictions start at the milestone they have already reached, so the first
nightly run after the deploy does not alert every doctor about old streaks
and patients see no celebration for an old milestone."""

import os
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, func, select, text
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from app.alerts_job import milestone_alerts
from app.clock import clock
from app.db import engine
from app.models import Alert, Appointment, AppointmentStatus, PaymentMethod
from app.seed import seed
from app.substances import reached_milestone

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

pytestmark = pytest.mark.skipif(
    engine.dialect.name != "postgresql", reason="needs PostgreSQL: runs the real migrations"
)


@pytest.fixture
def scratch_db():
    """A throwaway database on the test server, dropped afterwards."""
    name = f"mig0016_{uuid.uuid4().hex[:12]}"
    admin = create_engine(engine.url.set(database="postgres"), isolation_level="AUTOCOMMIT")
    with admin.connect() as c:
        c.execute(text(f'CREATE DATABASE "{name}"'))
    target = create_engine(make_url(engine.url).set(database=name))
    try:
        yield target
    finally:
        target.dispose()
        with admin.connect() as c:
            c.execute(text(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)'))
        admin.dispose()


def migrate(target, revision: str) -> None:
    cfg = Config(os.path.join(BACKEND, "alembic.ini"))
    cfg.set_main_option("script_location", os.path.join(BACKEND, "alembic"))
    with target.connect() as connection:
        cfg.attributes["connection"] = connection
        command.upgrade(cfg, revision)
        connection.commit()


def test_0016_backfills_the_milestone_already_reached(scratch_db):
    migrate(scratch_db, "0015")
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    patient, old, fresh = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    with scratch_db.begin() as c:
        c.execute(text(
            "INSERT INTO users (id, role, status, language, failed_logins, created_at) "
            "VALUES (:id, 'patient', 'verified', 'fr', 0, :now)"), {"id": patient, "now": now})
        for row_id, days in ((old, 40), (fresh, 0)):
            c.execute(text(
                "INSERT INTO addictions (id, patient_id, type, sobriety_start, longest_past_days, "
                "past_days, review_status, active, created_at) VALUES (:id, :p, 'tobacco', :start, "
                "0, 0, 'confirmed', true, :now)"),
                {"id": row_id, "p": patient, "start": now - timedelta(days=days), "now": now})
    migrate(scratch_db, "0016")
    with scratch_db.connect() as c:
        rows = dict(
            (r.id, (r.milestone_alerted, r.milestone_seen))
            for r in c.execute(text("SELECT id, milestone_alerted, milestone_seen FROM addictions"))
        )
    assert reached_milestone(40) > 0
    assert rows == {old: (reached_milestone(40),) * 2, fresh: (0, 0)}

    # A booked visit, so the nightly job would tell a doctor if it alerted.
    migrate(scratch_db, "head")
    with Session(scratch_db) as db:
        doctor = seed(db)
        db.add(Appointment(
            doctor_id=doctor.user_id, patient_id=patient, start_utc=now - timedelta(days=3),
            end_utc=now - timedelta(days=3) + timedelta(minutes=15),
            status=AppointmentStatus.completed, price_dzd=2000, method=PaymentMethod.clinic,
        ))
        db.commit()
    saved, clock.frozen = clock.frozen, None
    try:
        with Session(scratch_db) as db:
            assert milestone_alerts(db) == 0
            assert db.scalar(select(func.count()).select_from(Alert)) == 0
    finally:
        clock.frozen = saved
