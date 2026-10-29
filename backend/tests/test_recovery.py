import itertools
import uuid
from datetime import timedelta

from sqlalchemy.orm import Session

from app.clock import clock
from app.db import engine
from app.models import Alert

from .booking_helpers import add_appointment, make_doctor, verified_patient
from .conftest import bearer, register

CLEAN_SINCE = "2026-10-07T18:00:00Z"  # 10 days before the frozen clock


_slots = itertools.count()


def unlocked(client, sms, phone="0661234567") -> dict:
    """A patient past their first confirmed appointment, so recovery is open
    (PRD 5). Each gets a slot of their own."""
    s = register(client, sms, phone)
    at = clock.now() - timedelta(days=3) + timedelta(minutes=15 * next(_slots))
    add_appointment(make_doctor().user_id, uuid.UUID(s["user"]["id"]), at)
    return s


def add(client, session, **over):
    body = {"type": "cannabis", "substance": "haschich", "clean_since": CLEAN_SINCE} | over
    return client.post("/v1/me/addictions", json=body, headers=bearer(session))


def test_requires_login(client):
    assert client.get("/v1/me/addictions").status_code == 401
    assert client.post("/v1/me/addictions", json={}).status_code == 401


def test_locked_until_the_first_confirmed_appointment(client, sms):
    from app.models import AppointmentStatus

    s = register(client, sms)
    r = client.get("/v1/me/addictions", headers=bearer(s))
    assert r.status_code == 403 and r.json()["detail"]["code"] == "recovery_locked"
    # An unpaid hold or a cancelled appointment does not unlock it.
    pid, doctor = uuid.UUID(s["user"]["id"]), make_doctor().user_id
    add_appointment(doctor, pid, clock.now() + timedelta(days=3), status=AppointmentStatus.awaiting_payment,
                    hold_expires_at=clock.now() + timedelta(minutes=10))
    add_appointment(doctor, pid, clock.now() - timedelta(days=3), status=AppointmentStatus.cancelled)
    assert add(client, s).json()["detail"]["code"] == "recovery_locked"
    add_appointment(doctor, pid, clock.now() - timedelta(days=2))
    assert add(client, s).status_code == 201


def test_add_and_list(client, sms):
    s = unlocked(client, sms)
    r = add(client, s)
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["type"] == "cannabis"
    assert body["substance"] == "haschich"
    assert body["review_status"] == "pending"
    assert body["clean_since"] == CLEAN_SINCE
    assert body["longest_past_days"] == 0 and body["past_days"] == 0
    listed = client.get("/v1/me/addictions", headers=bearer(s)).json()
    assert [a["id"] for a in listed] == [body["id"]]


def test_unverified_patient_can_track(client, sms):
    # Tracking needs a confirmed appointment, not the clinic's ID approval.
    s = unlocked(client, sms)
    assert add(client, s).status_code == 201


def test_substance_is_optional_and_trimmed(client, sms):
    s = unlocked(client, sms)
    r = add(client, s, substance="  ")
    assert r.status_code == 201
    assert r.json()["substance"] is None


def test_rejects_bad_input(client, sms):
    s = unlocked(client, sms)
    assert add(client, s, type="coffee").status_code == 422
    assert add(client, s, clean_since="2026-10-25T00:00:00Z").status_code == 422
    assert add(client, s, substance="x" * 101).status_code == 422


def test_limit_of_addictions(client, sms):
    s = unlocked(client, sms)
    for _ in range(10):
        assert add(client, s).status_code == 201
    r = add(client, s)
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "too_many_addictions"


def test_patient_sees_only_own_addictions(client, sms):
    a = unlocked(client, sms, "0661234567")
    b = unlocked(client, sms, "0771234567")
    mine = add(client, a).json()
    assert client.get("/v1/me/addictions", headers=bearer(b)).json() == []
    # Another patient's id looks like it does not exist.
    r = client.post(
        f"/v1/me/addictions/{mine['id']}/relapses", json={}, headers=bearer(b)
    )
    assert r.status_code == 404


