from datetime import datetime

from sqlalchemy.orm import Session

from app import security
from app.db import engine
from app.models import AccountStatus, AppointmentStatus, DoctorProfile, PaymentMethod, Role, User

from .booking_helpers import add_appointment, make_doctor, user_id, verified_patient
from .conftest import advance, bearer, register

EMAIL = "dr.benmahdia@example.invalid"
PASSWORD = "clinique2026"
MONDAY_9 = datetime(2026, 10, 19, 8, 0)   # 09:00 Algiers


def doctor_with_password(email=EMAIL):
    profile = make_doctor()
    with Session(engine) as db:
        user = db.get(User, profile.user_id)
        user.password_hash = security.hash_password(PASSWORD)
        db.commit()
    return profile


def other_doctor():
    with Session(engine) as db:
        user = User(role=Role.doctor, email="other@example.invalid",
                    password_hash=security.hash_password(PASSWORD))
        db.add(user)
        db.flush()
        db.add(DoctorProfile(user_id=user.id, name_ar="د", name_fr="Dr Autre", price_dzd=1500))
        db.commit()
        return user.id


def login(client, email=EMAIL, password=PASSWORD):
    return client.post("/v1/staff/login", json={"email": email, "password": password})


def doc_headers(client, email=EMAIL):
    r = login(client, email)
    assert r.status_code == 200, r.text
    return bearer(r.json())


# --- login ------------------------------------------------------------------


def test_staff_login(client):
    doctor_with_password()
    r = login(client, "DR.Benmahdia@example.invalid")
    assert r.status_code == 200
    assert r.json()["user"]["role"] == "doctor"


def test_staff_login_wrong_password_and_lockout(client):
    doctor_with_password()
    for _ in range(5):
        r = login(client, password="wrong")
    assert r.status_code == 401
    r = login(client)
    assert (r.status_code, r.json()["detail"]["code"]) == (423, "account_locked")


def test_patient_cannot_use_staff_login_or_routes(client, sms):
    session = verified_patient(client, sms)
    assert client.get("/v1/staff/agenda", headers=bearer(session)).status_code == 403
    assert login(client, "patient@example.com").status_code == 401


def test_doctor_cannot_use_patient_routes(client):
    doctor_with_password()
    assert client.get("/v1/appointments", headers=doc_headers(client)).status_code == 403


# --- agenda -------------------------------------------------------------------


def test_agenda_shows_every_doctors_booked_visits_of_the_day(client, sms):
    # PRD 3: appointments and agendas are visible to every doctor in the clinic.
    doc = doctor_with_password()
    other = other_doctor()
    verified_patient(client, sms)
    me = user_id()
    add_appointment(doc.user_id, me, MONDAY_9)
    add_appointment(doc.user_id, me, datetime(2026, 10, 19, 8, 15), status=AppointmentStatus.awaiting_payment)
    add_appointment(doc.user_id, me, datetime(2026, 10, 20, 8, 0))
    add_appointment(other, me, datetime(2026, 10, 19, 8, 30))
    r = client.get("/v1/staff/agenda?day=2026-10-19", headers=doc_headers(client))
    assert r.status_code == 200
    item, theirs = r.json()
    assert theirs["start"] == "2026-10-19T08:30:00Z"
    assert item["start"] == "2026-10-19T08:00:00Z"
    assert item["patient_phone"] == "+213661234567"
    assert (item["status"], item["paid"]) == ("confirmed", False)


def test_agenda_rows_say_whose_visit_it_is(client, sms):
    # Only the visit's own doctor can act on it, so the row must say so.
    doc = doctor_with_password()
    other = other_doctor()
    verified_patient(client, sms)
    me = user_id()
    add_appointment(doc.user_id, me, MONDAY_9)
    add_appointment(other, me, datetime(2026, 10, 19, 8, 30))
    mine, theirs = client.get("/v1/staff/agenda?day=2026-10-19", headers=doc_headers(client)).json()
    assert (mine["mine"], mine["doctor_name_fr"]) == (True, "Dr Benmahdia Hocine")
    assert (theirs["mine"], theirs["doctor_name_fr"]) == (False, "Dr Autre")
    mine, theirs = client.get(
        "/v1/staff/agenda?day=2026-10-19", headers=doc_headers(client, "other@example.invalid")
    ).json()
    assert (mine["mine"], theirs["mine"]) == (False, True)


def test_agenda_needs_a_login(client):
    assert client.get("/v1/staff/agenda").status_code == 401


# --- status -----------------------------------------------------------------------


