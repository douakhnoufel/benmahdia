import uuid
from datetime import timedelta

from sqlalchemy.orm import Session

from app.clock import clock
from app.db import engine
from app.alerts_job import missed_dose_alerts
from app.models import Alert

from .booking_helpers import add_appointment, make_doctor, verified_patient
from .conftest import bearer
from .test_medications import linked_patient, prescribe, staff_session
from .test_staff import other_doctor


def add_addiction(client, s, **over):
    body = {"type": "cannabis", "substance": "haschich",
            "clean_since": "2026-10-07T18:00:00Z"} | over
    return client.post("/v1/me/addictions", json=body, headers=bearer(s)).json()


def relapse(client, s, a, **body):
    return client.post(f"/v1/me/addictions/{a['id']}/relapses", json=body, headers=bearer(s))


def setup(client, sms, phone="0661234567"):
    doctor = make_doctor()
    return doctor, staff_session(client, doctor), linked_patient(client, sms, doctor, phone)


def test_requires_doctor(client, sms):
    doctor, doc, s = setup(client, sms)
    url = f"/v1/staff/patients/{s['user']['id']}/addictions"
    assert client.get(url).status_code == 401
    assert client.get(url, headers=bearer(s)).status_code == 403
    assert client.get("/v1/staff/alerts").status_code == 401
    assert client.get("/v1/staff/alerts", headers=bearer(s)).status_code == 403


def test_doctor_reads_and_confirms_addictions(client, sms):
    _, doc, s = setup(client, sms)
    a = add_addiction(client, s)
    relapse(client, s, a, at="2026-10-12T10:00:00Z", note="soirée")
    url = f"/v1/staff/patients/{s['user']['id']}/addictions"
    [row] = client.get(url, headers=bearer(doc)).json()
    assert row["review_status"] == "pending" and row["type"] == "cannabis"
    assert row["relapses"] == [{"at": "2026-10-12T10:00:00Z", "note": "soirée"}]
    r = client.post(f"{url}/{a['id']}/confirm", headers=bearer(doc))
    assert r.status_code == 200 and r.json()["review_status"] == "confirmed"
    mine = client.get("/v1/me/addictions", headers=bearer(s)).json()
    assert mine[0]["review_status"] == "confirmed"


def test_rejected_addiction_leaves_the_patients_list(client, sms):
    _, doc, s = setup(client, sms)
    a = add_addiction(client, s)
    url = f"/v1/staff/patients/{s['user']['id']}/addictions/{a['id']}"
    assert client.post(f"{url}/reject", headers=bearer(doc)).json()["review_status"] == "rejected"
    assert client.get("/v1/me/addictions", headers=bearer(s)).json() == []
    # The doctor still sees it, and can change their mind.
    assert len(client.get(f"/v1/staff/patients/{s['user']['id']}/addictions", headers=bearer(doc)).json()) == 1
    assert client.post(f"{url}/confirm", headers=bearer(doc)).json()["review_status"] == "confirmed"


def test_doctor_only_reaches_own_patients(client, sms):
    _, doc, _ = setup(client, sms)
    stranger = verified_patient(client, sms, "0771234567")
    # Booked with another doctor only, so their recovery is open (PRD 5).
    add_appointment(other_doctor(), uuid.UUID(stranger["user"]["id"]), clock.now() - timedelta(days=3))
    a = add_addiction(client, stranger)
    url = f"/v1/staff/patients/{stranger['user']['id']}/addictions"
    assert client.get(url, headers=bearer(doc)).status_code == 404
    assert client.post(f"{url}/{a['id']}/confirm", headers=bearer(doc)).status_code == 404


def test_addiction_of_another_patient_is_not_found(client, sms):
    doctor, doc, s = setup(client, sms)
    other = linked_patient(client, sms, doctor, "0771234567")
    a = add_addiction(client, other)
    url = f"/v1/staff/patients/{s['user']['id']}/addictions/{a['id']}/confirm"
    assert client.post(url, headers=bearer(doc)).status_code == 404
    unknown = f"/v1/staff/patients/{s['user']['id']}/addictions/{uuid.uuid4()}/confirm"
    assert client.post(unknown, headers=bearer(doc)).status_code == 404


