import uuid
from datetime import date, datetime

from sqlalchemy.orm import Session

from app.db import engine
from app.models import Appointment, AppointmentStatus, AuditLog

from .booking_helpers import (
    add_appointment,
    block_day,
    expire_holds,
    headers,
    make_doctor,
    user_id,
    verified_patient,
)
from .conftest import bearer, register

# Clock: Saturday 2026-10-17 19:00 Algiers. First bookable day is Monday.
SLOT = "2026-10-19T08:00:00Z"  # 09:00 in Algiers
NEXT = "2026-10-19T08:15:00Z"
THIRD = "2026-10-19T08:30:00Z"


def hold(client, session, doctor, start=SLOT):
    return client.post(
        "/v1/appointments/holds",
        json={"doctor_id": str(doctor.user_id), "start": start},
        headers=headers(session),
    )


def confirm(client, session, appointment_id, method="clinic"):
    return client.post(
        f"/v1/appointments/{appointment_id}/confirm",
        json={"method": method},
        headers=headers(session),
    )


def booked(client, session, doctor, start=SLOT) -> dict:
    h = hold(client, session, doctor, start).json()
    r = confirm(client, session, h["id"])
    assert r.status_code == 200, r.text
    return r.json()


def code(r) -> str:
    return r.json()["detail"]["code"]


# --- POST /holds ------------------------------------------------------------