def test_mark_completed_or_no_show_after_start(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    a = add_appointment(doc.user_id, user_id(), datetime(2026, 10, 17, 17, 0))  # an hour ago
    h = doc_headers(client)
    r = client.post(f"/v1/staff/appointments/{a.id}/status", json={"status": "completed"}, headers=h)
    assert r.status_code == 200 and r.json()["status"] == "completed"
    r = client.post(f"/v1/staff/appointments/{a.id}/status", json={"status": "no_show"}, headers=h)
    assert r.json()["status"] == "no_show"


def test_cannot_mark_a_future_or_someone_elses_visit(client, sms):
    doc = doctor_with_password()
    other = other_doctor()
    verified_patient(client, sms)
    future = add_appointment(doc.user_id, user_id(), MONDAY_9)
    theirs = add_appointment(other, user_id(), datetime(2026, 10, 17, 17, 0))
    h = doc_headers(client)
    r = client.post(f"/v1/staff/appointments/{future.id}/status", json={"status": "completed"}, headers=h)
    assert (r.status_code, r.json()["detail"]["code"]) == (409, "not_started")
    r = client.post(f"/v1/staff/appointments/{theirs.id}/status", json={"status": "completed"}, headers=h)
    assert r.status_code == 404


# --- paid ---------------------------------------------------------------------------


def test_mark_clinic_payment_paid_and_unpaid(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    a = add_appointment(doc.user_id, user_id(), MONDAY_9)
    h = doc_headers(client)
    r = client.post(f"/v1/staff/appointments/{a.id}/paid", json={"paid": True}, headers=h)
    assert r.status_code == 200 and r.json()["paid"] is True
    r = client.post(f"/v1/staff/appointments/{a.id}/paid", json={"paid": False}, headers=h)
    assert r.json()["paid"] is False


def test_card_payments_are_set_only_by_chargily(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    a = add_appointment(doc.user_id, user_id(), MONDAY_9, method=PaymentMethod.cib)
    r = client.post(f"/v1/staff/appointments/{a.id}/paid", json={"paid": True}, headers=doc_headers(client))
    assert (r.status_code, r.json()["detail"]["code"]) == (409, "paid_by_card")


# --- patients -----------------------------------------------------------------------


def test_patients_are_only_those_who_booked_with_me(client, sms):
    doc = doctor_with_password()
    other = other_doctor()
    verified_patient(client, sms, "0661111111")
    verified_patient(client, sms, "0662222222")
    add_appointment(doc.user_id, user_id("0661111111"), datetime(2026, 9, 1, 8, 0),
                    status=AppointmentStatus.completed)
    add_appointment(doc.user_id, user_id("0661111111"), MONDAY_9)
    add_appointment(other, user_id("0662222222"), MONDAY_9)
    [p] = client.get("/v1/staff/patients", headers=doc_headers(client)).json()
    assert p["phone"] == "+213661111111"
    assert (p["visits"], p["last_visit"], p["next_visit"]) == (1, "2026-09-01T08:00:00Z", "2026-10-19T08:00:00Z")


# --- signups ------------------------------------------------------------------------


def test_signups_list_and_approve(client, sms):
    from .test_identity import declare
    doctor_with_password()
    declare(client, register(client, sms, "0661111111"))
    verified_patient(client, sms, "0662222222")
    h = doc_headers(client)
    [s] = client.get("/v1/staff/signups", headers=h).json()
    assert s["phone"] == "+213661111111"
    r = client.post(f"/v1/staff/signups/{s['id']}/approve", headers=h)
    assert r.status_code == 200
    with Session(engine) as db:
        assert db.get(User, user_id("0661111111")).status == AccountStatus.verified
    assert client.get("/v1/staff/signups", headers=h).json() == []
    assert client.post(f"/v1/staff/signups/{s['id']}/approve", headers=h).status_code == 404


def test_reject_signup(client, sms):
    doctor_with_password()
    register(client, sms)
    h = doc_headers(client)
    [s] = client.get("/v1/staff/signups", headers=h).json()
    assert client.post(f"/v1/staff/signups/{s['id']}/reject", headers=h).status_code == 200
    with Session(engine) as db:
        assert db.get(User, user_id()).status == AccountStatus.rejected


def test_approved_patient_can_then_book(client, sms):
    from .test_identity import declare
    doc = doctor_with_password()
    session = register(client, sms)
    declare(client, session)
    h = doc_headers(client)
    [s] = client.get("/v1/staff/signups", headers=h).json()
    client.post(f"/v1/staff/signups/{s['id']}/approve", headers=h)
    r = client.get("/v1/doctors", headers=bearer(session))
    assert r.status_code == 200 and r.json()[0]["id"] == str(doc.user_id)


# --- me -----------------------------------------------------------------------


def make_super_admin(email="admin@example.invalid"):
    with Session(engine) as db:
        user = User(role=Role.super_admin, email=email, password_hash=security.hash_password(PASSWORD))
        db.add(user)
        db.flush()
        db.add(DoctorProfile(user_id=user.id, name_ar="د. مدير", name_fr="Dr Admin", price_dzd=2500))
        db.commit()
        return user.id


def test_me_says_who_is_signed_in(client):
    doc = doctor_with_password()
    r = client.get("/v1/staff/me", headers=doc_headers(client))
    assert r.status_code == 200
    assert r.json() == {"id": str(doc.user_id), "role": "doctor",
                        "name_ar": "د. بن مهدية حسين", "name_fr": "Dr Benmahdia Hocine"}


def test_me_for_the_super_admin(client):
    admin = make_super_admin()
    r = client.get("/v1/staff/me", headers=doc_headers(client, "admin@example.invalid"))
    assert (r.json()["id"], r.json()["role"]) == (str(admin), "super_admin")


def test_me_is_for_staff_only(client, sms):
    assert client.get("/v1/staff/me").status_code == 401
    session = verified_patient(client, sms)
    assert client.get("/v1/staff/me", headers=bearer(session)).status_code == 403
