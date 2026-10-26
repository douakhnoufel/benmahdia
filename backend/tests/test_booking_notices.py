"""The doctor's alert when a booking is confirmed or cancelled (PRD 4.4:
"both sides are notified"). Sample data only."""

from sqlalchemy.orm import Session

from app.db import engine
from app.models import Alert

from .booking_helpers import headers, make_doctor, verified_patient
from .test_appointments import booked, hold
from .test_payments import chargily, checkout, event, held, send  # noqa: F401  (chargily is a fixture)


def alerts() -> list[tuple[str, str]]:
    with Session(engine) as db:
        return [(str(a.doctor_id), a.type) for a in db.query(Alert).order_by(Alert.created_at)]


def test_pay_at_clinic_confirm_alerts_the_doctor(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    booked(client, s, doctor)
    assert alerts() == [(str(doctor.user_id), "booking_confirmed")]


def test_a_hold_alone_alerts_nobody(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    assert hold(client, s, doctor).status_code == 201
    assert alerts() == []


def test_paid_webhook_alerts_the_doctor_once(client, sms, chargily):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    h = held(client, s, doctor)
    assert checkout(client, s, h["id"]).status_code == 201
    body = event("checkout.paid", "chk_1")
    assert send(client, body).status_code == 200
    assert send(client, body).status_code == 200   # Chargily retries
    assert alerts() == [(str(doctor.user_id), "booking_confirmed")]


def test_failed_payment_alerts_nobody(client, sms, chargily):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    h = held(client, s, doctor)
    checkout(client, s, h["id"])
    assert send(client, event("checkout.failed", "chk_1")).status_code == 200
    assert alerts() == []


def test_patient_cancel_alerts_the_doctor(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    done = booked(client, s, doctor)
    assert client.post(f"/v1/appointments/{done['id']}/cancel", headers=headers(s)).status_code == 200
    assert [kind for _, kind in alerts()] == ["booking_confirmed", "booking_cancelled"]


def test_alert_shows_in_the_doctors_inbox_without_medical_content(client, sms):
    from .test_staff import doc_headers, doctor_with_password

    doctor = doctor_with_password()
    s = verified_patient(client, sms)
    booked(client, s, doctor)
    [item] = client.get("/v1/staff/alerts", headers=doc_headers(client)).json()
    assert item["type"] == "booking_confirmed"
    assert set(item) == {"id", "patient_id", "patient_phone", "type", "priority", "read", "created_at"}
