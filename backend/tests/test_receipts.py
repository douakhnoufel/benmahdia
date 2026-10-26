"""GET /v1/appointments/{id}/receipt: proof of payment for the patient's own
paid appointments (PRD 4.4). Sample data only."""

import uuid

from .booking_helpers import headers, verified_patient
from .test_appointments import SLOT, booked, code, hold
from .test_payments import chargily, checkout, event, held, send  # noqa: F401  (chargily is a fixture)
from .test_staff import doc_headers, doctor_with_password


def receipt(client, session, appointment_id):
    return client.get(f"/v1/appointments/{appointment_id}/receipt", headers=headers(session))


def test_card_payment_receipt(client, sms, chargily):
    doctor = doctor_with_password()
    s = verified_patient(client, sms)
    h = held(client, s, doctor)
    checkout(client, s, h["id"], "cib")
    send(client, event("checkout.paid", "chk_1"))
    r = receipt(client, s, h["id"])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["number"] == "BM-" + uuid.UUID(h["id"]).hex[:8].upper()
    assert (body["start"], body["amount_dzd"], body["method"], body["payment_ref"]) == (SLOT, 2000, "cib", "chk_1")
    assert body["doctor_name_ar"] and body["doctor_name_fr"] and body["paid_at"]


def test_clinic_payment_has_a_receipt_only_once_marked_paid(client, sms):
    doctor = doctor_with_password()
    s = verified_patient(client, sms)
    a = booked(client, s, doctor)
    r = receipt(client, s, a["id"])
    assert r.status_code == 409 and code(r) == "not_paid"
    dh = doc_headers(client)
    assert client.post(f"/v1/staff/appointments/{a['id']}/paid", json={"paid": True}, headers=dh).status_code == 200
    r = receipt(client, s, a["id"])
    assert r.status_code == 200
    assert (r.json()["method"], r.json()["payment_ref"]) == ("clinic", None)


def test_hold_has_no_receipt(client, sms):
    doctor = doctor_with_password()
    s = verified_patient(client, sms)
    h = hold(client, s, doctor).json()
    r = receipt(client, s, h["id"])
    assert r.status_code == 409 and code(r) == "not_paid"


def test_someone_elses_receipt_looks_missing(client, sms, chargily):
    doctor = doctor_with_password()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    h = held(client, a, doctor)
    checkout(client, a, h["id"], "cib")
    send(client, event("checkout.paid", "chk_1"))
    theirs = receipt(client, b, h["id"])
    random = receipt(client, b, uuid.uuid4())
    assert theirs.status_code == random.status_code == 404
    assert theirs.json() == random.json()


def test_receipt_needs_a_verified_patient(client, sms):
    assert client.get(f"/v1/appointments/{uuid.uuid4()}/receipt").status_code == 401
