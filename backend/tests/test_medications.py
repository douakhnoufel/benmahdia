import uuid
from datetime import timedelta

from sqlalchemy.orm import Session

from app.clock import clock
from app.db import engine
from app.models import Quote, Role, User

from .booking_helpers import add_appointment, make_doctor, verified_patient
from .conftest import bearer, register

TODAY = "2026-10-17"  # frozen clock: 2026-10-17 18:00 UTC = 19:00 in Algiers
MED = {
    "name": "Sertraline",
    "amount": "50 mg",
    "times": ["20:00", "08:00"],
    "start_date": "2026-10-10",
    "end_date": None,
    "instructions": "Après le repas",
}


def staff_session(client, doctor) -> dict:
    with Session(engine) as db:
        user = db.get(User, doctor.user_id)
        user.password_hash = __import__("app.security", fromlist=["x"]).hash_password("doc-pass-2026")
        email = user.email
        db.commit()
    r = client.post("/v1/staff/login", json={"email": email, "password": "doc-pass-2026"})
    assert r.status_code == 200, r.text
    return r.json()


def linked_patient(client, sms, doctor, phone="0661234567") -> dict:
    s = verified_patient(client, sms, phone)
    add_appointment(doctor.user_id, uuid.UUID(s["user"]["id"]), clock.now() - timedelta(days=3))
    return s


def prescribe(client, doc, patient, **over):
    body = MED | over
    return client.post(
        f"/v1/staff/patients/{patient['user']['id']}/medications", json=body, headers=bearer(doc)
    )


def doses(client, s, day=None):
    params = {"day": day} if day else {}
    return client.get("/v1/me/doses", params=params, headers=bearer(s))


def test_requires_login(client):
    assert doses(client, {"access_token": "x"}).status_code == 401
    assert client.get("/v1/me/quote").status_code == 401
    assert client.put("/v1/me/doses", json={}).status_code == 401


def test_doctor_prescribes_and_patient_sees_sorted_doses(client, sms):
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    s = linked_patient(client, sms, doctor)
    r = prescribe(client, doc, s)
    assert r.status_code == 201, r.text
    assert r.json()["times"] == ["08:00", "20:00"]
    items = doses(client, s).json()
    assert [(d["time"], d["status"], d["name"], d["amount"]) for d in items] == [
        ("08:00", "due", "Sertraline", "50 mg"),
        ("20:00", "due", "Sertraline", "50 mg"),
    ]
    assert items[0]["instruction"] == "Après le repas"


def test_mark_dose_taken_then_skipped(client, sms):
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    s = linked_patient(client, sms, doctor)
    med = prescribe(client, doc, s).json()
    put = lambda status: client.put(  # noqa: E731
        "/v1/me/doses",
        json={"medication_id": med["id"], "day": TODAY, "time": "08:00", "status": status},
        headers=bearer(s),
    )
    r = put("taken")
    assert r.status_code == 200 and r.json()["status"] == "taken"
    assert [d["status"] for d in doses(client, s).json()] == ["taken", "due"]
    assert put("skipped").json()["status"] == "skipped"  # changing one's mind is allowed
    assert [d["status"] for d in doses(client, s).json()] == ["skipped", "due"]


def test_dose_checks(client, sms):
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    s = linked_patient(client, sms, doctor)
    med = prescribe(client, doc, s).json()
    base = {"medication_id": med["id"], "day": TODAY, "time": "08:00", "status": "taken"}
    put = lambda **o: client.put("/v1/me/doses", json=base | o, headers=bearer(s))  # noqa: E731
    assert put(time="09:00").status_code == 422  # not one of the prescribed times
    assert put(status="due").status_code == 422
    assert put(day="2026-10-09").status_code == 422  # before the start date
    assert put(day="2026-10-22").status_code == 422  # too far ahead
    assert put(medication_id=str(uuid.uuid4())).status_code == 404


def test_past_unlogged_doses_are_missed(client, sms):
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    s = linked_patient(client, sms, doctor)
    prescribe(client, doc, s)
    assert {d["status"] for d in doses(client, s, "2026-10-16").json()} == {"missed"}


def test_ended_or_future_medication_is_not_listed(client, sms):
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    s = linked_patient(client, sms, doctor)
    prescribe(client, doc, s, end_date="2026-10-15")
    prescribe(client, doc, s, start_date="2026-10-20")
    assert doses(client, s).json() == []


