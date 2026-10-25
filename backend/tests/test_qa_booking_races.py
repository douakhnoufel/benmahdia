"""QA 2026-10-25 (concurrency): booking races on the real database.

SQLite has no row lock and no overlap rule, so like test_concurrent_holds.py
these tests are skipped unless the app engine is PostgreSQL.

    DATABASE_URL=postgresql+psycopg://...@127.0.0.1:5432/... pytest tests/test_qa_booking_races.py

Every race test checks, after the race, straight in the database, that no two
blocking appointments (awaiting_payment or confirmed) of one doctor overlap.
"""

import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from threading import Barrier

import pytest
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Session

from app.db import engine
from app.models import (
    Appointment,
    AppointmentStatus,
    AuditLog,
    Availability,
    DoctorProfile,
    Payment,
    PaymentStatus,
    Role,
    User,
)

from .booking_helpers import add_appointment, expire_holds, headers, make_doctor, user_id, verified_patient
from .test_appointments import hold
from .test_payments import chargily, event, send  # noqa: F401  (chargily is a fixture)

pytestmark = pytest.mark.skipif(
    engine.dialect.name != "postgresql", reason="needs PostgreSQL (row lock and overlap rule)"
)

# Clock (conftest): Saturday 2026-10-17 19:00 Algiers. Monday 09:00-12:00
# Algiers is 08:00-11:00 UTC: twelve 15-minute slots.
MONDAY = datetime(2026, 10, 19, 8, 0)
ROUNDS = 5


def slot(n: int, minutes: int = 15) -> str:
    return (MONDAY + timedelta(minutes=minutes * n)).strftime("%Y-%m-%dT%H:%M:%SZ")


def phone(n: int) -> str:
    return f"06612345{n:02d}"


def patients(client, sms, count: int) -> list[dict]:
    return [verified_patient(client, sms, phone(n)) for n in range(count)]


def parallel(*calls):
    """Runs the calls at the same moment (as far as threads allow)."""
    gate = Barrier(len(calls))

    def run(fn):
        gate.wait()
        return fn()

    with ThreadPoolExecutor(max_workers=len(calls)) as pool:
        return list(pool.map(run, calls))


def overlaps() -> int:
    """Pairs of blocking appointments of one doctor that overlap. Must be 0."""
    with engine.connect() as c:
        return c.execute(
            text(
                """
                SELECT count(*) FROM appointments a JOIN appointments b
                  ON a.doctor_id = b.doctor_id AND a.id < b.id
                 AND a.status IN ('awaiting_payment', 'confirmed')
                 AND b.status IN ('awaiting_payment', 'confirmed')
                 AND a.start_utc < b.end_utc AND b.start_utc < a.end_utc
                """
            )
        ).scalar_one()


def open_holds(patient_id) -> int:
    with Session(engine) as db:
        return (
            db.query(Appointment)
            .filter(
                Appointment.patient_id == patient_id,
                Appointment.status == AppointmentStatus.awaiting_payment,
            )
            .count()
        )


def get_appointment(appointment_id) -> Appointment | None:
    with Session(engine) as db:
        return db.get(Appointment, uuid.UUID(str(appointment_id)))


def audits(action: str, target: str) -> int:
    with Session(engine) as db:
        return db.query(AuditLog).filter(AuditLog.action == action, AuditLog.target == target).count()


def second_doctor() -> DoctorProfile:
    """Another seeded-style doctor with the same weekly hours (fake data)."""
    first = make_doctor()
    with Session(engine) as db:
        user = User(role=Role.doctor, email="dr.second@example.invalid", language="fr")
        db.add(user)
        db.flush()
        profile = DoctorProfile(
            user_id=user.id, name_ar="د. طبيب ثان", name_fr="Dr Second", slot_minutes=15, price_dzd=2000
        )
        db.add(profile)
        db.flush()
        for w in db.query(Availability).filter(Availability.doctor_id == first.user_id).all():
            db.add(Availability(doctor_id=user.id, weekday=w.weekday,
                                start_minute=w.start_minute, end_minute=w.end_minute))
        db.commit()
        db.refresh(profile)
        db.expunge(profile)
        return profile


@pytest.fixture(autouse=True)
def _fresh_pool(client):
    """conftest drops and recreates the tables for every test; pooled
    PostgreSQL connections keep prepared plans for the old tables ("cached
    plan must not change result type"). Start each test with new connections."""
    engine.dispose()
    yield


# --- R-23: many patients, one slot -------------------------------------------


