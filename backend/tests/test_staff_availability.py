from datetime import date, datetime

import pytest

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import engine
from app.models import Appointment, AppointmentStatus, AuditLog

from .booking_helpers import add_appointment, block_day, headers, user_id, verified_patient
from .conftest import bearer
from .test_staff import doc_headers, doctor_with_password, other_doctor

# Clock: Saturday 2026-10-17 19:00 in Algiers. The seed opens every day but
# Friday, 09:00-12:00 and 14:00-16:00, 15-minute slots, 24 h notice.
URL = "/v1/staff/availability"
MONDAY = date(2026, 10, 19)
MONDAY_9 = datetime(2026, 10, 19, 8, 0)  # 09:00 Algiers
NINE, NOON, TWO, FOUR = 9 * 60, 12 * 60, 14 * 60, 16 * 60


def window(weekday, start, end):
    return {"weekday": weekday, "start_minute": start, "end_minute": end}


@pytest.fixture
def patient(client, sms):
    return verified_patient(client, sms, "0770000001")


def monday_slots(client, patient, doctor_id):
    """Monday as a patient sees it."""
    cal = client.get(f"/v1/doctors/{doctor_id}/calendar", headers=headers(patient)).json()
    day = next(d for d in cal["days"] if d["day"] == MONDAY.isoformat())
    return day


def test_reads_the_doctors_hours(client):
    doctor_with_password()
    r = client.get(URL, headers=doc_headers(client))
    assert r.status_code == 200
    body = r.json()
    assert (body["slot_minutes"], body["notice_hours"]) == (15, 24)
    assert len(body["windows"]) == 12
    assert body["windows"][0] == window(0, NINE, NOON)
    assert body["blocked_days"] == body["conflicts"] == []


def test_needs_a_doctor(client, sms):
    assert client.get(URL).status_code == 401
    session = verified_patient(client, sms)
    assert client.get(URL, headers=bearer(session)).status_code == 403
    assert client.put(f"{URL}/windows", json={"windows": []}, headers=bearer(session)).status_code == 403


def test_replacing_the_week_changes_the_patient_calendar(client, patient):
    doc = doctor_with_password()
    week = [window(0, 10 * 60, 11 * 60), window(1, NINE, NOON)]
    r = client.put(f"{URL}/windows", json={"windows": week}, headers=doc_headers(client))
    assert r.status_code == 200, r.text
    assert r.json()["windows"] == week
    day = monday_slots(client, patient, doc.user_id)
    assert [s["start"] for s in day["slots"]] == [
        "2026-10-19T09:00:00Z", "2026-10-19T09:15:00Z", "2026-10-19T09:30:00Z", "2026-10-19T09:45:00Z",
    ]


def test_an_empty_week_closes_every_day(client, patient):
    doc = doctor_with_password()
    r = client.put(f"{URL}/windows", json={"windows": []}, headers=doc_headers(client))
    assert r.json()["windows"] == []
    assert monday_slots(client, patient, doc.user_id)["closure"] == "closed"


def test_window_rules(client):
    doctor_with_password()
    h = doc_headers(client)

    def code(windows):
        r = client.put(f"{URL}/windows", json={"windows": windows}, headers=h)
        return r.status_code, r.json()["detail"] if r.status_code == 422 else r.json()["detail"]["code"]

    assert code([window(0, NINE + 3, NOON)]) == (400, "off_grid")
    assert code([window(0, NOON, NINE)]) == (400, "empty_window")
    assert code([window(0, NINE, NOON), window(0, 11 * 60, TWO)]) == (400, "overlapping_windows")
    assert code([window(0, m, m + 30) for m in range(0, 7 * 60, 60)]) == (400, "too_many_windows")
    assert code([window(7, NINE, NOON)])[0] == 422
    assert code([window(0, NINE, 1441)])[0] == 422
    # Two windows that touch are fine: no break between them.
    assert client.put(f"{URL}/windows", json={"windows": [window(0, NINE, NOON), window(0, NOON, TWO)]},
                      headers=h).status_code == 200
    # Nothing was saved by the refused calls.
    assert len(client.get(URL, headers=h).json()["windows"]) == 2


def test_slot_length_and_notice(client, patient):
    doc = doctor_with_password()
    h = doc_headers(client)
    r = client.put(f"{URL}/settings", json={"slot_minutes": 10, "notice_hours": 48}, headers=h)
    assert r.status_code == 200
    assert (r.json()["slot_minutes"], r.json()["notice_hours"]) == (10, 48)
    # 48 h notice from Saturday 19:00: Monday 09:00 is now too soon.
    assert monday_slots(client, patient, doc.user_id)["closure"] == "too_soon"
    r = client.put(f"{URL}/settings", json={"slot_minutes": 10, "notice_hours": 0}, headers=h)
    slots = monday_slots(client, patient, doc.user_id)["slots"]
    assert [s["start"] for s in slots[:2]] == ["2026-10-19T08:00:00Z", "2026-10-19T08:10:00Z"]
    assert client.put(f"{URL}/settings", json={"slot_minutes": 20, "notice_hours": 24}, headers=h).status_code == 422
    assert client.put(f"{URL}/settings", json={"slot_minutes": 15, "notice_hours": 169}, headers=h).status_code == 422
    assert client.put(f"{URL}/settings", json={"slot_minutes": 15, "notice_hours": -1}, headers=h).status_code == 422


