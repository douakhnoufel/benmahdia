"""The clinic's Payments page (PRD 4.4, 7) and the staff receipt. Sample data only."""

from datetime import datetime

from sqlalchemy.orm import Session

from app.db import engine
from app.models import Appointment, AppointmentStatus, PaymentMethod

from .booking_helpers import add_appointment, headers, user_id, verified_patient
from .conftest import bearer
from .test_appointments import booked
from .test_payments import chargily, checkout, event, held, send  # noqa: F401  (chargily is a fixture)
from .test_staff import doc_headers, doctor_with_password, make_super_admin, other_doctor

OCT = "/v1/staff/payments?from=2026-10-01&to=2026-10-31"


def paid(a: Appointment, when=datetime(2026, 10, 1, 9, 0)) -> None:
    with Session(engine) as db:
        db.get(Appointment, a.id).paid_at = when
        db.commit()


def test_lists_own_appointments_with_totals(client, sms):
    doc = doctor_with_password()
    other = other_doctor()
    verified_patient(client, sms)
    me = user_id()
    a1 = add_appointment(doc.user_id, me, datetime(2026, 10, 5, 8, 0), status=AppointmentStatus.completed)
    paid(a1)
    add_appointment(doc.user_id, me, datetime(2026, 10, 12, 8, 0), status=AppointmentStatus.no_show)
    add_appointment(doc.user_id, me, datetime(2026, 10, 20, 8, 0))
    # Cancelled and unpaid: nothing owed.
    add_appointment(doc.user_id, me, datetime(2026, 10, 21, 8, 0), status=AppointmentStatus.cancelled)
    # Another doctor's, out of range, or only a hold: not listed.
    add_appointment(other, me, datetime(2026, 10, 6, 8, 0))
    add_appointment(doc.user_id, me, datetime(2026, 11, 2, 8, 0))
    add_appointment(doc.user_id, me, datetime(2026, 10, 22, 8, 0), status=AppointmentStatus.awaiting_payment)
    r = client.get(OCT, headers=doc_headers(client))
    assert r.status_code == 200, r.text
    body = r.json()
    assert [row["start"][:10] for row in body["rows"]] == ["2026-10-05", "2026-10-12", "2026-10-20", "2026-10-21"]
    first = body["rows"][0]
    assert (first["paid"], first["paid_at"], first["mine"], first["patient_phone"]) == (
        True, "2026-10-01T09:00:00Z", True, "+213661234567")
    assert body["totals"] == {"paid_count": 1, "paid_dzd": 2000, "unpaid_count": 2, "unpaid_dzd": 4000}


def test_range_uses_clinic_days(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    # 23:30 UTC on Oct 31 is 00:30 on Nov 1 in Algiers.
    add_appointment(doc.user_id, user_id(), datetime(2026, 10, 31, 23, 30))
    add_appointment(doc.user_id, user_id(), datetime(2026, 9, 30, 23, 30))  # Oct 1, 00:30
    rows = client.get(OCT, headers=doc_headers(client)).json()["rows"]
    assert [row["start"] for row in rows] == ["2026-09-30T23:30:00Z"]


def test_super_admin_sees_every_doctor(client, sms):
    doc = doctor_with_password()
    make_super_admin()
    verified_patient(client, sms)
    add_appointment(doc.user_id, user_id(), datetime(2026, 10, 5, 8, 0))
    rows = client.get(OCT, headers=doc_headers(client, "admin@example.invalid")).json()["rows"]
    assert [(row["doctor_name_fr"], row["mine"]) for row in rows] == [("Dr Benmahdia Hocine", False)]


def test_range_rules(client):
    doctor_with_password()
    h = doc_headers(client)
    r = client.get("/v1/staff/payments?from=2026-10-31&to=2026-10-01", headers=h)
    assert (r.status_code, r.json()["detail"]["code"]) == (400, "bad_range")
    # At most 92 clinic days, both ends counted.
    r = client.get("/v1/staff/payments?from=2026-01-01&to=2026-04-03", headers=h)
    assert (r.status_code, r.json()["detail"]["code"]) == (400, "range_too_long")
    assert client.get("/v1/staff/payments?from=2026-01-01&to=2026-04-02", headers=h).status_code == 200
    assert client.get("/v1/staff/payments?from=2026-10-01", headers=h).status_code == 422
    assert client.get("/v1/staff/payments?from=hier&to=2026-10-01", headers=h).status_code == 422


def test_payments_need_a_doctor(client, sms):
    assert client.get(OCT).status_code == 401
    session = verified_patient(client, sms)
    assert client.get(OCT, headers=bearer(session)).status_code == 403


# --- receipt ---------------------------------------------------------------------


def staff_receipt(client, appointment_id, email="dr.benmahdia@example.invalid"):
    return client.get(f"/v1/staff/appointments/{appointment_id}/receipt", headers=doc_headers(client, email))


def test_doctor_sees_the_same_receipt_as_the_patient(client, sms, chargily):
    doctor = doctor_with_password()
    s = verified_patient(client, sms)
    h = held(client, s, doctor)
    checkout(client, s, h["id"], "edahabia")
    send(client, event("checkout.paid", "chk_1"))
    mine = client.get(f"/v1/appointments/{h['id']}/receipt", headers=headers(s)).json()
    r = staff_receipt(client, h["id"])
    assert r.status_code == 200
    assert r.json() == mine
    assert r.json()["payment_ref"] == "chk_1"


def test_receipt_only_once_paid(client, sms):
    doctor = doctor_with_password()
    s = verified_patient(client, sms)
    a = booked(client, s, doctor)
    r = staff_receipt(client, a["id"])
    assert (r.status_code, r.json()["detail"]["code"]) == (409, "not_paid")


def test_receipt_of_another_doctors_visit(client, sms):
    doctor_with_password()
    other = other_doctor()
    make_super_admin()
    verified_patient(client, sms)
    a = add_appointment(other, user_id(), datetime(2026, 10, 5, 8, 0), method=PaymentMethod.clinic)
    paid(a)
    r = staff_receipt(client, a.id)
    assert (r.status_code, r.json()["detail"]["code"]) == (404, "appointment_not_found")
    assert staff_receipt(client, a.id, "other@example.invalid").status_code == 200
    assert staff_receipt(client, a.id, "admin@example.invalid").status_code == 200
    r = staff_receipt(client, "00000000-0000-0000-0000-000000000000", "admin@example.invalid")
    assert r.status_code == 404


def test_receipt_needs_a_doctor(client, sms):
    doc = doctor_with_password()
    s = verified_patient(client, sms)
    a = add_appointment(doc.user_id, user_id(), datetime(2026, 10, 5, 8, 0))
    paid(a)
    assert client.get(f"/v1/staff/appointments/{a.id}/receipt").status_code == 401
    assert client.get(f"/v1/staff/appointments/{a.id}/receipt", headers=bearer(s)).status_code == 403
