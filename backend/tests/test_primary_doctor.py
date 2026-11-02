"""The primary doctor is the doctor of a patient's first confirmed booking.
It is a label ("my doctor"): it never changes who reads a file (PRD 3, 4.3)."""

from sqlalchemy.orm import Session

from app.db import engine
from app.models import PrimaryDoctor

from .booking_helpers import headers, make_doctor, verified_patient
from .test_appointments import FOLLOW_UP, NEXT, SLOT, confirm, hold
from .test_payments import chargily, checkout, event, send  # noqa: F401  (chargily is a fixture)
from .test_qa_booking_rules import second_doctor

PHONE = "0661234571"


def my_doctor(client, session):
    r = client.get("/v1/me/doctor", headers=headers(session))
    assert r.status_code == 200, r.text
    return r.json()


def book(client, session, doctor, start=SLOT, method="clinic") -> dict:
    h = hold(client, session, doctor, start)
    assert h.status_code == 201, h.text
    if method == "clinic":
        assert confirm(client, session, h.json()["id"]).status_code == 200
    return h.json()


def test_no_primary_doctor_before_a_booking(client, sms):
    s = verified_patient(client, sms, PHONE)
    assert my_doctor(client, s) is None


def test_an_unpaid_hold_does_not_set_it(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms, PHONE)
    assert hold(client, s, doctor).status_code == 201
    assert my_doctor(client, s) is None


def test_first_confirmed_booking_sets_it(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms, PHONE)
    book(client, s, doctor)
    assert my_doctor(client, s) == {
        "id": str(doctor.user_id),
        "name_ar": doctor.name_ar,
        "name_fr": doctor.name_fr,
    }


def test_a_later_booking_with_a_colleague_keeps_the_first(client, sms):
    first = make_doctor()
    colleague = second_doctor()
    s = verified_patient(client, sms, PHONE)
    book(client, s, first)
    book(client, s, colleague, FOLLOW_UP)
    assert my_doctor(client, s)["id"] == str(first.user_id)
    with Session(engine) as db:
        assert db.query(PrimaryDoctor).count() == 1


def test_a_card_payment_confirmed_by_the_webhook_sets_it(client, sms, chargily):
    doctor = make_doctor()
    s = verified_patient(client, sms, PHONE)
    h = hold(client, s, doctor).json()
    assert checkout(client, s, h["id"]).status_code == 201
    assert my_doctor(client, s) is None
    assert send(client, event("checkout.paid", "chk_1")).status_code == 200
    assert my_doctor(client, s)["id"] == str(doctor.user_id)


def test_each_patient_has_their_own(client, sms):
    first = make_doctor()
    colleague = second_doctor()
    a = verified_patient(client, sms, PHONE)
    b = verified_patient(client, sms, "0661234572")
    book(client, a, first)
    book(client, b, colleague, NEXT)
    assert my_doctor(client, a)["id"] == str(first.user_id)
    assert my_doctor(client, b)["id"] == str(colleague.user_id)


def test_it_needs_a_signed_in_user(client):
    assert client.get("/v1/me/doctor").status_code in (401, 403)