def test_block_and_unblock_a_day(client, patient):
    doc = doctor_with_password()
    h = doc_headers(client)
    r = client.post(f"{URL}/blocked-days", json={"day": "2026-10-19", "reason": "  Congrès  "}, headers=h)
    assert r.status_code == 201, r.text
    [blocked] = r.json()["blocked_days"]
    assert (blocked["day"], blocked["reason"]) == ("2026-10-19", "Congrès")
    assert monday_slots(client, patient, doc.user_id)["closure"] == "closed"
    r = client.delete(f"{URL}/blocked-days/{blocked['id']}", headers=h)
    assert r.status_code == 200
    assert r.json()["blocked_days"] == []
    assert monday_slots(client, patient, doc.user_id)["closure"] == "none"


def test_blocked_day_rules(client):
    doctor_with_password()
    h = doc_headers(client)
    post = lambda day: client.post(f"{URL}/blocked-days", json={"day": day}, headers=h)  # noqa: E731
    assert post("2026-10-16").json()["detail"]["code"] == "day_in_past"
    assert post("2027-12-01").json()["detail"]["code"] == "day_too_far"
    # Today (clinic time) can still be blocked.
    assert post("2026-10-17").status_code == 201
    r = post("2026-10-17")
    assert (r.status_code, r.json()["detail"]["code"]) == (409, "already_blocked")
    assert client.post(f"{URL}/blocked-days", json={"day": "2026-10-20", "reason": "x" * 121},
                       headers=h).status_code == 422


def test_past_blocked_days_are_not_listed(client):
    doc = doctor_with_password()
    block_day(doc.user_id, date(2026, 10, 1))
    assert client.get(URL, headers=doc_headers(client)).json()["blocked_days"] == []


def test_a_doctor_only_changes_their_own_hours(client):
    doctor_with_password()
    other_doctor()
    mine, theirs = doc_headers(client), doc_headers(client, "other@example.invalid")
    blocked = client.post(f"{URL}/blocked-days", json={"day": "2026-10-20"}, headers=mine).json()["blocked_days"][0]
    r = client.delete(f"{URL}/blocked-days/{blocked['id']}", headers=theirs)
    assert (r.status_code, r.json()["detail"]["code"]) == (404, "blocked_day_not_found")
    client.put(f"{URL}/windows", json={"windows": [window(2, NINE, NOON)]}, headers=theirs)
    body = client.get(URL, headers=mine).json()
    assert len(body["windows"]) == 12 and len(body["blocked_days"]) == 1
    assert client.get(URL, headers=theirs).json()["blocked_days"] == []


def test_booked_visits_are_kept_and_listed_as_conflicts(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    me = user_id()
    visit = add_appointment(doc.user_id, me, MONDAY_9)
    add_appointment(doc.user_id, me, datetime(2026, 10, 19, 13, 0))  # 14:00, still inside
    add_appointment(doc.user_id, me, datetime(2026, 10, 19, 8, 30), status=AppointmentStatus.cancelled)
    add_appointment(doc.user_id, me, datetime(2026, 10, 12, 8, 0), status=AppointmentStatus.completed)
    h = doc_headers(client)
    r = client.put(f"{URL}/windows", json={"windows": [window(0, TWO, FOUR)]}, headers=h)
    assert r.json()["conflicts"] == [{
        "appointment_id": str(visit.id), "start": "2026-10-19T08:00:00Z",
        "patient_phone": "+213661234567", "reason": "outside_hours",
    }]
    r = client.post(f"{URL}/blocked-days", json={"day": "2026-10-19"}, headers=h)
    assert [c["reason"] for c in r.json()["conflicts"]] == ["blocked_day", "blocked_day"]
    # Nothing was cancelled or moved.
    with Session(engine) as db:
        a = db.get(Appointment, visit.id)
        assert (a.status, a.start_utc) == (AppointmentStatus.confirmed, MONDAY_9)
    # A shorter slot length does not create a conflict for a booked 15-min visit.
    client.delete(f"{URL}/blocked-days/{r.json()['blocked_days'][0]['id']}", headers=h)
    client.put(f"{URL}/windows", json={"windows": [window(0, NINE, NOON), window(0, TWO, FOUR)]}, headers=h)
    r = client.put(f"{URL}/settings", json={"slot_minutes": 5, "notice_hours": 24}, headers=h)
    assert r.json()["conflicts"] == []


def test_changes_are_audited(client):
    doc = doctor_with_password()
    h = doc_headers(client)
    client.put(f"{URL}/windows", json={"windows": []}, headers=h)
    client.put(f"{URL}/settings", json={"slot_minutes": 10, "notice_hours": 24}, headers=h)
    blocked = client.post(f"{URL}/blocked-days", json={"day": "2026-10-20", "reason": "Congrès"},
                          headers=h).json()["blocked_days"][0]
    client.delete(f"{URL}/blocked-days/{blocked['id']}", headers=h)
    with Session(engine) as db:
        rows = db.scalars(select(AuditLog).where(AuditLog.action.like("availability.%"))).all()
    assert [r.action for r in rows] == [
        "availability.windows", "availability.settings", "availability.blocked", "availability.unblocked",
    ]
    assert all(r.actor_id == doc.user_id for r in rows)
    # The reason the doctor typed is not copied into the audit log.
    assert all("Congrès" not in (r.target or "") for r in rows)