def test_patient_sees_only_own_medications(client, sms):
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    a = linked_patient(client, sms, doctor, "0661234567")
    b = linked_patient(client, sms, doctor, "0771234567")
    med = prescribe(client, doc, a).json()
    assert doses(client, b).json() == []
    r = client.put(
        "/v1/me/doses",
        json={"medication_id": med["id"], "day": TODAY, "time": "08:00", "status": "taken"},
        headers=bearer(b),
    )
    assert r.status_code == 404


def test_doctor_only_reaches_own_patients(client, sms):
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    stranger = verified_patient(client, sms)  # never booked with this doctor
    assert prescribe(client, doc, stranger).status_code == 404
    url = f"/v1/staff/patients/{stranger['user']['id']}/medications"
    assert client.get(url, headers=bearer(doc)).status_code == 404
    # A patient cannot use the doctor's routes.
    assert prescribe(client, stranger, stranger).status_code == 403


def test_prescription_validation(client, sms):
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    s = linked_patient(client, sms, doctor)
    for over in (
        {"times": []},
        {"times": ["8:00"]},
        {"times": ["08:00", "08:00"]},
        {"times": [f"{h:02d}:00" for h in range(7)]},
        {"name": " "},
        {"end_date": "2026-10-01"},
    ):
        assert prescribe(client, doc, s, **over).status_code == 422, over


def test_doctor_lists_and_stops_a_medication(client, sms):
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    s = linked_patient(client, sms, doctor)
    med = prescribe(client, doc, s).json()
    url = f"/v1/staff/patients/{s['user']['id']}/medications"
    assert [m["id"] for m in client.get(url, headers=bearer(doc)).json()] == [med["id"]]
    assert client.delete(f"{url}/{med['id']}", headers=bearer(doc)).status_code == 204
    assert client.get(url, headers=bearer(doc)).json() == []
    assert doses(client, s).json() == []
    assert client.delete(f"{url}/{med['id']}", headers=bearer(doc)).status_code == 404


def test_quote_of_the_day_is_stable_and_changes_daily(client, sms):
    s = register(client, sms)
    with Session(engine) as db:
        for i in range(3):
            db.add(Quote(text_ar=f"ع{i}", text_fr=f"fr{i}"))
        db.commit()
    first = client.get("/v1/me/quote", headers=bearer(s)).json()
    assert client.get("/v1/me/quote", headers=bearer(s)).json() == first
    clock.frozen = clock.frozen + timedelta(days=1)
    s2 = client.post("/v1/auth/login", json={"phone": "0661234567", "password": "sobre2026"}).json()
    assert client.get("/v1/me/quote", headers=bearer(s2)).json() != first


def test_quote_prefers_the_patients_addiction_types(client, sms):
    s = register(client, sms)
    client.post("/v1/me/addictions", json={"type": "alcohol", "clean_since": "2026-10-01T00:00:00Z"},
                headers=bearer(s))
    with Session(engine) as db:
        db.add(Quote(text_ar="ك", text_fr="cannabis", addiction_type="cannabis"))
        db.add(Quote(text_ar="خ", text_fr="alcool", addiction_type="alcohol"))
        db.add(Quote(text_ar="ع", text_fr="générale"))
        db.commit()
    seen = set()
    for _ in range(4):
        seen.add(client.get("/v1/me/quote", headers=bearer(s)).json()["text_fr"])
        clock.frozen = clock.frozen + timedelta(days=1)
        s = client.post("/v1/auth/login", json={"phone": "0661234567", "password": "sobre2026"}).json()
    assert "cannabis" not in seen and seen <= {"alcool", "générale"}


def test_no_quote_is_a_404(client, sms):
    s = register(client, sms)
    r = client.get("/v1/me/quote", headers=bearer(s))
    assert r.status_code == 404 and r.json()["detail"]["code"] == "no_quote"


def test_seed_quotes_exist_once(client):
    from app.quotes_seed import seed_quotes

    with Session(engine) as db:
        seed_quotes(db)
        seed_quotes(db)
        total = db.query(Quote).count()
        assert 5 <= total <= 12
        assert db.query(Quote).filter(Quote.text_ar == "", Quote.text_fr == "").count() == 0


def test_patient_role_check(client, sms):
    s = register(client, sms)
    with Session(engine) as db:
        db.get(User, uuid.UUID(s["user"]["id"])).role = Role.doctor
        db.commit()
    assert doses(client, s).status_code == 403
    assert client.get("/v1/me/quote", headers=bearer(s)).status_code == 403