@pytest.mark.parametrize("round_", range(ROUNDS))
def test_many_patients_same_slot_exactly_one_wins(client, sms, round_):
    doctor = make_doctor()
    sessions = patients(client, sms, 10)
    results = parallel(*[lambda s=s: hold(client, s, doctor, slot(0)) for s in sessions])
    codes = sorted(r.status_code for r in results)
    assert codes == [201] + [409] * 9, codes
    assert overlaps() == 0


@pytest.mark.parametrize("round_", range(ROUNDS))
def test_patients_spread_over_few_slots_one_winner_per_slot(client, sms, round_):
    doctor = make_doctor()
    sessions = patients(client, sms, 12)
    results = parallel(*[lambda i=i, s=s: hold(client, s, doctor, slot(i % 3)) for i, s in enumerate(sessions)])
    assert sum(r.status_code == 201 for r in results) == 3
    assert all(r.status_code in (201, 409) for r in results), [r.status_code for r in results]
    assert overlaps() == 0


# --- R-24 / R-19: overlapping but different starts ---------------------------


def test_db_refuses_overlapping_rows_with_different_starts(client, sms):
    """The EXCLUDE constraint itself: 08:00-08:15 and 08:10-08:20 for one
    doctor, inserted from two transactions at once. One must fail."""
    doctor = make_doctor()
    verified_patient(client, sms, phone(1))
    verified_patient(client, sms, phone(2))
    p1, p2 = user_id(phone(1)), user_id(phone(2))

    def insert(pid, start, minutes):
        try:
            add_appointment(doctor.user_id, pid, start, minutes=minutes)
            return "ok"
        except IntegrityError:
            return "refused"
        except OperationalError as e:  # PostgreSQL may break the tie as a deadlock
            assert "deadlock" in str(e).lower(), e
            return "refused"

    outcome = parallel(
        lambda: insert(p1, MONDAY, 15),
        lambda: insert(p2, MONDAY + timedelta(minutes=10), 10),
    )
    assert sorted(outcome) == ["ok", "refused"], outcome
    assert overlaps() == 0


@pytest.mark.parametrize("round_", range(ROUNDS))
def test_slot_length_change_offset_starts_cannot_overlap(client, sms, round_):
    """A 15-min hold at 08:00, then the doctor moves to 10-min slots. 08:10
    overlaps it (everyone refused); 08:20 is free (exactly one wins)."""
    doctor = make_doctor()
    sessions = patients(client, sms, 9)
    assert hold(client, sessions[0], doctor, slot(0)).status_code == 201
    with Session(engine) as db:
        db.get(DoctorProfile, doctor.user_id).slot_minutes = 10
        db.commit()
    rest = sessions[1:]
    results = parallel(*[lambda i=i, s=s: hold(client, s, doctor, slot(1 + i % 2, 10)) for i, s in enumerate(rest)])
    at_0810 = [r.status_code for i, r in enumerate(results) if i % 2 == 0]
    at_0820 = [r.status_code for i, r in enumerate(results) if i % 2 == 1]
    assert set(at_0810) == {409}, at_0810
    assert sorted(at_0820) == [201] + [409] * (len(at_0820) - 1), at_0820
    assert overlaps() == 0


# --- R-25: one patient replacing their hold in parallel ----------------------


@pytest.mark.parametrize("round_", range(ROUNDS))
def test_one_patient_parallel_holds_same_doctor_keeps_one(client, sms, round_):
    doctor = make_doctor()
    s = verified_patient(client, sms, phone(0))
    results = parallel(*[lambda n=n: hold(client, s, doctor, slot(n)) for n in range(6)])
    assert all(r.status_code in (201, 409) for r in results), [r.status_code for r in results]
    assert open_holds(user_id(phone(0))) == 1
    assert overlaps() == 0


def test_one_patient_parallel_holds_two_doctors_keeps_one(client, sms):
    first = make_doctor()
    second = second_doctor()
    s = verified_patient(client, sms, phone(0))
    pid = user_id(phone(0))
    for n in range(ROUNDS * 2):
        results = parallel(
            lambda: hold(client, s, first, slot(n)),
            lambda: hold(client, s, second, slot(n)),
        )
        assert all(r.status_code == 201 for r in results), [r.status_code for r in results]
        assert open_holds(pid) == 1, f"round {n}: patient has {open_holds(pid)} open holds"


# --- R-26: hold racing with expiry --------------------------------------------


