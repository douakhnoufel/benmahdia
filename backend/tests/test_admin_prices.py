from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import engine
from app.models import Appointment, AuditLog

from .booking_helpers import add_appointment, user_id, verified_patient
from .conftest import bearer
from .test_appointments import hold
from .test_staff import doc_headers, doctor_with_password, make_super_admin

ADMIN = "admin@example.invalid"


def price_url(doctor_id):
    return f"/v1/admin/doctors/{doctor_id}/price"


def test_super_admin_lists_every_doctor(client):
    doc = doctor_with_password()
    admin = make_super_admin()
    r = client.get("/v1/admin/doctors", headers=doc_headers(client, ADMIN))
    assert r.status_code == 200
    assert [(d["id"], d["name_fr"], d["price_dzd"]) for d in r.json()] == [
        (str(admin), "Dr Admin", 2500),
        (str(doc.user_id), "Dr Benmahdia Hocine", 2000),
    ]


def test_new_price_applies_to_new_bookings_only(client, sms):
    doc = doctor_with_password()
    make_super_admin()
    session = verified_patient(client, sms)
    earlier = add_appointment(doc.user_id, user_id(), datetime(2026, 10, 20, 8, 0))
    r = client.put(price_url(doc.user_id), json={"price_dzd": 3000}, headers=doc_headers(client, ADMIN))
    assert r.status_code == 200
    assert r.json()["price_dzd"] == 3000
    held = hold(client, session, doc)
    assert held.json()["price_dzd"] == 3000
    with Session(engine) as db:
        assert db.get(Appointment, earlier.id).price_dzd == 2000


def test_only_the_super_admin_sets_prices(client, sms):
    doc = doctor_with_password()
    assert client.get("/v1/admin/doctors").status_code == 401
    assert client.put(price_url(doc.user_id), json={"price_dzd": 1}).status_code == 401
    # A plain doctor, even for their own price.
    h = doc_headers(client)
    assert client.get("/v1/admin/doctors", headers=h).status_code == 403
    r = client.put(price_url(doc.user_id), json={"price_dzd": 1}, headers=h)
    assert (r.status_code, r.json()["detail"]["code"]) == (403, "forbidden")
    patient = verified_patient(client, sms)
    assert client.get("/v1/admin/doctors", headers=bearer(patient)).status_code == 403


def test_price_rules(client):
    doc = doctor_with_password()
    make_super_admin()
    h = doc_headers(client, ADMIN)
    for bad in (-1, 100_001, "deux mille", None):
        assert client.put(price_url(doc.user_id), json={"price_dzd": bad}, headers=h).status_code == 422
    assert client.put(price_url(doc.user_id), json={"price_dzd": 0}, headers=h).status_code == 200
    r = client.put(price_url("00000000-0000-0000-0000-000000000000"), json={"price_dzd": 1}, headers=h)
    assert (r.status_code, r.json()["detail"]["code"]) == (404, "doctor_not_found")


def test_price_change_is_audited(client):
    doc = doctor_with_password()
    admin = make_super_admin()
    client.put(price_url(doc.user_id), json={"price_dzd": 2200}, headers=doc_headers(client, ADMIN))
    with Session(engine) as db:
        [row] = db.scalars(select(AuditLog).where(AuditLog.action == "doctor.price")).all()
    assert (row.actor_id, row.target) == (admin, str(doc.user_id))
