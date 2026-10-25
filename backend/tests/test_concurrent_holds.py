"""Many patients grabbing one slot at once. SQLite cannot show this: it needs
the PostgreSQL row lock and overlap rule, so the test is skipped elsewhere.

    DATABASE_URL=postgresql+psycopg://... pytest tests/test_concurrent_holds.py
"""

from concurrent.futures import ThreadPoolExecutor

import pytest
from sqlalchemy.orm import Session

from app.db import engine
from app.models import Appointment, AppointmentStatus

from .booking_helpers import make_doctor, verified_patient
from .test_appointments import SLOT, hold

pytestmark = pytest.mark.skipif(
    engine.dialect.name != "postgresql", reason="needs PostgreSQL (row lock and overlap rule)"
)

PATIENTS = 8


def test_one_of_many_simultaneous_holds_wins(client, sms):
    doctor = make_doctor()
    sessions = [verified_patient(client, sms, f"06612345{n:02d}") for n in range(PATIENTS)]

    with ThreadPoolExecutor(max_workers=PATIENTS) as pool:
        results = list(pool.map(lambda s: hold(client, s, doctor, SLOT), sessions))

    codes = sorted(r.status_code for r in results)
    assert codes == [201] + [409] * (PATIENTS - 1), codes
    assert all(r.json()["detail"]["code"] == "slot_unavailable" for r in results if r.status_code == 409)
    with Session(engine) as db:
        held = db.query(Appointment).filter(Appointment.status == AppointmentStatus.awaiting_payment).count()
    assert held == 1
