"""Front-desk check-in with the patient's booking code."""

from datetime import datetime

import pytest
from sqlalchemy.orm import Session

from app import checkin
from app.db import engine
from app.models import Appointment, AppointmentStatus, AuditLog

from .booking_helpers import add_appointment, headers, make_doctor, user_id, verified_patient
from .conftest import advance, bearer
from .test_appointments import SLOT, booked, confirm, hold
from .test_payments import chargily, checkout, event, held, send  # noqa: F401
from .test_staff import doc_headers, doctor_with_password, other_doctor

# Clock: Saturday 2026-10-17 19:00 in Algiers (18:00 UTC).
TODAY_EVENING = datetime(2026, 10, 17, 20, 0)   # 21:00 Algiers, same clinic day
LATE_UTC = datetime(2026, 10, 17, 23, 30)       # 00:30 Algiers: already Sunday
MONDAY_9 = datetime(2026, 10, 19, 8, 0)
CODE = "K7M4PX"


def post(client, code, h=None):
    return client.post("/v1/staff/checkin", json={"code": code}, headers=h or doc_headers(client))


def error(r) -> str:
    return r.json()["detail"]["code"]


def audit_actions() -> list[str]:
    with Session(engine) as db:
        return [row.action for row in db.query(AuditLog).order_by(AuditLog.id)]


def stored(appointment_id) -> Appointment:
    with Session(engine) as db:
        return db.get(Appointment, appointment_id)


# --- the code is issued on confirmation ------------------------------------------