def test_relapse_restarts_counter_and_keeps_history(client, sms):
    s = unlocked(client, sms)
    a = add(client, s, clean_since="2026-09-25T09:00:00Z").json()
    url = f"/v1/me/addictions/{a['id']}/relapses"
    at = "2026-10-03T09:30:00Z"  # 8 days after clean_since
    r = client.post(url, json={"at": at, "note": "soirée"}, headers=bearer(s))
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["clean_since"] == at
    assert body["past_days"] == 8
    assert body["longest_past_days"] == 8
    # A second, shorter streak: the longest stays, the total grows.
    r = client.post(url, json={"at": "2026-10-06T09:30:00Z"}, headers=bearer(s))
    body = r.json()
    assert body["past_days"] == 11
    assert body["longest_past_days"] == 8


def test_relapse_defaults_to_now(client, sms):
    s = unlocked(client, sms)
    a = add(client, s).json()
    r = client.post(f"/v1/me/addictions/{a['id']}/relapses", json={}, headers=bearer(s))
    assert r.status_code == 201
    assert r.json()["clean_since"] == "2026-10-17T18:00:00Z"
    assert r.json()["past_days"] == 10


def test_relapse_time_checks(client, sms):
    s = unlocked(client, sms)
    a = add(client, s).json()
    url = f"/v1/me/addictions/{a['id']}/relapses"
    before = client.post(url, json={"at": "2026-10-01T00:00:00Z"}, headers=bearer(s))
    assert before.status_code == 422
    assert before.json()["detail"]["code"] == "relapse_before_start"
    future = client.post(url, json={"at": "2026-10-20T00:00:00Z"}, headers=bearer(s))
    assert future.status_code == 422
    assert client.post(url, json={"note": "x" * 501}, headers=bearer(s)).status_code == 422


def test_relapse_alerts_the_patients_doctor_without_medical_content(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    add_appointment(doctor.user_id, uuid.UUID(s["user"]["id"]), clock.now() - timedelta(days=3))
    a = add(client, s).json()
    client.post(f"/v1/me/addictions/{a['id']}/relapses", json={"note": "secret"}, headers=bearer(s))
    with Session(engine) as db:
        alerts = db.query(Alert).all()
        assert len(alerts) == 1
        alert = alerts[0]
        assert alert.doctor_id == doctor.user_id
        assert str(alert.patient_id) == s["user"]["id"]
        assert alert.type == "relapse" and alert.read is False
        assert "secret" not in repr(vars(alert))


def test_relapse_alert_skips_a_doctor_the_patient_only_holds_a_slot_with(client, sms):
    # An unpaid hold does not make someone the patient's doctor, so the alert goes to the doctor of the paid visit.
    from app.models import AppointmentStatus

    from .test_staff import other_doctor

    paid, held = make_doctor(), other_doctor()
    s = verified_patient(client, sms)
    pid = uuid.UUID(s["user"]["id"])
    add_appointment(paid.user_id, pid, clock.now() - timedelta(days=3))
    add_appointment(held, pid, clock.now() + timedelta(days=2), status=AppointmentStatus.awaiting_payment)
    a = add(client, s).json()
    client.post(f"/v1/me/addictions/{a['id']}/relapses", json={}, headers=bearer(s))
    with Session(engine) as db:
        assert [x.doctor_id for x in db.query(Alert).all()] == [paid.user_id]


def test_relapse_is_locked_before_the_first_confirmed_appointment(client, sms):
    # Recovery opens with the first paid visit (PRD 5), so a patient with no
    # doctor yet cannot reach the relapse route, and no doctor is alerted.
    s = register(client, sms)
    r = client.post(f"/v1/me/addictions/{uuid.uuid4()}/relapses", json={}, headers=bearer(s))
    assert r.status_code == 403 and r.json()["detail"]["code"] == "recovery_locked"
    with Session(engine) as db:
        assert db.query(Alert).count() == 0


def test_staff_cannot_use_patient_routes(client, sms):
    from app.models import Role, User

    s = register(client, sms)
    with Session(engine) as db:
        user = db.get(User, uuid.UUID(s["user"]["id"]))
        user.role = Role.doctor
        db.commit()
    assert client.get("/v1/me/addictions", headers=bearer(s)).status_code == 403
