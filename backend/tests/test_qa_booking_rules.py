"""QA booking rules (api-rules, run 2026-10-25).

Edge cases for the booking rules in qa/booking/2026-10-25/rules.md (Area = api).
Each test names the R-id it covers. Tests marked xfail(strict=True) expose a
real gap against docs/PRD.md; the finding is in qa/booking/2026-10-25/api-rules.md.

Clock: Saturday 2026-10-17 18:00 UTC = 19:00 Algiers (see conftest.START).
Seeded doctor: 15 min slots, 09:00-12:00 and 14:00-16:00 Algiers, closed Friday,
24 h notice, 15 min hold, 2000 DZD. No real patient data.
"""

from datetime import date, datetime, timedelta

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import security
from app.clock import clock
from app.db import engine
from app.main import app
from app.models import (
    AccountStatus,
    Alert,
    AppointmentStatus,
    AuditLog,
    Availability,
    DoctorProfile,
    IdStatus,
    Role,
    User,
)

from .booking_helpers import add_appointment, headers, make_doctor, user_id, verified_patient
from .conftest import advance, bearer, register
from .test_appointments import SLOT, booked, code, confirm, hold
from .test_identity import body as id_body
from .test_identity import declare
from .test_staff import doc_headers, doctor_with_password

MONDAY = date(2026, 10, 19)


def set_profile(doctor, **fields) -> None:
    with Session(engine) as db:
        p = db.get(DoctorProfile, doctor.user_id)
        for k, v in fields.items():
            setattr(p, k, v)
        db.commit()


def second_doctor() -> DoctorProfile:
    """Another bookable doctor with the same hours as the seeded one."""
    with Session(engine) as db:
        user = User(role=Role.doctor, email="dr.second@example.invalid",
                    password_hash=security.hash_password("clinique2026"))
        db.add(user)
        db.flush()
        p = DoctorProfile(user_id=user.id, name_ar="د. ثاني", name_fr="Dr Second",
                          slot_minutes=15, price_dzd=2000)
        db.add(p)
        for weekday in (0, 1, 2, 3, 5, 6):
            for start, end in ((9 * 60, 12 * 60), (14 * 60, 16 * 60)):
                db.add(Availability(doctor_id=user.id, weekday=weekday,
                                    start_minute=start, end_minute=end))
        db.commit()
        db.refresh(p)
        db.expunge(p)
        return p


def patient_with_status(client, sms, phone, status: AccountStatus, id_status=None) -> dict:
    session = register(client, sms, phone)
    if id_status is not None:
        assert declare(client, session, id_number="1234567890123456" + phone[-2:]).status_code == 201
    with Session(engine) as db:
        u = db.query(User).filter(User.phone == "+213" + phone.lstrip("0")).one()
        u.status = status
        if id_status is not None:
            u.id_declaration.status = id_status
        db.commit()
    return session


def booking_calls(client, session, doctor) -> list[tuple[str, int, str]]:
    """Every patient booking route, called by [session]."""
    h = bearer(session)
    rs = {
        "hold": client.post("/v1/appointments/holds",
                            json={"doctor_id": str(doctor.user_id), "start": SLOT}, headers=h),
        "list": client.get("/v1/appointments", headers=h),
        "follow_up": client.get("/v1/appointments/follow-up", headers=h),
        "doctors": client.get("/v1/doctors", headers=h),
        "calendar": client.get(f"/v1/doctors/{doctor.user_id}/calendar", headers=h),
    }
    return [(k, r.status_code, r.json()["detail"]["code"]) for k, r in rs.items()]


# --- Gating (R-01, R-02, R-05, R-06) -----------------------------------------


@pytest.mark.parametrize("status,id_status", [
    (AccountStatus.pending_verification, None),              # id_status none
    (AccountStatus.pending_verification, IdStatus.declared),
    (AccountStatus.pending_verification, IdStatus.rejected),
    (AccountStatus.rejected, None),                          # sign-up refused outright
])
def test_r02_every_non_approved_state_is_refused_everywhere(client, sms, status, id_status):
    doctor = make_doctor()
    s = patient_with_status(client, sms, "0661234501", status, id_status)
    for name, http, err in booking_calls(client, s, doctor):
        assert (http, err) == (403, "not_verified"), name