def test_clinic_booking_gets_a_code_the_patient_can_read(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    held_slot = hold(client, s, doctor).json()
    assert held_slot["checkin_code"] is None          # a hold is not an appointment yet
    a = confirm(client, s, held_slot["id"]).json()
    assert len(a["checkin_code"]) == checkin.LENGTH
    assert set(a["checkin_code"]) <= set(checkin.ALPHABET)
    [listed] = client.get("/v1/appointments", headers=headers(s)).json()
    assert listed["checkin_code"] == a["checkin_code"]


def test_card_payment_gets_a_code_from_the_webhook(client, sms, chargily):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    a = held(client, s, doctor)
    checkout(client, s, a["id"])
    assert send(client, event("checkout.paid", "chk_1")).status_code == 200
    [listed] = client.get("/v1/appointments", headers=headers(s)).json()
    assert listed["status"] == "confirmed" and len(listed["checkin_code"]) == checkin.LENGTH


def test_a_cancelled_appointment_no_longer_shows_its_code(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    a = booked(client, s, doctor)
    r = client.post(f"/v1/appointments/{a['id']}/cancel", headers=headers(s))
    assert r.status_code == 200 and r.json()["checkin_code"] is None


def test_codes_are_unique_and_easy_to_read(client):
    with Session(engine) as db:
        codes = {checkin.new_code(db) for _ in range(300)}
    assert len(codes) == 300
    assert all(not set(c) & set("0O1IL") for c in codes)


def test_normalize_accepts_what_a_person_types():
    assert checkin.normalize(" k7m-4px ") == "K7M4PX"


# --- check-in ---------------------------------------------------------------------


def test_checking_in_marks_the_patient_as_arrived(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    a = add_appointment(doc.user_id, user_id(), TODAY_EVENING, checkin_code=CODE)
    h = doc_headers(client)
    r = post(client, CODE, h)
    assert r.status_code == 200, r.text
    item = r.json()
    assert item["id"] == str(a.id) and item["patient_phone"] == "+213661234567"
    assert (item["status"], item["checked_in_at"]) == ("confirmed", "2026-10-17T18:00:00Z")
    [agenda_item] = client.get("/v1/staff/agenda?day=2026-10-17", headers=h).json()
    assert agenda_item["checked_in_at"] == "2026-10-17T18:00:00Z"
    assert audit_actions().count("appointment.checked_in") == 1


def test_the_code_may_be_typed_loosely(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    add_appointment(doc.user_id, user_id(), TODAY_EVENING, checkin_code=CODE)
    assert post(client, " k7m-4px ").status_code == 200


def test_checking_in_twice_changes_nothing(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    a = add_appointment(doc.user_id, user_id(), TODAY_EVENING, checkin_code=CODE)
    h = doc_headers(client)
    first = post(client, CODE, h).json()["checked_in_at"]
    advance(minutes=5)
    r = post(client, CODE, h)
    assert r.status_code == 200 and r.json()["checked_in_at"] == first
    assert stored(a.id).checked_in_at == datetime(2026, 10, 17, 18, 0)
    assert audit_actions().count("appointment.checked_in") == 1


def test_another_doctors_code_looks_like_an_unknown_code(client, sms):
    doctor_with_password()
    other = other_doctor()
    verified_patient(client, sms)
    theirs = add_appointment(other, user_id(), TODAY_EVENING, checkin_code=CODE)
    r = post(client, CODE)
    assert (r.status_code, error(r)) == (404, "checkin_code_invalid")
    assert r.json() == post(client, "ZZZZZZ").json()      # same answer as a made-up code
    assert stored(theirs.id).checked_in_at is None


def test_a_code_works_only_on_the_day_of_the_visit(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    later = add_appointment(doc.user_id, user_id(), MONDAY_9, checkin_code=CODE)
    r = post(client, CODE)
    assert (r.status_code, error(r)) == (409, "not_today")
    assert stored(later.id).checked_in_at is None


def test_the_day_is_the_clinic_day_not_the_utc_day(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    # 23:30 UTC is 00:30 in Algiers: tomorrow for the clinic, today in UTC.
    add_appointment(doc.user_id, user_id(), LATE_UTC, checkin_code=CODE)
    r = post(client, CODE)
    assert (r.status_code, error(r)) == (409, "not_today")


@pytest.mark.parametrize("status", [
    AppointmentStatus.cancelled,
    AppointmentStatus.no_show,
    AppointmentStatus.completed,
    AppointmentStatus.awaiting_payment,
])
def test_only_a_confirmed_appointment_can_check_in(client, sms, status):
    doc = doctor_with_password()
    verified_patient(client, sms)
    a = add_appointment(doc.user_id, user_id(), TODAY_EVENING, status=status, checkin_code=CODE,
                        hold_expires_at=datetime(2026, 10, 17, 18, 10))
    r = post(client, CODE)
    assert (r.status_code, error(r)) == (409, "not_checkable")
    assert stored(a.id).checked_in_at is None


def test_check_in_needs_a_doctor(client, sms):
    s = verified_patient(client, sms)
    assert client.post("/v1/staff/checkin", json={"code": CODE}).status_code == 401
    assert client.post("/v1/staff/checkin", json={"code": CODE}, headers=bearer(s)).status_code == 403


def test_an_empty_code_is_refused(client):
    doctor_with_password()
    assert post(client, "").status_code == 422
    assert post(client, "---").status_code == 404      # nothing left after cleaning


# --- guessing -----------------------------------------------------------------------


def test_too_many_wrong_codes_make_the_account_wait(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    add_appointment(doc.user_id, user_id(), TODAY_EVENING, checkin_code=CODE)
    h = doc_headers(client)
    for i in range(10):
        assert post(client, f"WRONG{i}", h).status_code == 404
    r = post(client, "AAAAAA", h)
    assert (r.status_code, error(r)) == (429, "too_many_attempts")
    assert int(r.headers["Retry-After"]) == 600
    # Even the right code waits: the limit protects against trying many codes.
    assert post(client, CODE, h).status_code == 429
    assert "checkin.failed" in audit_actions()


def test_the_wait_ends_and_other_doctors_are_not_affected(client, sms):
    doc = doctor_with_password()
    other = other_doctor()
    verified_patient(client, sms)
    add_appointment(doc.user_id, user_id(), TODAY_EVENING, checkin_code=CODE)
    h = doc_headers(client)
    for i in range(10):
        post(client, f"WRONG{i}", h)
    assert post(client, CODE, h).status_code == 429
    # A second doctor is not blocked by the first one's failures.
    from .test_staff import PASSWORD, login
    h2 = bearer(login(client, "other@example.invalid", PASSWORD).json())
    assert post(client, "AAAAAA", h2).status_code == 404
    advance(minutes=11)
    h = doc_headers(client)
    assert post(client, CODE, h).status_code == 200


def test_valid_but_unusable_codes_do_not_count_as_guesses(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    add_appointment(doc.user_id, user_id(), MONDAY_9, checkin_code=CODE)
    h = doc_headers(client)
    for _ in range(12):
        assert post(client, CODE, h).status_code == 409
