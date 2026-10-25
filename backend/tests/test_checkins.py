import itertools
import uuid
from datetime import timedelta

from sqlalchemy.orm import Session

from app.clock import clock
from app.db import engine
from app.models import Role, User

from .booking_helpers import add_appointment, make_doctor
from .conftest import bearer, register

TODAY = "2026-10-17"  # the frozen clock is 2026-10-17 18:00 UTC


_slots = itertools.count()


def unlocked(client, sms, phone="0661234567") -> dict:
    """A patient past their first confirmed appointment, so recovery is open
    (PRD 5). Each gets a slot of their own."""
    s = register(client, sms, phone)
    at = clock.now() - timedelta(days=3) + timedelta(minutes=15 * next(_slots))
    add_appointment(make_doctor().user_id, uuid.UUID(s["user"]["id"]), at)
    return s


def tick(client, s, day=TODAY):
    return client.put(f"/v1/me/checkins/{day}", headers=bearer(s))


def test_requires_login(client):
    assert client.get("/v1/me/checkins").status_code == 401
    assert client.put(f"/v1/me/checkins/{TODAY}").status_code == 401
    assert client.get("/v1/me/reminder").status_code == 401
    assert client.put("/v1/me/reminder", json={"time": "21:00"}).status_code == 401


def test_tick_today_and_list(client, sms):
    s = unlocked(client, sms)
    assert client.get("/v1/me/checkins", headers=bearer(s)).json() == []
    assert tick(client, s).status_code == 204
    assert tick(client, s, "2026-10-16").status_code == 204
    days = client.get("/v1/me/checkins", headers=bearer(s)).json()
    assert days == ["2026-10-16", "2026-10-17"]


def test_tick_twice_is_fine(client, sms):
    s = unlocked(client, sms)
    assert tick(client, s).status_code == 204
    assert tick(client, s).status_code == 204
    assert client.get("/v1/me/checkins", headers=bearer(s)).json() == [TODAY]


def test_tick_day_must_be_recent_and_not_in_the_future(client, sms):
    s = unlocked(client, sms)
    assert tick(client, s, "2026-10-18").status_code == 204  # phone already past midnight
    for day in ("2026-10-19", "2026-10-10"):
        r = tick(client, s, day)
        assert r.status_code == 422, day
        assert r.json()["detail"]["code"] == "checkin_day_out_of_range"
    assert tick(client, s, "not-a-date").status_code == 422


def test_each_patient_has_their_own_days(client, sms):
    a = unlocked(client, sms, "0661234567")
    b = unlocked(client, sms, "0771234567")
    tick(client, a)
    assert client.get("/v1/me/checkins", headers=bearer(b)).json() == []


def test_list_only_returns_the_recent_window(client, sms):
    s = unlocked(client, sms)
    tick(client, s, "2026-10-16")
    r = client.get("/v1/me/checkins", params={"since": "2026-10-17"}, headers=bearer(s))
    assert r.json() == []


def test_reminder_set_read_and_clear(client, sms):
    s = unlocked(client, sms)
    assert client.get("/v1/me/reminder", headers=bearer(s)).json() == {"time": None}
    r = client.put("/v1/me/reminder", json={"time": "21:05"}, headers=bearer(s))
    assert r.status_code == 200 and r.json() == {"time": "21:05"}
    assert client.get("/v1/me/reminder", headers=bearer(s)).json() == {"time": "21:05"}
    r = client.put("/v1/me/reminder", json={"time": None}, headers=bearer(s))
    assert r.json() == {"time": None}
    assert client.get("/v1/me/reminder", headers=bearer(s)).json() == {"time": None}


def test_reminder_rejects_bad_times(client, sms):
    s = unlocked(client, sms)
    for bad in ("24:00", "9:00", "21:60", "9pm", ""):
        r = client.put("/v1/me/reminder", json={"time": bad}, headers=bearer(s))
        assert r.status_code == 422, bad


def test_staff_cannot_use_patient_routes(client, sms):
    s = register(client, sms)
    with Session(engine) as db:
        db.get(User, uuid.UUID(s["user"]["id"])).role = Role.doctor
        db.commit()
    assert client.get("/v1/me/checkins", headers=bearer(s)).status_code == 403
    assert client.get("/v1/me/reminder", headers=bearer(s)).status_code == 403