def test_r02_duplicate_attempt_leaves_the_patient_locked(client, sms):
    doctor = make_doctor()
    first = register(client, sms, "0661234502")
    assert declare(client, first).status_code == 201
    second = register(client, sms, "0661234503")
    r = declare(client, second)
    assert (r.status_code, r.json()["detail"]["code"]) == (409, "id_already_linked")
    for name, http, err in booking_calls(client, second, doctor):
        assert (http, err) == (403, "not_verified"), name


def test_r01_a_patient_rejected_after_booking_cannot_act_on_it(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    a = booked(client, s, doctor)
    with Session(engine) as db:
        db.get(User, user_id()).status = AccountStatus.rejected
        db.commit()
    r = client.post(f"/v1/appointments/{a['id']}/cancel", headers=headers(s))
    assert (r.status_code, code(r)) == (403, "not_verified")


def test_r01_approval_without_a_declaration_does_not_unlock_booking(client, sms):
    doctor = doctor_with_password()
    s = register(client, sms)          # no ID declared: id_status = none
    h = doc_headers(client)
    [signup] = client.get("/v1/staff/signups", headers=h).json()
    assert signup["id_status"] == "none"
    client.post(f"/v1/staff/signups/{signup['id']}/approve", headers=h)
    r = hold(client, s, doctor)
    assert r.status_code == 403


@pytest.mark.xfail(strict=True, reason="QA API-02: no automatic approval; a scanner-read, unedited, unused ID still waits for staff")
def test_r05_clean_declaration_is_approved_automatically(client, sms):
    make_doctor()
    s = register(client, sms)
    # PRD 4.2 signals sent by the app. The API has no field for them yet, so
    # the names here are a guess; the assertion is what the PRD requires.
    payload = id_body() | {"scanned": True, "edited": False, "faces": 1}
    r = client.post("/v1/me/identity", json=payload, headers=bearer(s))
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "approved"


def test_r06_addictions_locked_until_first_confirmed_appointment(client, sms):
    make_doctor()
    s = verified_patient(client, sms)
    r = client.post("/v1/me/addictions", headers=bearer(s),
                    json={"type": "tobacco", "clean_since": "2026-10-07T18:00:00Z"})
    assert r.status_code == 403


def test_r06_daily_check_locked_until_first_confirmed_appointment(client, sms):
    make_doctor()
    s = verified_patient(client, sms)
    r = client.put("/v1/me/checkins/2026-10-17", headers=bearer(s))
    assert r.status_code == 403


def test_r06_doses_locked_until_first_confirmed_appointment(client, sms):
    make_doctor()
    s = register(client, sms)          # not even ID-approved
    assert client.get("/v1/me/doses", headers=bearer(s)).status_code == 403


def test_r06_tracking_works_once_an_appointment_is_confirmed(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    booked(client, s, doctor)
    r = client.post("/v1/me/addictions", headers=bearer(s),
                    json={"type": "tobacco", "clean_since": "2026-10-07T18:00:00Z"})
    assert r.status_code == 201, r.text
    assert client.put("/v1/me/checkins/2026-10-17", headers=bearer(s)).status_code == 204


# --- Slot grid (R-09, R-10) ---------------------------------------------------


def test_r09_five_minute_slots(client, sms):
    doctor = make_doctor(slot_minutes=5)
    s = verified_patient(client, sms)
    r = hold(client, s, doctor, "2026-10-19T08:05:00Z")
    assert r.status_code == 201, r.text
    assert r.json()["end"] == "2026-10-19T08:10:00Z"
    r = hold(client, s, doctor, "2026-10-19T08:07:00Z")
    assert (r.status_code, code(r)) == (409, "slot_unavailable")


def test_r10_first_and_last_slot_and_no_overrun(client, sms):
    doctor = make_doctor()
    # Monday morning window now ends at 11:50: an 11:45 slot would overrun it.
    with Session(engine) as db:
        w = db.scalar(select(Availability).where(
            Availability.doctor_id == doctor.user_id, Availability.weekday == 0,
            Availability.start_minute == 9 * 60))
        w.end_minute = 11 * 60 + 50
        db.commit()
    s = verified_patient(client, sms)
    assert hold(client, s, doctor, "2026-10-19T08:00:00Z").status_code == 201  # 09:00 first
    assert hold(client, s, doctor, "2026-10-19T07:45:00Z").status_code == 409  # 08:45
    assert hold(client, s, doctor, "2026-10-19T10:30:00Z").status_code == 201  # 11:30 last
    assert hold(client, s, doctor, "2026-10-19T10:45:00Z").status_code == 409  # 11:45 overruns
    assert hold(client, s, doctor, "2026-10-19T11:00:00Z").status_code == 409  # break
    starts = [
        x["start"] for d in client.get(f"/v1/doctors/{doctor.user_id}/calendar",
                                       headers=headers(s)).json()["days"]
        if d["day"] == "2026-10-19" for x in d["slots"]
    ]
    assert "2026-10-19T10:30:00Z" in starts and "2026-10-19T10:45:00Z" not in starts


# --- Notice and horizon (R-13, R-14, R-15, R-16) ------------------------------


def test_r13_exactly_at_notice_is_bookable_one_minute_inside_is_not(client, sms):
    doctor = make_doctor()
    set_profile(doctor, notice_hours=38)   # 18:00Z Sat + 38 h = Monday 08:00Z
    s = verified_patient(client, sms)
    a = hold(client, s, doctor, SLOT)
    assert a.status_code == 201, a.text
    client.delete(f"/v1/appointments/{a.json()['id']}/hold", headers=headers(s))
    advance(minutes=1)
    r = hold(client, s, doctor, SLOT)
    assert (r.status_code, code(r)) == (409, "slot_unavailable")


def test_r13_notice_is_per_doctor(client, sms):
    doctor = make_doctor()
    set_profile(doctor, notice_hours=48)
    s = verified_patient(client, sms)
    assert hold(client, s, doctor, SLOT).status_code == 409             # 38 h away
    assert hold(client, s, doctor, "2026-10-20T08:00:00Z").status_code == 201  # 62 h away


def test_r14_last_bookable_day_of_the_horizon(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    # Clinic today = Sat 2026-10-17. Day +59 = Tue 2026-12-15, +61 = Thu 12-17.
    assert hold(client, s, doctor, "2026-12-15T08:00:00Z").status_code == 201
    assert hold(client, s, doctor, "2026-12-17T08:00:00Z").status_code == 409
    days = client.get(f"/v1/doctors/{doctor.user_id}/calendar", headers=headers(s)).json()["days"]
    assert days[-1]["day"] == "2026-12-15"


def test_r14_day_60_follows_the_calendar(client, sms):
    """Day +60 (Wed 2026-12-16): PRD "up to 60 days" is ambiguous (QUESTION
    API-Q1). This only checks hold and calendar agree."""
    doctor = make_doctor()
    s = verified_patient(client, sms)
    days = {d["day"] for d in client.get(f"/v1/doctors/{doctor.user_id}/calendar",
                                         headers=headers(s)).json()["days"]}
    held = hold(client, s, doctor, "2026-12-16T08:00:00Z").status_code == 201
    assert held == ("2026-12-16" in days)


def test_r15_start_with_an_algiers_offset_is_the_same_slot(client, sms):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    r = hold(client, a, doctor, "2026-10-19T09:00:00+01:00")
    assert r.status_code == 201, r.text
    assert r.json()["start"] == SLOT
    r = hold(client, b, doctor, SLOT)
    assert (r.status_code, code(r)) == (409, "slot_unavailable")


def test_r15_off_grid_offset_is_refused(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    # 09:00 UTC+2 = 07:00Z = 08:00 Algiers: before opening.
    assert hold(client, s, doctor, "2026-10-19T09:00:00+02:00").status_code == 409


def test_r16_horizon_and_today_use_the_algiers_day_after_utc_midnight(client, sms):
    # 23:30Z Saturday is already 00:30 Sunday 2026-10-18 in Algiers.
    clock.frozen = datetime(2026, 10, 17, 23, 30)
    doctor = make_doctor()
    s = verified_patient(client, sms)
    days = client.get(f"/v1/doctors/{doctor.user_id}/calendar", headers=headers(s)).json()["days"]
    assert days[0]["day"] == "2026-10-18"
    assert days[-1]["day"] == "2026-12-16"
    # Clinic day +59 = Wed 12-16 (with a UTC "today" this would be refused).
    assert hold(client, s, doctor, "2026-12-16T08:00:00Z").status_code == 201
    assert hold(client, s, doctor, "2026-12-17T08:00:00Z").status_code == 409


# --- What blocks a slot (R-18) -------------------------------------------------


@pytest.mark.parametrize("status", [AppointmentStatus.completed, AppointmentStatus.no_show,
                                    AppointmentStatus.cancelled])
def test_r18_closed_visits_do_not_block_the_slot(client, sms, status):
    doctor = make_doctor()
    verified_patient(client, sms, "0661111111")
    add_appointment(doctor.user_id, user_id("0661111111"), datetime(2026, 10, 19, 8, 0),
                    status=status)
    b = verified_patient(client, sms, "0662222222")
    assert hold(client, b, doctor).status_code == 201


# --- State machine (R-29..R-33, R-39) -----------------------------------------


def test_r32_cancel_exactly_at_notice_then_cancel_twice(client, sms):
    doctor = make_doctor()
    patient = verified_patient(client, sms)
    # Exactly 24 h after the frozen clock (cancel does not check the grid).
    a = add_appointment(doctor.user_id, user_id(), datetime(2026, 10, 18, 18, 0))
    r = client.post(f"/v1/appointments/{a.id}/cancel", headers=headers(patient))
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "cancelled"
    r = client.post(f"/v1/appointments/{a.id}/cancel", headers=headers(patient))
    assert (r.status_code, code(r)) == (409, "not_cancellable")


def test_r32_one_minute_inside_notice_cannot_cancel(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    a = add_appointment(doctor.user_id, user_id(), datetime(2026, 10, 18, 17, 59))
    r = client.post(f"/v1/appointments/{a.id}/cancel", headers=headers(s))
    assert (r.status_code, code(r)) == (409, "too_late_to_cancel")


@pytest.mark.parametrize("status", [AppointmentStatus.completed, AppointmentStatus.no_show,
                                    AppointmentStatus.awaiting_payment])
def test_r32_only_confirmed_can_be_cancelled(client, sms, status):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    a = add_appointment(doctor.user_id, user_id(), datetime(2026, 10, 25, 8, 0), status=status,
                        hold_expires_at=clock.now() + timedelta(minutes=10))
    r = client.post(f"/v1/appointments/{a.id}/cancel", headers=headers(s))
    assert (r.status_code, code(r)) == (409, "not_cancellable")


def test_r33_cancel_then_another_patient_takes_the_slot(client, sms):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    appt = booked(client, a, doctor)
    assert client.post(f"/v1/appointments/{appt['id']}/cancel", headers=headers(a)).status_code == 200
    assert hold(client, b, doctor).status_code == 201
    # The cancelled one cannot be confirmed back.
    r = confirm(client, a, appt["id"])
    assert (r.status_code, code(r)) == (409, "not_a_hold")


def test_r27_confirm_a_released_hold(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    h = hold(client, s, doctor).json()
    client.delete(f"/v1/appointments/{h['id']}/hold", headers=headers(s))
    r = confirm(client, s, h["id"])
    assert (r.status_code, code(r)) == (404, "appointment_not_found")


def test_r25_replaced_hold_cannot_be_confirmed(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    first = hold(client, s, doctor).json()
    assert hold(client, s, doctor, "2026-10-19T08:15:00Z").status_code == 201
    r = confirm(client, s, first["id"])
    assert (r.status_code, code(r)) == (404, "appointment_not_found")


@pytest.mark.parametrize("status", [AppointmentStatus.cancelled, AppointmentStatus.awaiting_payment])
def test_r39_cancelled_or_unpaid_cannot_be_marked(client, sms, status):
    doctor = doctor_with_password()
    verified_patient(client, sms)
    a = add_appointment(doctor.user_id, user_id(), datetime(2026, 10, 17, 8, 0), status=status,
                        hold_expires_at=clock.now() + timedelta(minutes=10))
    h = doc_headers(client)
    for target in ("completed", "no_show"):
        r = client.post(f"/v1/staff/appointments/{a.id}/status", json={"status": target}, headers=h)
        assert (r.status_code, r.json()["detail"]["code"]) == (409, "not_markable"), target


# --- Primary doctor, follow-up, price (R-34, R-35, R-36) ----------------------


@pytest.mark.xfail(strict=True, reason="QA API-04: no primary doctor; alerts go to the doctor last booked, not the first")
def test_r34_first_booked_doctor_is_the_primary_doctor(client, sms):
    first = make_doctor()
    second = second_doctor()
    s = verified_patient(client, sms)
    booked(client, s, first, SLOT)                       # Monday 19th, booked first
    booked(client, s, second, "2026-10-26T08:00:00Z")   # a later day, booked second
    r = client.post("/v1/me/addictions", headers=bearer(s),
                    json={"type": "tobacco", "clean_since": "2026-10-07T18:00:00Z"})
    assert r.status_code == 201, r.text
    client.post(f"/v1/me/addictions/{r.json()['id']}/relapses", json={}, headers=bearer(s))
    with Session(engine) as db:
        alerts = db.query(Alert).all()
    assert [a.doctor_id for a in alerts] == [first.user_id]


def test_r35_follow_up_ignores_cancelled_and_no_show(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    for st in (AppointmentStatus.cancelled, AppointmentStatus.no_show):
        add_appointment(doctor.user_id, user_id(), datetime(2026, 10, 10, 8, 0), status=st)
    assert client.get("/v1/appointments/follow-up", headers=headers(s)).json() is None


def test_r36_follow_up_costs_the_same_as_any_appointment(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    add_appointment(doctor.user_id, user_id(), datetime(2026, 10, 14, 8, 0),
                    status=AppointmentStatus.completed)
    fu = client.get("/v1/appointments/follow-up", headers=headers(s)).json()
    assert fu["day"] == "2026-11-13"   # Friday: closed, the patient picks another day
    set_profile(doctor, price_dzd=2500)
    r = hold(client, s, doctor, "2026-11-14T08:00:00Z")
    assert r.status_code == 201, r.text
    assert r.json()["price_dzd"] == 2500


# --- Doctor-side booking features (R-37, R-38) ---------------------------------


def _staff_routes(method: str, word: str) -> list[str]:
    paths = app.openapi()["paths"]
    return [p for p, ops in paths.items()
            if p.startswith("/v1/staff") and method.lower() in ops and word in p]


@pytest.mark.xfail(strict=True, reason="QA API-05: no route for a doctor to book for a patient")
def test_r37_doctor_can_book_for_a_patient(client):
    assert any(p.rstrip("/").endswith("appointments") for p in _staff_routes("POST", "appointments"))


def test_r38_doctor_can_set_availability(client):
    assert _staff_routes("PUT", "availab") or _staff_routes("POST", "availab")


# --- Audit (R-40) ------------------------------------------------------------


def test_r40_confirm_and_cancel_are_audited_with_ids_only(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    a = booked(client, s, doctor)
    client.post(f"/v1/appointments/{a['id']}/cancel", headers=headers(s))
    with Session(engine) as db:
        rows = db.query(AuditLog).filter(AuditLog.action.like("appointment.%")).all()
        actions = [r.action for r in rows]
        assert actions == ["appointment.held", "appointment.confirmed", "appointment.cancelled"]
        assert {r.target for r in rows} == {a["id"]}
        assert a["checkin_code"] not in " ".join(r.target or "" for r in rows)
        assert all(r.actor_id == user_id() for r in rows)