def test_hold_creates_a_timed_reservation(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    r = hold(client, s, doctor)
    assert r.status_code == 201, r.text
    a = r.json()
    assert a["status"] == "awaiting_payment"
    assert (a["start"], a["end"]) == (SLOT, "2026-10-19T08:15:00Z")
    assert a["price_dzd"] == 2000 and a["method"] is None
    assert a["hold_expires_at"] == "2026-10-17T18:15:00Z"
    assert a["doctor"]["id"] == str(doctor.user_id)


def test_hold_needs_a_login_and_a_verified_patient(client, sms):
    doctor = make_doctor()
    body = {"doctor_id": str(doctor.user_id), "start": SLOT}
    assert client.post("/v1/appointments/holds", json=body).status_code == 401
    pending = register(client, sms)
    r = client.post("/v1/appointments/holds", json=body, headers=bearer(pending))
    assert (r.status_code, code(r)) == (403, "not_verified")


def test_hold_unknown_doctor(client, sms):
    make_doctor()
    s = verified_patient(client, sms)
    r = client.post("/v1/appointments/holds", headers=headers(s),
                    json={"doctor_id": "00000000-0000-0000-0000-000000000000", "start": SLOT})
    assert (r.status_code, code(r)) == (404, "doctor_not_found")


def test_second_patient_cannot_take_the_same_slot(client, sms):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    assert hold(client, a, doctor).status_code == 201
    r = hold(client, b, doctor)
    assert (r.status_code, code(r)) == (409, "slot_unavailable")


def test_off_grid_start_is_refused(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    r = hold(client, s, doctor, "2026-10-19T08:05:00Z")
    assert (r.status_code, code(r)) == (409, "slot_unavailable")


def test_slot_rules(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    for start in (
        "2026-10-18T08:00:00Z",   # inside the 24 h notice
        "2026-10-19T03:00:00Z",   # outside consultation hours
        "2026-10-23T08:00:00Z",   # Friday, closed
        "2026-12-21T08:00:00Z",   # beyond 60 days
    ):
        r = hold(client, s, doctor, start)
        assert (r.status_code, code(r)) == (409, "slot_unavailable"), start
    block_day(doctor.user_id, date(2026, 10, 20))
    assert hold(client, s, doctor, "2026-10-20T08:00:00Z").status_code == 409


def test_new_hold_replaces_the_patients_old_one(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    first = hold(client, s, doctor).json()
    second = hold(client, s, doctor, NEXT)
    assert second.status_code == 201
    other = verified_patient(client, sms, "0662222222")
    assert hold(client, other, doctor).status_code == 201   # first slot is free again
    assert first["id"] != second.json()["id"]


def test_failed_hold_keeps_the_patients_old_one(client, sms):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    mine = hold(client, a, doctor).json()
    hold(client, b, doctor, NEXT)
    assert hold(client, a, doctor, NEXT).status_code == 409
    assert [x["id"] for x in client.get("/v1/appointments", headers=headers(a)).json()] == [mine["id"]]


def test_expired_hold_frees_the_slot(client, sms):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    hold(client, a, doctor)
    expire_holds()
    assert hold(client, b, doctor).status_code == 201


def test_hold_is_audited_without_medical_content(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    a = hold(client, s, doctor).json()
    with Session(engine) as db:
        line = db.query(AuditLog).filter(AuditLog.action == "appointment.held").one()
    assert line.target == a["id"]


# --- DELETE /{id}/hold --------------------------------------------------------


def test_release_hold_frees_the_slot(client, sms):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    h = hold(client, a, doctor).json()
    assert client.delete(f"/v1/appointments/{h['id']}/hold", headers=headers(a)).status_code == 204
    assert hold(client, b, doctor).status_code == 201
    assert client.get("/v1/appointments", headers=headers(a)).json() == []


def test_release_refuses_other_patients_and_confirmed(client, sms):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    h = hold(client, a, doctor).json()
    r = client.delete(f"/v1/appointments/{h['id']}/hold", headers=headers(b))
    assert (r.status_code, code(r)) == (404, "appointment_not_found")
    done = booked(client, a, doctor, NEXT)
    r = client.delete(f"/v1/appointments/{done['id']}/hold", headers=headers(a))
    assert (r.status_code, code(r)) == (409, "not_a_hold")


# --- POST /{id}/confirm -------------------------------------------------------


def test_confirm_with_clinic_payment(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    h = hold(client, s, doctor).json()
    r = confirm(client, s, h["id"])
    assert r.status_code == 200
    assert (r.json()["status"], r.json()["method"], r.json()["hold_expires_at"]) == ("confirmed", "clinic", None)


def test_card_payment_cannot_be_confirmed_from_the_app(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    h = hold(client, s, doctor).json()
    for method in ("cib", "edahabia"):
        r = confirm(client, s, h["id"], method)
        assert (r.status_code, code(r)) == (400, "payment_method_unavailable")
    with Session(engine) as db:
        assert db.get(Appointment, uuid.UUID(h["id"])).status == AppointmentStatus.awaiting_payment


def test_confirm_after_the_hold_ran_out(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    h = hold(client, s, doctor).json()
    expire_holds()
    r = confirm(client, s, h["id"])
    assert (r.status_code, code(r)) == (409, "hold_expired")
    assert client.get("/v1/appointments", headers=headers(s)).json() == []


def test_confirm_someone_elses_or_twice(client, sms):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    h = hold(client, a, doctor).json()
    assert confirm(client, b, h["id"]).status_code == 404
    confirm(client, a, h["id"])
    r = confirm(client, a, h["id"])
    assert (r.status_code, code(r)) == (409, "not_a_hold")


# --- GET "" ---------------------------------------------------------------------


def test_list_shows_only_my_appointments_oldest_first(client, sms):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    booked(client, a, doctor, NEXT)
    booked(client, a, doctor)
    booked(client, b, doctor, THIRD)
    mine = client.get("/v1/appointments", headers=headers(a)).json()
    assert [x["start"] for x in mine] == [SLOT, NEXT]
    assert len(client.get("/v1/appointments", headers=headers(b)).json()) == 1


def test_list_needs_a_verified_patient(client, sms):
    assert client.get("/v1/appointments").status_code == 401
    pending = register(client, sms)
    assert client.get("/v1/appointments", headers=bearer(pending)).status_code == 403


def test_list_hides_open_holds_that_ran_out(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    hold(client, s, doctor)
    assert len(client.get("/v1/appointments", headers=headers(s)).json()) == 1
    expire_holds()
    assert client.get("/v1/appointments", headers=headers(s)).json() == []


# --- POST /{id}/cancel ----------------------------------------------------------


def test_cancel_outside_the_notice(client, sms):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    done = booked(client, a, doctor)
    r = client.post(f"/v1/appointments/{done['id']}/cancel", headers=headers(a))
    assert r.status_code == 200 and r.json()["status"] == "cancelled"
    assert hold(client, b, doctor).status_code == 201   # slot is back
    # The cancelled visit stays in the patient's history.
    assert [x["status"] for x in client.get("/v1/appointments", headers=headers(a)).json()] == ["cancelled"]


def test_cancel_inside_the_notice_is_refused(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    # A confirmed visit tomorrow at 08:00 UTC is 14 h away: inside the notice.
    done = add_appointment(doctor.user_id, user_id(), datetime(2026, 10, 18, 8, 0))
    r = client.post(f"/v1/appointments/{done.id}/cancel", headers=headers(s))
    assert (r.status_code, code(r)) == (409, "too_late_to_cancel")


def test_cancel_refuses_other_patients_and_non_confirmed(client, sms):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    done = booked(client, a, doctor)
    assert client.post(f"/v1/appointments/{done['id']}/cancel", headers=headers(b)).status_code == 404
    client.post(f"/v1/appointments/{done['id']}/cancel", headers=headers(a))
    r = client.post(f"/v1/appointments/{done['id']}/cancel", headers=headers(a))
    assert (r.status_code, code(r)) == (409, "not_cancellable")


# --- GET /follow-up -------------------------------------------------------------


def test_follow_up_is_empty_without_a_visit(client, sms):
    make_doctor()
    s = verified_patient(client, sms)
    r = client.get("/v1/appointments/follow-up", headers=headers(s))
    assert r.status_code == 200 and r.json() is None


def test_follow_up_is_30_days_after_the_latest_visit(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    me = user_id()
    add_appointment(doctor.user_id, me, datetime(2026, 9, 1, 8, 0), status=AppointmentStatus.completed)
    add_appointment(doctor.user_id, me, datetime(2026, 9, 10, 8, 0), status=AppointmentStatus.cancelled)
    add_appointment(doctor.user_id, me, datetime(2026, 9, 14, 8, 0), status=AppointmentStatus.completed)
    r = client.get("/v1/appointments/follow-up", headers=headers(s)).json()
    assert (r["day"], r["days"]) == ("2026-10-14", 30)
    assert r["after"]["start"] == "2026-09-14T08:00:00Z"


def test_follow_up_ignores_other_patients(client, sms):
    doctor = make_doctor()
    verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    add_appointment(doctor.user_id, user_id("0661111111"), datetime(2026, 9, 1, 8, 0),
                    status=AppointmentStatus.completed)
    assert client.get("/v1/appointments/follow-up", headers=headers(b)).json() is None