@pytest.mark.parametrize("round_", range(ROUNDS))
def test_expired_hold_owner_confirms_while_others_grab_the_slot(client, sms, round_):
    doctor = make_doctor()
    sessions = patients(client, sms, 6)
    owner, others = sessions[0], sessions[1:]
    h = hold(client, owner, doctor, slot(0)).json()
    expire_holds()
    confirm_owner = lambda: client.post(  # noqa: E731
        f"/v1/appointments/{h['id']}/confirm", json={"method": "clinic"}, headers=headers(owner)
    )
    results = parallel(confirm_owner, *[lambda s=s: hold(client, s, doctor, slot(0)) for s in others])
    assert results[0].status_code in (404, 409), results[0].text  # gone or hold_expired, never booked
    assert sorted(r.status_code for r in results[1:]) == [201] + [409] * (len(others) - 1)
    assert overlaps() == 0


@pytest.mark.parametrize("round_", range(ROUNDS))
def test_paid_webhook_for_expired_hold_races_new_hold(client, sms, chargily, round_):
    """Either the late payment confirms the old hold (newcomer refused) or the
    newcomer wins and the payment is flagged for refund. Never both, never
    money lost without a refund flag (a 500 is retried as Chargily would)."""
    doctor = make_doctor()
    owner = verified_patient(client, sms, phone(0))
    newcomer = verified_patient(client, sms, phone(1))
    h = hold(client, owner, doctor, slot(0)).json()
    co = client.post(f"/v1/appointments/{h['id']}/checkout", json={"method": "cib"}, headers=headers(owner))
    assert co.status_code == 201, co.text
    expire_holds()
    body = event("checkout.paid", "chk_1")
    hook, grab = parallel(lambda: send(client, body), lambda: hold(client, newcomer, doctor, slot(0)))
    if hook.status_code != 200:
        assert send(client, body).status_code == 200  # Chargily retry
    a = get_appointment(h["id"])
    with Session(engine) as db:
        p = db.query(Payment).filter(Payment.chargily_id == "chk_1").one()
        assert p.status == PaymentStatus.paid
    if a is not None and a.status == AppointmentStatus.confirmed:
        assert grab.status_code == 409
    else:
        assert grab.status_code == 201
        assert audits("payment.needs_refund", str(p.id)) == 1
    assert overlaps() == 0


# --- Confirm / release / cancel ----------------------------------------------


def test_confirm_racing_release_never_loses_a_confirmed_booking(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms, phone(0))
    for n in range(12):
        h = hold(client, s, doctor, slot(n)).json()
        conf, rel = parallel(
            lambda: client.post(f"/v1/appointments/{h['id']}/confirm", json={"method": "clinic"}, headers=headers(s)),
            lambda: client.delete(f"/v1/appointments/{h['id']}/hold", headers=headers(s)),
        )
        assert conf.status_code != 500 and rel.status_code != 500, (n, conf.status_code, rel.status_code)
        a = get_appointment(h["id"])
        if conf.status_code == 200:
            assert a is not None and a.status == AppointmentStatus.confirmed, f"round {n}: confirmed then deleted"
        assert overlaps() == 0


@pytest.mark.parametrize("round_", range(ROUNDS))
def test_confirm_racing_cancel_is_consistent(client, sms, round_):
    doctor = make_doctor()
    s = verified_patient(client, sms, phone(0))
    h = hold(client, s, doctor, slot(0)).json()
    conf, canc = parallel(
        lambda: client.post(f"/v1/appointments/{h['id']}/confirm", json={"method": "clinic"}, headers=headers(s)),
        lambda: client.post(f"/v1/appointments/{h['id']}/cancel", headers=headers(s)),
    )
    assert conf.status_code == 200, conf.text
    assert canc.status_code in (200, 409), canc.text
    a = get_appointment(h["id"])
    expected = AppointmentStatus.cancelled if canc.status_code == 200 else AppointmentStatus.confirmed
    assert a.status == expected
    assert overlaps() == 0


# --- Webhooks in parallel -----------------------------------------------------


@pytest.mark.parametrize("round_", range(ROUNDS))
def test_two_paid_webhooks_in_parallel_confirm_once(client, sms, chargily, round_):
    doctor = make_doctor()
    s = verified_patient(client, sms, phone(0))
    h = hold(client, s, doctor, slot(0)).json()
    assert client.post(f"/v1/appointments/{h['id']}/checkout", json={"method": "cib"},
                       headers=headers(s)).status_code == 201
    body = event("checkout.paid", "chk_1")
    results = parallel(lambda: send(client, body), lambda: send(client, body))
    assert [r.status_code for r in results] == [200, 200]
    a = get_appointment(h["id"])
    assert a.status == AppointmentStatus.confirmed and a.checkin_code
    assert audits("appointment.confirmed", h["id"]) == 1
    assert overlaps() == 0


