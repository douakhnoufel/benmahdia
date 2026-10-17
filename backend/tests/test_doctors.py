from datetime import date, datetime, timedelta

from app.clock import clock
from app.models import AppointmentStatus

from .booking_helpers import (
    add_appointment,
    block_day,
    headers,
    make_doctor,
    user_id,
    verified_patient,
)
from .conftest import register, bearer

# Clock is Saturday 2026-10-17 18:00 UTC = 19:00 in Algiers. With 24 h notice
# the first bookable morning is Monday 2026-10-19.
MONDAY = date(2026, 10, 19)


def day_of(calendar: dict, day: date) -> dict:
    return next(d for d in calendar["days"] if d["day"] == day.isoformat())


def test_doctors_need_a_login(client):
    assert client.get("/v1/doctors").status_code == 401


def test_pending_patient_cannot_see_doctors(client, sms):
    session = register(client, sms)
    r = client.get("/v1/doctors", headers=bearer(session))
    assert r.status_code == 403
    assert r.json()["detail"]["code"] == "not_verified"


def test_lists_the_doctor(client, sms):
    doctor = make_doctor()
    session = verified_patient(client, sms)
    r = client.get("/v1/doctors", headers=headers(session))
    assert r.status_code == 200
    [d] = r.json()
    assert d["id"] == str(doctor.user_id)
    assert d["name_fr"] == "Dr Benmahdia Hocine"
    assert (d["slot_minutes"], d["price_dzd"], d["notice_hours"], d["hold_minutes"]) == (15, 2000, 24, 15)
    assert d["horizon_days"] == 60


def test_calendar_unknown_doctor(client, sms):
    session = verified_patient(client, sms)
    r = client.get("/v1/doctors/00000000-0000-0000-0000-000000000000/calendar", headers=headers(session))
    assert r.status_code == 404
    assert r.json()["detail"]["code"] == "doctor_not_found"


def test_calendar_needs_a_verified_patient(client, sms):
    doctor = make_doctor()
    session = register(client, sms)
    r = client.get(f"/v1/doctors/{doctor.user_id}/calendar", headers=bearer(session))
    assert r.status_code == 403


def test_calendar_shape_and_rules(client, sms):
    doctor = make_doctor()
    session = verified_patient(client, sms)
    r = client.get(f"/v1/doctors/{doctor.user_id}/calendar", headers=headers(session))
    assert r.status_code == 200
    cal = r.json()
    assert len(cal["days"]) == 60
    assert cal["days"][0]["day"] == "2026-10-17"
    # Today and tomorrow are inside the 24 h notice.
    assert cal["days"][0]["closure"] == "too_soon"
    assert cal["days"][1]["closure"] == "too_soon"
    # Friday is closed.
    assert day_of(cal, date(2026, 10, 23))["closure"] == "closed"
    monday = day_of(cal, MONDAY)
    assert monday["closure"] == "none"
    # 09:00-12:00 and 14:00-16:00 in 15-minute slots.
    assert len(monday["slots"]) == 12 + 8
    assert all(s["free"] for s in monday["slots"])
    # 09:00 Algiers (UTC+1) is 08:00 UTC.
    assert monday["slots"][0]["start"] == "2026-10-19T08:00:00Z"
    assert monday["slots"][12]["start"] == "2026-10-19T13:00:00Z"


def test_slot_length_follows_the_doctor(client, sms):
    doctor = make_doctor(slot_minutes=10)
    session = verified_patient(client, sms)
    cal = client.get(f"/v1/doctors/{doctor.user_id}/calendar", headers=headers(session)).json()
    assert len(day_of(cal, MONDAY)["slots"]) == 18 + 12


def test_blocked_day_is_closed(client, sms):
    doctor = make_doctor()
    block_day(doctor.user_id, MONDAY)
    session = verified_patient(client, sms)
    cal = client.get(f"/v1/doctors/{doctor.user_id}/calendar", headers=headers(session)).json()
    assert day_of(cal, MONDAY) == {"day": "2026-10-19", "closure": "closed", "slots": []}


def test_booked_slot_is_not_free_and_reveals_nothing(client, sms):
    doctor = make_doctor()
    other = verified_patient(client, sms, phone="0770000001")
    session = verified_patient(client, sms)
    add_appointment(doctor.user_id, user_id("0770000001"), datetime(2026, 10, 19, 8, 0))
    r = client.get(f"/v1/doctors/{doctor.user_id}/calendar", headers=headers(session))
    first = day_of(r.json(), MONDAY)["slots"][0]
    assert first == {"start": "2026-10-19T08:00:00Z", "free": False}
    assert "patient" not in r.text and str(user_id("0770000001")) not in r.text


def test_overlapping_slot_sizes_block_each_other(client, sms):
    doctor = make_doctor(slot_minutes=10)
    session = verified_patient(client, sms)
    # A 15 min visit from 08:00 covers the 08:00 and 08:10 slots, not 08:20.
    add_appointment(doctor.user_id, user_id(), datetime(2026, 10, 19, 8, 0), minutes=15)
    slots = day_of(
        client.get(f"/v1/doctors/{doctor.user_id}/calendar", headers=headers(session)).json(), MONDAY
    )["slots"]
    assert [s["free"] for s in slots[:3]] == [False, False, True]


def test_active_hold_blocks_but_expired_hold_does_not(client, sms):
    doctor = make_doctor()
    session = verified_patient(client, sms)
    me = user_id()
    now = clock.now()
    add_appointment(doctor.user_id, me, datetime(2026, 10, 19, 8, 0),
                    status=AppointmentStatus.awaiting_payment, hold_expires_at=now + timedelta(minutes=5))
    add_appointment(doctor.user_id, me, datetime(2026, 10, 19, 8, 15),
                    status=AppointmentStatus.awaiting_payment, hold_expires_at=now - timedelta(minutes=1))
    slots = day_of(
        client.get(f"/v1/doctors/{doctor.user_id}/calendar", headers=headers(session)).json(), MONDAY
    )["slots"]
    assert [s["free"] for s in slots[:3]] == [False, True, True]


def test_cancelled_appointment_frees_the_slot(client, sms):
    doctor = make_doctor()
    session = verified_patient(client, sms)
    add_appointment(doctor.user_id, user_id(), datetime(2026, 10, 19, 8, 0),
                    status=AppointmentStatus.cancelled)
    slots = day_of(
        client.get(f"/v1/doctors/{doctor.user_id}/calendar", headers=headers(session)).json(), MONDAY
    )["slots"]
    assert slots[0]["free"] is True