def test_relapse_alert_reaches_the_doctor_and_can_be_read(client, sms):
    _, doc, s = setup(client, sms)
    a = add_addiction(client, s)
    relapse(client, s, a)
    [alert] = client.get("/v1/staff/alerts", headers=bearer(doc)).json()
    assert alert["type"] == "relapse" and alert["priority"] == "high"
    assert alert["read"] is False and alert["patient_id"] == s["user"]["id"]
    assert "note" not in alert
    r = client.post(f"/v1/staff/alerts/{alert['id']}/read", headers=bearer(doc))
    assert r.status_code == 200 and r.json()["read"] is True
    assert client.get("/v1/staff/alerts", params={"unread": True}, headers=bearer(doc)).json() == []
    assert len(client.get("/v1/staff/alerts", headers=bearer(doc)).json()) == 1


def test_a_doctor_sees_only_their_own_alerts(client, sms):
    _, doc, s = setup(client, sms)
    a = add_addiction(client, s)
    relapse(client, s, a)
    with Session(engine) as db:
        alert = db.query(Alert).one()
        alert_id = str(alert.id)
        from app.models import DoctorProfile, Role, User
        other = User(role=Role.doctor, email="autre@example.invalid")
        db.add(other)
        db.flush()
        db.add(DoctorProfile(user_id=other.id, name_ar="د", name_fr="Dr Autre",
                             slot_minutes=15, price_dzd=2000))
        db.commit()
        from app import security
        other.password_hash = security.hash_password("autre-pass-2026")
        db.commit()
    other_doc = client.post("/v1/staff/login",
                            json={"email": "autre@example.invalid", "password": "autre-pass-2026"}).json()
    assert client.get("/v1/staff/alerts", headers=bearer(other_doc)).json() == []
    assert client.post(f"/v1/staff/alerts/{alert_id}/read", headers=bearer(other_doc)).status_code == 404


def _two_missed_days(client, sms):
    """A medicine started a week ago; the patient answered nothing."""
    _, doc, s = setup(client, sms)
    prescribe(client, doc, s)
    return doc, s


def test_two_missed_days_alert_the_prescriber_once_a_day(client, sms):
    doc, s = _two_missed_days(client, sms)
    with Session(engine) as db:
        assert missed_dose_alerts(db) == 1
        assert missed_dose_alerts(db) == 0  # same day: no second alert
    [alert] = client.get("/v1/staff/alerts", headers=bearer(doc)).json()
    assert alert["type"] == "missed_doses" and alert["patient_id"] == s["user"]["id"]
    # Next day, still nothing taken: the doctor hears again.
    clock.frozen = clock.frozen + timedelta(days=1)
    with Session(engine) as db:
        assert missed_dose_alerts(db) == 1


def test_no_alert_when_a_dose_was_taken_or_the_course_is_new(client, sms):
    doctor, doc, s = setup(client, sms)
    med = prescribe(client, doc, s).json()
    # Taken yesterday (2026-10-16): only one missed day in a row.
    client.put("/v1/me/doses", headers=bearer(s),
               json={"medication_id": med["id"], "day": "2026-10-16", "time": "08:00", "status": "taken"})
    with Session(engine) as db:
        assert missed_dose_alerts(db) == 0
    # A course that started yesterday has had one day only.
    prescribe(client, doc, s, name="Autre", start_date="2026-10-16")
    with Session(engine) as db:
        assert missed_dose_alerts(db) == 0


def test_no_alert_for_a_stopped_medicine(client, sms):
    doc, s = _two_missed_days(client, sms)
    url = f"/v1/staff/patients/{s['user']['id']}/medications"
    [med] = client.get(url, headers=bearer(doc)).json()
    client.delete(f"{url}/{med['id']}", headers=bearer(doc))
    with Session(engine) as db:
        assert missed_dose_alerts(db) == 0