def test_paid_webhook_racing_release_never_loses_the_money(client, sms, chargily):
    """Natural timing. Passes on the single-worker app because the async
    webhook holds the event loop; the window is shown by the slowed test below."""
    doctor = make_doctor()
    s = verified_patient(client, sms, phone(0))
    for n in range(12):
        h = hold(client, s, doctor, slot(n)).json()
        assert client.post(f"/v1/appointments/{h['id']}/checkout", json={"method": "cib"},
                           headers=headers(s)).status_code == 201
        chk = f"chk_{n + 1}"
        body = event("checkout.paid", chk)
        hook, _rel = parallel(lambda: send(client, body),
                              lambda: client.delete(f"/v1/appointments/{h['id']}/hold", headers=headers(s)))
        if hook.status_code != 200:
            assert send(client, body).status_code == 200  # Chargily retry
        with Session(engine) as db:
            p = db.query(Payment).filter(Payment.chargily_id == chk).one()
            pid = str(p.id)
            assert p.status == PaymentStatus.paid
        a = get_appointment(h["id"])
        kept = a is not None and a.status == AppointmentStatus.confirmed
        assert kept or audits("payment.needs_refund", pid) == 1, f"round {n}: paid, no booking, no refund flag"


# --- Same races with the release slowed down ----------------------------------
# release_hold loads the appointment, checks its status in memory, then
# deletes it by primary key. These tests widen the gap between the load and
# the delete (a sleep, as a slow request or GC pause would) so the other
# request reliably commits inside it.

GAP = 0.6


@pytest.fixture
def slow_release(monkeypatch):
    import inspect
    import time

    from app.routers import appointments as appt

    real = appt._mine

    def slowed(db, patient, appointment_id):
        a = real(db, patient, appointment_id)
        if inspect.stack()[1].function == "release_hold":
            time.sleep(GAP)
        return a

    monkeypatch.setattr(appt, "_mine", slowed)


def staggered(first, second, delay=GAP / 3):
    """Starts [first], then [second] a moment later, while [first] waits."""
    import time

    with ThreadPoolExecutor(max_workers=2) as pool:
        f1 = pool.submit(first)
        time.sleep(delay)
        f2 = pool.submit(second)
        return f1.result(), f2.result()


def test_paid_webhook_inside_release_gap_never_loses_the_money(client, sms, chargily, slow_release):
    doctor = make_doctor()
    s = verified_patient(client, sms, phone(0))
    h = hold(client, s, doctor, slot(0)).json()
    assert client.post(f"/v1/appointments/{h['id']}/checkout", json={"method": "cib"},
                       headers=headers(s)).status_code == 201
    rel, hook = staggered(
        lambda: client.delete(f"/v1/appointments/{h['id']}/hold", headers=headers(s)),
        lambda: send(client, event("checkout.paid", "chk_1")),
    )
    assert hook.status_code == 200
    with Session(engine) as db:
        p = db.query(Payment).filter(Payment.chargily_id == "chk_1").one()
        pid, paid = str(p.id), p.status == PaymentStatus.paid
    a = get_appointment(h["id"])
    kept = a is not None and a.status == AppointmentStatus.confirmed
    assert paid
    assert kept or audits("payment.needs_refund", pid) == 1, (
        f"release={rel.status_code}: payment paid, appointment gone, no refund flag"
    )


def test_confirm_inside_release_gap_keeps_the_booking(client, sms, slow_release):
    doctor = make_doctor()
    s = verified_patient(client, sms, phone(0))
    h = hold(client, s, doctor, slot(0)).json()
    rel, conf = staggered(
        lambda: client.delete(f"/v1/appointments/{h['id']}/hold", headers=headers(s)),
        lambda: client.post(f"/v1/appointments/{h['id']}/confirm", json={"method": "clinic"}, headers=headers(s)),
    )
    assert conf.status_code == 200, conf.text
    a = get_appointment(h["id"])
    assert a is not None and a.status == AppointmentStatus.confirmed, (
        f"confirm said 200 with code {conf.json()['checkin_code'] is not None}, release said {rel.status_code}, row gone"
    )
