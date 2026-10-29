"""QA 2026-10-26, recovery pillar, api-rules role.

Tests the recovery rules of docs/PRD.md (3, 5, 5.1-5.4, 5.6, 7, 12.3) through
the HTTP API. R-xx ids refer to qa/recovery/2026-10-26/rules.md; API-NN ids
to the findings in qa/recovery/2026-10-26/api-rules.md.

- A test that shows a real bug is xfail(strict=True) with its finding id.
- A test named test_question_* pins what the API does where the PRD is
  silent; the finding asks which behaviour is wanted.

Fixtures are fake: Algerian test phones, seeded doctors, no real drug names.
"""

import traceback
import uuid
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from datetime import date, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker

from app.clock import clock
from app.db import engine, get_db
from app.main import app
from app.models import (
    Addiction,
    AddictionCheck,
    Alert,
    Appointment,
    AppointmentStatus,
    AuditLog,
    DailyCheck,
    DoseLog,
    DoseStatus,
    HabitLog,
    Quote,
    Relapse,
)

from .booking_helpers import add_appointment, make_doctor
from .conftest import START, bearer, register
from .test_medications import doses, linked_patient, prescribe, staff_session
from .test_substance_tracking import CLEAN_SINCE, NICOTINE, TODAY, add, check, checks, later
from .test_substance_tracking import setup as doctor_and_patient

ZERO = "00000000-0000-0000-0000-000000000000"
# A course with no real drug name in it.
COURSE = {"name": "Traitement QA", "amount": "1 unité", "times": ["08:00"], "instructions": None}

PRD_SIGNALS = {  # PRD 5.6 table, in its order
    "nicotine": ["irritability", "restlessness"],
    "thc": ["sleep", "irritability"],
    "pregabalin": ["anxiety", "sleep"],
    "buprenorphine": ["discomfort", "sleep"],
    "cocaine": ["low_mood", "low_energy"],
    "amphetamines": ["sleep", "low_appetite"],
}


def iso(t: datetime) -> str:
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def pid(s) -> str:
    return s["user"]["id"]


def move_to(client, when: datetime, s, doc=None) -> None:
    """Sets the clock (forward only) and refreshes the sessions it outlived."""
    clock.frozen = when
    r = client.post("/v1/auth/refresh", json={"refresh_token": s["refresh_token"]})
    assert r.status_code == 200, r.text
    s.update(r.json())
    if doc is not None:
        doc.update(staff_session(client, doc["doctor"]))


def relapse(client, s, a, **body):
    return client.post(f"/v1/me/addictions/{a['id']}/relapses", json=body, headers=bearer(s))


def habit(client, s, **body):
    return client.post("/v1/me/habits", json={"kind": "sport"} | body, headers=bearer(s))


def staff_addictions(client, doc, s):
    return client.get(f"/v1/staff/patients/{pid(s)}/addictions", headers=bearer(doc))


def review(client, doc, s, a, decision):
    return client.post(
        f"/v1/staff/patients/{pid(s)}/addictions/{a['id']}/{decision}", headers=bearer(doc)
    )


def recovery_routes() -> list[tuple[str, str]]:
    """Every patient route of the recovery pillar, read from the API's own
    route table, so a route added later is swept too."""
    return [
        (method.upper(), path)
        for path, ops in app.openapi()["paths"].items()
        for method, op in ops.items()
        if path.startswith("/v1/me") and "recovery" in op.get("tags", [])
    ]


def call_route(client, s, method, path):
    url = path.replace("{addiction_id}", ZERO).replace("{habit_id}", ZERO).replace("{day}", TODAY)
    body = None if method == "GET" else {}
    return client.request(method, url, json=body, headers=bearer(s))


# --- 1. Unlock (PRD 5 intro) ----------------------------------------------


def test_every_recovery_route_is_locked_until_a_paid_visit_then_opens(client, sms):
    """R-01: every recovery route, including the ones rules.md lists as
    uncovered (milestone seen, habit reminder, habit days, habit delete)."""
    routes = recovery_routes()
    for uncovered in (
        ("POST", "/v1/me/addictions/{addiction_id}/milestone/seen"),
        ("PUT", "/v1/me/habits/{habit_id}/reminder"),
        ("PUT", "/v1/me/habits/{habit_id}/days/{day}"),
        ("DELETE", "/v1/me/habits/{habit_id}/days/{day}"),
        ("DELETE", "/v1/me/habits/{habit_id}"),
        ("PUT", "/v1/me/addictions/{addiction_id}/goal"),
    ):
        assert uncovered in routes
    assert len(routes) >= 21
    s = register(client, sms)
    for method, path in routes:
        r = call_route(client, s, method, path)
        assert r.status_code == 403 and r.json()["detail"]["code"] == "recovery_locked", (method, path, r.text)
    add_appointment(make_doctor().user_id, uuid.UUID(pid(s)), clock.now() - timedelta(days=1))
    for method, path in routes:
        r = call_route(client, s, method, path)
        assert r.status_code != 403, (method, path, r.text)


@pytest.mark.parametrize("status", [AppointmentStatus.completed, AppointmentStatus.no_show])
def test_a_finished_or_missed_paid_visit_keeps_recovery_open(client, sms, status):
    """R-03: "a paid visit stays paid"."""
    s = register(client, sms)
    add_appointment(make_doctor().user_id, uuid.UUID(pid(s)), clock.now() - timedelta(days=3), status=status)
    assert client.get("/v1/me/addictions", headers=bearer(s)).status_code == 200
    assert add(client, s).status_code == 201


def test_a_paid_visit_still_to_come_unlocks(client, sms):
    """R-02: the unlock is the confirmed (paid) appointment, not the visit."""
    s = register(client, sms)
    add_appointment(make_doctor().user_id, uuid.UUID(pid(s)), clock.now() + timedelta(days=5))
    assert client.get("/v1/me/addictions", headers=bearer(s)).status_code == 200


def test_question_a_paid_visit_cancelled_later_locks_recovery_again(client, sms):
    """QUESTION API-07 (R-05, G-02). PRD 5 unlocks "after the first
    appointment is confirmed (paid)" and says nothing of a later cancel or
    refund. Today every route locks again, the data stays, and the doctor
    keeps the file and the alerts (see SEC-02)."""
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    s = register(client, sms)
    visit = add_appointment(doctor.user_id, uuid.UUID(pid(s)), clock.now() - timedelta(days=3))
    add(client, s)
    with Session(engine) as db:
        db.get(Appointment, visit.id).status = AppointmentStatus.cancelled
        db.commit()
    for method, path in recovery_routes():
        r = call_route(client, s, method, path)
        assert r.status_code == 403 and r.json()["detail"]["code"] == "recovery_locked", (method, path)
    assert len(staff_addictions(client, doc, s).json()) == 1


# --- 2. Addictions, review, relapse (PRD 3, 5.1) --------------------------


@pytest.mark.parametrize(
    ("profile", "type_"),
    [("nicotine", "tobacco"), ("thc", "cannabis"), ("pregabalin", "pills"),
     ("buprenorphine", "opioids"), ("cocaine", "stimulants"), ("amphetamines", "stimulants")],
)
def test_each_profile_implies_its_prd_type_and_waits_for_review(client, sms, profile, type_):
    """R-10, R-14."""
    _, s = doctor_and_patient(client, sms)
    r = add(client, s, profile=profile)
    assert r.status_code == 201, r.text
    assert (r.json()["type"], r.json()["review_status"]) == (type_, "pending")
    wrong = "gambling"
    assert add(client, s, profile=profile, type=wrong).status_code == 422


def test_doctor_review_is_recorded_and_can_be_changed(client, sms):
    """R-15: confirm and reject record who and when, are audited with the
    row id only, and the doctor can change their mind."""
    doc, s = doctor_and_patient(client, sms)
    a = add(client, s, substance="Produit QA").json()
    r = review(client, doc, s, a, "reject")
    assert r.status_code == 200 and r.json()["review_status"] == "rejected"
    assert client.get("/v1/me/addictions", headers=bearer(s)).json() == []
    r = review(client, doc, s, a, "confirm")
    assert r.json()["review_status"] == "confirmed"
    [mine] = client.get("/v1/me/addictions", headers=bearer(s)).json()
    assert mine["review_status"] == "confirmed" and mine["clean_since"] == CLEAN_SINCE
    with Session(engine) as db:
        row = db.get(Addiction, uuid.UUID(a["id"]))
        assert row.reviewed_by == doc["doctor"].user_id and row.reviewed_at == clock.now()
        audit = {r.action: r.target for r in db.scalars(select(AuditLog))}
    assert audit["addiction.rejected"] == audit["addiction.confirmed"] == a["id"]


def test_after_review_no_route_edits_the_start_date(client, sms):
    """R-19 (PRD 3): after review only a relapse moves the counter."""
    doc, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    review(client, doc, s, a, "confirm")
    moved = {"clean_since": "2026-01-01T00:00:00Z", "type": "tobacco", "past_days": 999}
    for method in ("PUT", "PATCH"):
        r = client.request(method, f"/v1/me/addictions/{a['id']}", json=moved, headers=bearer(s))
        assert r.status_code in (404, 405), (method, r.status_code)
        r = client.request(method, f"/v1/staff/patients/{pid(s)}/addictions/{a['id']}", json=moved,
                           headers=bearer(doc))
        assert r.status_code in (404, 405), (method, r.status_code)
    # Routes that take a body ignore a start date slipped into it.
    client.put(f"/v1/me/addictions/{a['id']}/goal", json={"days": 14} | moved, headers=bearer(s))
    client.post(f"/v1/me/addictions/{a['id']}/milestone/seen", json=moved, headers=bearer(s))
    client.put(f"/v1/staff/patients/{pid(s)}/addictions/{a['id']}/profile",
               json={"profile": "nicotine"} | moved, headers=bearer(doc))
    [now] = client.get("/v1/me/addictions", headers=bearer(s)).json()
    assert (now["clean_since"], now["past_days"]) == (CLEAN_SINCE, 0)


def test_the_patient_cannot_delete_relapse_history(client, sms):
    """R-20 (PRD 3 "cannot delete relapse history")."""
    doc, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    assert relapse(client, s, a, at="2026-10-12T08:00:00Z", note="Note QA").status_code == 201
    with Session(engine) as db:
        [rid] = db.scalars(select(Relapse.id)).all()
    base = f"/v1/me/addictions/{a['id']}"
    for method, url in (
        ("DELETE", base),
        ("DELETE", f"{base}/relapses"),
        ("DELETE", f"{base}/relapses/{rid}"),
        ("PUT", f"{base}/relapses/{rid}"),
        ("PUT", f"{base}/relapses"),
    ):
        r = client.request(method, url, headers=bearer(s))
        assert r.status_code in (404, 405), (method, url, r.status_code)
    [row] = staff_addictions(client, doc, s).json()
    assert row["relapses"] == [{"at": "2026-10-12T08:00:00Z", "note": "Note QA"}]
    assert row["past_days"] == 4  # 10-07 18:00 to 10-12 08:00


def test_relapse_time_edges(client, sms):
    """R-21: "when" can be given; not in the future (5 min of phone clock
    slack), not before the current start, and an offset is converted."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    assert relapse(client, s, a, at="2026-10-07T17:59:59Z").json()["detail"]["code"] == "relapse_before_start"
    assert relapse(client, s, a, at=iso(START + timedelta(minutes=6))).json()["detail"]["code"] == "relapse_in_future"
    r = relapse(client, s, a, at="2026-10-12T10:00:00+01:00")
    assert r.status_code == 201 and r.json()["clean_since"] == "2026-10-12T09:00:00Z"
    # The earlier streak is closed: a relapse before the new start is refused.
    assert relapse(client, s, a, at="2026-10-10T09:00:00Z").json()["detail"]["code"] == "relapse_before_start"
    b = add(client, s).json()
    r = relapse(client, s, b, at=iso(START + timedelta(minutes=4)))
    assert r.status_code == 201


def test_the_counter_keeps_the_hour_of_its_start(client, sms):
    """R-22, R-27 (API side): the start keeps its time so the app can show
    hours, through an offset and a relapse."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s, clean_since="2026-10-17T09:45:00+01:00").json()
    assert a["clean_since"] == "2026-10-17T08:45:00Z"
    r = relapse(client, s, a, at="2026-10-17T15:20:00+01:00").json()
    assert r["clean_since"] == "2026-10-17T14:20:00Z" and r["past_days"] == 0


def test_longest_streak_and_total_survive_relapses_and_the_ladder_restarts(client, sms):
    """R-22, R-24: past streaks are folded in, never lost, and the new
    streak has its own milestones and its first small goal."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s, clean_since="2026-08-01T00:00:00Z").json()
    assert (a["milestone"], a["goal"]) == (60, 90)  # 77 days
    client.put(f"/v1/me/addictions/{a['id']}/goal", json={"days": None}, headers=bearer(s))
    client.post(f"/v1/me/addictions/{a['id']}/milestone/seen", headers=bearer(s))
    r = relapse(client, s, a, at="2026-10-10T00:00:00Z").json()  # 70-day streak
    assert (r["past_days"], r["longest_past_days"]) == (70, 70)
    assert (r["milestone"], r["milestone_seen"], r["goal_days"], r["goal"]) == (7, 0, None, 14)
    r = relapse(client, s, a, at="2026-10-15T00:00:00Z").json()  # 5-day streak
    assert (r["past_days"], r["longest_past_days"]) == (75, 70)
    r = relapse(client, s, a).json()  # same day again
    assert (r["past_days"], r["longest_past_days"], r["goal"]) == (77, 70, 1)


def test_used_today_in_the_check_logs_no_relapse_and_no_alert_by_itself(client, sms):
    """R-25 (PRD 5.6 step 1): "No" opens relapse logging in the app; the
    check alone does not restart the counter or alert the doctor."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    assert check(client, s, a, used=True).status_code == 204
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(Relapse)) == 0
        assert db.scalar(select(func.count()).select_from(Alert)) == 0
    assert relapse(client, s, a).status_code == 201
    with Session(engine) as db:
        assert [x.type for x in db.scalars(select(Alert))] == ["relapse"]


def test_question_a_double_tap_on_i_relapsed_logs_two_relapses(client, sms):
    """QUESTION API-15. The PRD does not say whether two relapses logged
    seconds apart are one event. Today both are kept and the doctor gets two
    high-priority relapse alerts."""
    doc, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    assert relapse(client, s, a).status_code == 201
    assert relapse(client, s, a).status_code == 201
    [row] = staff_addictions(client, doc, s).json()
    assert len(row["relapses"]) == 2
    alerts = client.get("/v1/staff/alerts", headers=bearer(doc)).json()
    assert [x["type"] for x in alerts] == ["relapse", "relapse"]


def test_question_a_rejected_addiction_still_takes_relapses_goals_and_a_slot(client, sms):
    """QUESTION API-08 (R-16, R-13, G-07). A rejected addiction leaves the
    patient's list and refuses daily checks, but still takes a relapse (which
    raises a high alert), a goal and a milestone seen, still counts toward
    the 10-addiction limit, and still picks the quote's type."""
    doc, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    review(client, doc, s, a, "reject")
    assert client.get("/v1/me/addictions", headers=bearer(s)).json() == []
    assert check(client, s, a).status_code == 404
    assert relapse(client, s, a).status_code == 201
    assert [x["type"] for x in client.get("/v1/staff/alerts", headers=bearer(doc)).json()] == ["relapse"]
    assert client.put(f"/v1/me/addictions/{a['id']}/goal", json={"days": 3}, headers=bearer(s)).status_code == 200
    assert client.post(f"/v1/me/addictions/{a['id']}/milestone/seen", headers=bearer(s)).status_code == 200
    for _ in range(9):
        assert add(client, s).status_code == 201
    assert len(client.get("/v1/me/addictions", headers=bearer(s)).json()) == 9
    r = add(client, s)
    assert r.status_code == 409 and r.json()["detail"]["code"] == "too_many_addictions"


@pytest.mark.xfail(strict=True, reason="QA API-09: the doctor cannot record triggers or a severity level per addiction")
def test_the_doctor_records_triggers_and_severity(client, sms):
    """R-18 (PRD 3, 9: Addiction.severity, triggers)."""
    doc, s = doctor_and_patient(client, sms)
    add(client, s)
    [row] = staff_addictions(client, doc, s).json()
    assert {"triggers", "severity"} <= set(row)


# --- 3. Milestones and small goals (PRD 5.1, 5.6) -------------------------

LADDER = [  # streak days, milestone reached, automatic goal
    (0, 0, 1), (1, 1, 3), (2, 1, 3), (3, 3, 7), (6, 3, 7), (7, 7, 14), (14, 14, 28),
    (27, 14, 28), (28, 14, 60), (30, 30, 60), (60, 60, 90), (90, 90, 180),
    (180, 180, 365), (364, 180, 365), (365, 365, 730), (730, 730, 1095),
]


@pytest.mark.parametrize(("days", "milestone", "goal"), LADDER)
def test_milestone_and_automatic_goal_through_the_api(client, sms, days, milestone, goal):
    """R-29, R-33: 1, 3, 7, 14, 30, 60, 90, 180, 365 then yearly; goals
    1, 3, 7, 14, 28 then the ladder from 60."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s, clean_since=iso(START - timedelta(days=days))).json()
    assert (a["milestone"], a["goal"], a["milestone_seen"]) == (milestone, goal, 0)


def test_milestone_seen_never_runs_ahead(client, sms):
    """R-31: only the milestone reached now can be marked seen."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s, clean_since=iso(START - timedelta(hours=5))).json()
    url = f"/v1/me/addictions/{a['id']}/milestone/seen"
    assert client.post(url, headers=bearer(s)).json()["milestone_seen"] == 0
    later(client, s, days=1)
    r = client.post(url, headers=bearer(s)).json()
    assert (r["milestone"], r["milestone_seen"]) == (1, 1)
    assert client.post(url, headers=bearer(s)).json()["milestone_seen"] == 1
    later(client, s, days=2)
    [now] = client.get("/v1/me/addictions", headers=bearer(s)).json()
    assert (now["milestone"], now["milestone_seen"]) == (3, 1)


def test_patient_chooses_another_step_and_a_relapse_goes_back_to_one_day(client, sms):
    """R-34, R-35, R-24 (PRD 5.6 small goals)."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s, clean_since=iso(START - timedelta(days=2))).json()
    url = f"/v1/me/addictions/{a['id']}/goal"
    assert a["goal"] == 3
    assert client.put(url, json={"days": 14}, headers=bearer(s)).json()["goal"] == 14  # higher
    assert client.put(url, json={"days": 3}, headers=bearer(s)).json()["goal"] == 3  # back down
    for bad in (1, 2, 4, 30, -1):
        r = client.put(url, json={"days": bad}, headers=bearer(s))
        assert r.status_code == 422 and r.json()["detail"]["code"] == "goal_invalid", bad
    assert client.put(url, json={}, headers=bearer(s)).status_code == 422
    later(client, s, days=1)  # 3 days: the chosen goal is reached, the next is suggested
    [now] = client.get("/v1/me/addictions", headers=bearer(s)).json()
    assert (now["goal_days"], now["goal"]) == (3, 7)
    r = relapse(client, s, a).json()
    assert (r["goal_days"], r["goal"]) == (None, 1)


def test_question_after_four_weeks_no_other_step_can_be_chosen(client, sms):
    """QUESTION API-16 (R-34, G-10). PRD 5.6: after 4 weeks the ladder takes
    over (60, 90, 180, 365) and "the patient can choose a different step".
    Only 1-28 are accepted, so past day 28 every choice is refused."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s, clean_since=iso(START - timedelta(days=35))).json()
    assert a["goal"] == 60
    for days in (60, 90, 180, 365):
        r = client.put(f"/v1/me/addictions/{a['id']}/goal", json={"days": days}, headers=bearer(s))
        assert r.status_code == 422 and r.json()["detail"]["code"] == "goal_invalid", days


# --- 4. Daily check per addiction (PRD 5.4, 5.6) --------------------------


def test_each_profile_asks_exactly_the_prd_signals(client, sms):
    """R-44 (all six rows of the table), R-43: generic = craving only."""
    _, s = doctor_and_patient(client, sms)
    catalog = client.get("/v1/me/recovery/profiles", headers=bearer(s)).json()
    assert {p["key"]: [x["key"] for x in p["signals"]] for p in catalog} == PRD_SIGNALS
    for profile, keys in PRD_SIGNALS.items():
        a = add(client, s, profile=profile).json()
        other = next(v for v in PRD_SIGNALS.values() if set(v) != set(keys))
        for wrong in ({k: 3 for k in other}, {keys[0]: 3}, {}):
            r = check(client, s, a, signals=wrong)
            assert r.status_code == 422 and r.json()["detail"]["code"] == "signals_mismatch", (profile, wrong)
        assert check(client, s, a, signals={k: 5 for k in keys}).status_code == 204, profile
    generic = add(client, s, profile=None, type="gambling").json()
    assert check(client, s, generic, signals={"sleep": 2}).status_code == 422
    assert check(client, s, generic, signals={}).status_code == 204


def test_ratings_are_whole_numbers_from_1_to_5(client, sms):
    """R-43: craving and both signals 1-5; 0, 6, missing and fractions fail."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    url = f"/v1/me/addictions/{a['id']}/checks/{TODAY}"
    good = {"used": False, "craving": 3, "signals": NICOTINE}
    for over in ({"craving": 0}, {"craving": 6}, {"craving": 2.5}, {"craving": None}, {"craving": "beaucoup"},
                 {"used": None}, {"signals": {"irritability": 0, "restlessness": 2}},
                 {"signals": {"irritability": 6, "restlessness": 2}},
                 {"signals": {"irritability": -1, "restlessness": 2}},
                 {"signals": {"irritability": 2.5, "restlessness": 2}},
                 {"signals": {"irritability": None, "restlessness": 2}}):
        r = client.put(url, json=good | over, headers=bearer(s))
        assert r.status_code == 422, (over, r.text)
    for missing in ("used", "craving"):
        body = {k: v for k, v in good.items() if k != missing}
        assert client.put(url, json=body, headers=bearer(s)).status_code == 422, missing
    for edge in (1, 5):
        body = good | {"craving": edge, "signals": {"irritability": edge, "restlessness": edge}}
        assert client.put(url, json=body, headers=bearer(s)).status_code == 204, edge


def test_one_answer_per_addiction_per_day(client, sms):
    """R-45: a second save the same day replaces the first; days are
    separate; another addiction has its own answer."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    b = add(client, s, profile="thc").json()
    check(client, s, a, craving=2)
    check(client, s, a, craving=4)
    check(client, s, a, day="2026-10-16", craving=1)
    check(client, s, b, signals={"sleep": 1, "irritability": 1}, craving=5)
    with Session(engine) as db:
        rows = db.scalars(select(AddictionCheck).order_by(AddictionCheck.day)).all()
    assert sorted((str(r.addiction_id), r.day.isoformat(), r.craving) for r in rows) == sorted([
        (a["id"], "2026-10-16", 1), (a["id"], TODAY, 4), (b["id"], TODAY, 5),
    ])


def test_late_answers_are_editable_the_day_they_are_given_only(client, sms):
    """R-45, R-48: yesterday and two days ago can still be answered; each
    answer locks once the day it was given is over; three days back is
    refused."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    assert check(client, s, a, day="2026-10-16").status_code == 204
    assert check(client, s, a, day="2026-10-16", craving=4).status_code == 204
    assert check(client, s, a, day="2026-10-15").status_code == 204
    assert check(client, s, a).status_code == 204
    r = check(client, s, a, day="2026-10-14")
    assert r.status_code == 422 and r.json()["detail"]["code"] == "checkin_day_out_of_range"
    later(client, s)
    for day in ("2026-10-16", TODAY):
        r = check(client, s, a, day=day, craving=1)
        assert r.status_code in (409, 422), day
    assert check(client, s, a, day="2026-10-18").status_code == 204


@pytest.mark.xfail(strict=True, reason="QA API-01: the same-day edit window follows the UTC date, so a check saved after midnight in Algiers locks at 01:00")
def test_a_check_saved_after_midnight_in_algiers_stays_editable_that_day(client, sms):
    """R-46 (PRD 5.6 "editable the same day"). The phone sends its own
    (Algiers) day. Saved at 00:30 on 10-18 in Algiers, edited at 01:10 the
    same Algiers day."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    move_to(client, datetime(2026, 10, 17, 23, 30), s)  # 00:30 on 10-18 in Algiers
    assert check(client, s, a, day="2026-10-18", craving=2).status_code == 204
    move_to(client, datetime(2026, 10, 18, 0, 10), s)  # 01:10 on 10-18 in Algiers
    r = check(client, s, a, day="2026-10-18", used=True, craving=5)
    assert r.status_code == 204, r.text


def test_the_week_strip_counts_only_addictions_that_existed_that_day(client, sms):
    """R-49: a day is done when every active addiction that existed then was
    checked; adding one today does not undo yesterday."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    check(client, s, a, day="2026-10-16")
    b = add(client, s, profile="cocaine").json()
    assert checks(client, s).json()["done_days"] == ["2026-10-16"]
    check(client, s, a)
    assert checks(client, s).json()["done_days"] == ["2026-10-16"]
    check(client, s, b, signals={"low_mood": 2, "low_energy": 2})
    assert checks(client, s).json()["done_days"] == ["2026-10-16", TODAY]


@pytest.mark.xfail(strict=True, reason="QA API-03: the week strip dates a new addiction by its UTC day, so one added after midnight in Algiers undoes the day before")
def test_adding_an_addiction_after_midnight_in_algiers_keeps_yesterday_done(client, sms):
    """R-47, R-49. 10-17 (Algiers) is fully checked; at 00:30 on 10-18
    Algiers the patient adds a second addiction; 10-17 must stay done."""
    _, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    check(client, s, a)
    assert checks(client, s).json()["done_days"] == [TODAY]
    move_to(client, datetime(2026, 10, 17, 23, 30), s)  # 00:30 on 10-18 in Algiers
    add(client, s, profile="thc")
    assert checks(client, s).json()["done_days"] == [TODAY]


def test_buprenorphine_taken_as_prescribed_is_not_use(client, sms):
    """PRD 5.6 Goal: a prescribed dose taken is tracked in Medications, not
    as use: the counter, checks and relapses do not move."""
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    s = linked_patient(client, sms, doctor)
    a = add(client, s, profile="buprenorphine").json()
    med = prescribe(client, doc, s, **COURSE).json()
    r = client.put("/v1/me/doses", json={"medication_id": med["id"], "day": TODAY, "time": "08:00",
                                         "status": "taken"}, headers=bearer(s))
    assert r.status_code == 200
    [now] = client.get("/v1/me/addictions", headers=bearer(s)).json()
    assert (now["clean_since"], now["past_days"]) == (a["clean_since"], 0)
    assert checks(client, s).json() == {"checks": [], "done_days": []}
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(Relapse)) == 0


# --- 5. Good habits (PRD 5.6) ---------------------------------------------


def test_a_removed_habit_frees_its_slot_and_keeps_its_days(client, sms):
    """R-57, R-58, R-62: five active at most; removing one stops it, keeps
    its done days and audits the row id only; it can be picked again."""
    _, s = doctor_and_patient(client, sms)
    sport = habit(client, s).json()
    for kind in ("water", "reading", "sleep", "call_family"):
        assert habit(client, s, kind=kind).status_code == 201
    assert client.put(f"/v1/me/habits/{sport['id']}/days/{TODAY}", headers=bearer(s)).status_code == 204
    r = habit(client, s, kind="brush_teeth")
    assert r.status_code == 409 and r.json()["detail"]["code"] == "too_many_habits"
    assert client.delete(f"/v1/me/habits/{sport['id']}", headers=bearer(s)).status_code == 204
    base = f"/v1/me/habits/{sport['id']}"
    for method, url, body in (("PUT", f"{base}/days/{TODAY}", None), ("DELETE", f"{base}/days/{TODAY}", None),
                              ("PUT", f"{base}/reminder", {"time": None}), ("DELETE", base, None)):
        assert client.request(method, url, json=body, headers=bearer(s)).status_code == 404, (method, url)
    again = habit(client, s)
    assert again.status_code == 201 and again.json()["days"] == []
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(HabitLog)) == 1
        targets = [r.target for r in db.scalars(select(AuditLog).where(AuditLog.action == "habit.removed"))]
    assert targets == [sport["id"]]


def test_one_tick_per_habit_per_day(client, sms):
    """R-58: ticking twice keeps one row; unticking a day never ticked is
    harmless; ticks for other recent days are their own."""
    _, s = doctor_and_patient(client, sms)
    h = habit(client, s).json()
    url = f"/v1/me/habits/{h['id']}/days"
    for day in (TODAY, TODAY, "2026-10-15", "2026-10-18"):
        assert client.put(f"{url}/{day}", headers=bearer(s)).status_code == 204, day
    assert client.delete(f"{url}/2026-10-16", headers=bearer(s)).status_code == 204
    with Session(engine) as db:
        days = sorted(d.isoformat() for d in db.scalars(select(HabitLog.day)))
    assert days == ["2026-10-15", TODAY, "2026-10-18"]


@pytest.mark.parametrize("good", ["00:00", "09:05", "23:59"])
def test_reminder_times_accept_24_hour_hh_mm(client, sms, good):
    """R-40, R-60, R-65."""
    _, s = doctor_and_patient(client, sms)
    h = habit(client, s).json()
    assert client.put("/v1/me/reminder", json={"time": good}, headers=bearer(s)).json()["time"] == good
    r = client.put(f"/v1/me/habits/{h['id']}/reminder", json={"time": good}, headers=bearer(s))
    assert r.json()["reminder_time"] == good


@pytest.mark.parametrize("bad", ["24:00", "23:60", "9:05", "09:5", "09:05:00", " 09:05", "09h05", "", "-1:00", "9 PM"])
def test_reminder_times_refuse_anything_else(client, sms, bad):
    """R-40, R-60, R-65: the obvious wrong shapes."""
    doc, s = doctor_and_patient(client, sms)
    h = habit(client, s).json()
    assert client.put("/v1/me/reminder", json={"time": bad}, headers=bearer(s)).status_code == 422
    assert client.put(f"/v1/me/habits/{h['id']}/reminder", json={"time": bad}, headers=bearer(s)).status_code == 422
    assert habit(client, s, kind="water", reminder_time=bad).status_code == 422
    assert prescribe(client, doc, s, **COURSE | {"times": [bad]}).status_code == 422


@pytest.mark.xfail(strict=True, reason="QA API-06: the HH:MM check accepts a trailing newline and non-ASCII digits (6 chars overflow varchar(5) on PostgreSQL)")
@pytest.mark.parametrize("bad", ["21:30\n", "1١:3٠"])
def test_reminder_times_are_plain_ascii_hh_mm(client, sms, bad):
    """R-40, R-60, R-65. "1١:3٠" mixes in Arabic-Indic digits."""
    doc, s = doctor_and_patient(client, sms)
    h = habit(client, s).json()
    assert client.put("/v1/me/reminder", json={"time": bad}, headers=bearer(s)).status_code == 422
    assert client.put(f"/v1/me/habits/{h['id']}/reminder", json={"time": bad}, headers=bearer(s)).status_code == 422
    assert prescribe(client, doc, s, **COURSE | {"times": [bad]}).status_code == 422


# --- 6. Doses (PRD 5.3) ---------------------------------------------------


def _course(client, sms, **over):
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    s = linked_patient(client, sms, doctor)
    med = prescribe(client, doc, s, **COURSE | over).json()
    return doc, s, med


def _dose(client, s, med, **over):
    body = {"medication_id": med["id"], "day": TODAY, "time": "08:00", "status": "taken"} | over
    return client.put("/v1/me/doses", json=body, headers=bearer(s))


def test_dose_answers_follow_the_course_dates_and_read_back_as_history(client, sms):
    """R-69, R-70: the last day of a course can be answered, the day after
    cannot; past answers read back on their day; an unanswered past dose is
    missed."""
    _, s, med = _course(client, sms, start_date="2026-10-10", end_date="2026-10-16")
    assert _dose(client, s, med, day="2026-10-16").status_code == 200
    r = _dose(client, s, med, day=TODAY)
    assert r.status_code == 422 and r.json()["detail"]["code"] == "dose_not_scheduled"
    r = _dose(client, s, med, day="2026-10-14")
    assert r.status_code == 422 and r.json()["detail"]["code"] == "dose_day_out_of_range"
    assert _dose(client, s, med, day="2026-10-16", status="skipped").json()["status"] == "skipped"
    assert [d["status"] for d in doses(client, s, "2026-10-16").json()] == ["skipped"]
    assert [d["status"] for d in doses(client, s, "2026-10-15").json()] == ["missed"]
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(DoseLog)) == 1


def test_doses_only_for_the_patients_own_running_medicines(client, sms):
    """R-70: another patient's medicine, a stopped one and an unknown id all
    look unknown."""
    doc, s, med = _course(client, sms)
    other = linked_patient(client, sms, make_doctor(), "0661234502")
    assert _dose(client, other, med).status_code == 404
    assert _dose(client, s, med, medication_id=str(uuid.uuid4())).status_code == 404
    client.delete(f"/v1/staff/patients/{pid(s)}/medications/{med['id']}", headers=bearer(doc))
    r = _dose(client, s, med)
    assert r.status_code == 404 and r.json()["detail"]["code"] == "medication_not_found"


def test_the_patient_cannot_create_or_edit_medications(client, sms):
    """R-68 (PRD 3 "cannot edit their medications")."""
    doc, s, med = _course(client, sms)
    for method, url in (("POST", "/v1/me/medications"), ("PUT", f"/v1/me/medications/{med['id']}"),
                        ("PATCH", f"/v1/me/medications/{med['id']}"), ("DELETE", f"/v1/me/medications/{med['id']}")):
        r = client.request(method, url, json=COURSE, headers=bearer(s))
        assert r.status_code in (404, 405), (method, url, r.status_code)
    staff = f"/v1/staff/patients/{pid(s)}/medications"
    assert client.post(staff, json=COURSE | {"start_date": TODAY}, headers=bearer(s)).status_code == 403
    assert client.delete(f"{staff}/{med['id']}", headers=bearer(s)).status_code == 403
    assert [m["id"] for m in client.get(staff, headers=bearer(doc)).json()] == [med["id"]]


def test_question_snooze_is_not_an_answer_the_server_keeps(client, sms):
    """QUESTION API-17 (R-71, G-11). PRD 5.3: "Taken / Skipped / Snooze;
    history syncs to the server". The API keeps taken and skipped only."""
    _, s, med = _course(client, sms, start_date="2026-10-10")
    for status in ("snooze", "snoozed", "missed", "due"):
        assert _dose(client, s, med, status=status).status_code == 422, status


def test_question_a_dose_can_be_answered_for_tomorrow(client, sms):
    """QUESTION API-18 (G-04). The dose window is clinic today-2..today+1,
    so "taken" is accepted for a dose of tomorrow (Algeria has one time zone,
    the clinic day is the phone's day), and counts as taken for the
    missed_doses alert."""
    _, s, med = _course(client, sms, start_date="2026-10-10")
    assert _dose(client, s, med, day="2026-10-18").status_code == 200


def test_question_a_stopped_medicine_leaves_the_patients_past_days(client, sms):
    """QUESTION API-19 (R-73). After the doctor stops a medicine, the
    patient's own past answers for it are no longer listed on any day."""
    doc, s, med = _course(client, sms, start_date="2026-10-10")
    _dose(client, s, med, day="2026-10-16")
    assert [d["status"] for d in doses(client, s, "2026-10-16").json()] == ["taken"]
    client.delete(f"/v1/staff/patients/{pid(s)}/medications/{med['id']}", headers=bearer(doc))
    assert doses(client, s, "2026-10-16").json() == []
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(DoseLog)) == 1


@pytest.mark.xfail(strict=True, reason="QA API-10: no staff route returns the patient's dose answers (medication adherence)")
def test_the_doctor_reads_medication_adherence(client, sms):
    """R-74 (PRD 7 patient file "medication adherence", 5.3 "history syncs
    to the server"). Every staff GET under the patient is probed for the
    patient's "taken"."""
    doc, s, med = _course(client, sms, start_date="2026-10-10")
    a = add(client, s).json()
    assert _dose(client, s, med).status_code == 200
    seen = []
    for path, ops in app.openapi()["paths"].items():
        if path.startswith("/v1/staff/patients/{patient_id}") and "get" in ops:
            url = (path.replace("{patient_id}", pid(s)).replace("{addiction_id}", a["id"])
                   .replace("{medication_id}", med["id"]))
            r = client.get(url, headers=bearer(doc))
            seen.append((url, r.status_code))
            if r.status_code == 200 and '"taken"' in r.text:
                return
    pytest.fail(f"no staff route shows the answer; probed {seen}")


@pytest.mark.xfail(strict=True, reason="QA API-11: the doctor can prescribe and stop a medicine but not edit its schedule")
def test_the_doctor_can_edit_a_schedule():
    """R-66 (PRD 7 "Medications: create and edit schedules per patient")."""
    ops = app.openapi()["paths"].get("/v1/staff/patients/{patient_id}/medications/{medication_id}", {})
    assert {"put", "patch"} & set(ops), sorted(ops)


# --- 7. Quote of the day (PRD 5.2) ----------------------------------------


def test_the_quote_changes_at_midnight_in_algiers_in_both_languages(client, sms):
    """R-75, R-78, day boundary: one quote per clinic day."""
    _, s = doctor_and_patient(client, sms)  # the seed adds the clinic's quotes
    add(client, s)
    move_to(client, datetime(2026, 10, 17, 22, 59), s)  # 23:59 on 10-17 in Algiers
    before = client.get("/v1/me/quote", headers=bearer(s)).json()
    move_to(client, datetime(2026, 10, 17, 23, 1), s)  # 00:01 on 10-18 in Algiers
    after = client.get("/v1/me/quote", headers=bearer(s)).json()
    move_to(client, datetime(2026, 10, 18, 0, 30), s)  # new UTC day, same Algiers day
    same = client.get("/v1/me/quote", headers=bearer(s)).json()
    assert before != after == same
    for q in (before, after):
        assert q["text_ar"].strip() and q["text_fr"].strip()


@pytest.mark.xfail(strict=True, reason="QA API-12: quotes have no recovery stage, so the quote of the day ignores the patient's stage")
def test_the_quote_is_chosen_by_recovery_stage():
    """R-77 (PRD 5.2 "chosen by addiction type and recovery stage"; 9 Quote
    has "stage")."""
    assert "stage" in Quote.__table__.columns


@pytest.mark.xfail(strict=True, reason="QA API-13: no route lets the super admin manage the quote library or a doctor add a quote")
def test_the_quote_library_is_managed_from_the_dashboard():
    """R-79 (PRD 5.2 "Library managed by the super admin; doctors can add
    their own", 7 super admin screens)."""
    assert any("quote" in p for p in app.openapi()["paths"] if p.startswith("/v1/staff")), "no staff quote route"


# --- 8. Day boundaries (PRD 8.6 clinic in Algeria; G-03) -------------------


def test_doses_and_ticks_follow_the_algiers_day_after_midnight(client, sms):
    """R-47: at 00:30 in Algiers (23:30 UTC the day before), today's doses
    are the Algiers day's, and a tick or habit for the Algiers day is
    accepted."""
    doc, s, med = _course(client, sms, start_date="2026-10-10")
    h = habit(client, s).json()
    move_to(client, datetime(2026, 10, 17, 23, 30), s)  # 00:30 on 10-18 in Algiers
    assert [d["status"] for d in doses(client, s).json()] == ["due"]
    assert _dose(client, s, med, day="2026-10-18").status_code == 200
    assert [d["status"] for d in doses(client, s).json()] == ["taken"]
    assert client.put("/v1/me/checkins/2026-10-18", headers=bearer(s)).status_code == 204
    assert client.put(f"/v1/me/habits/{h['id']}/days/2026-10-18", headers=bearer(s)).status_code == 204


@pytest.mark.xfail(strict=True, reason="QA API-03: the doctor's chart and habit summary end at the UTC date and miss the patient's day from 00:00 to 01:00 Algiers")
def test_the_doctor_sees_the_patients_day_right_after_midnight_in_algiers(client, sms):
    """R-118, R-63."""
    doc, s = doctor_and_patient(client, sms)
    a = add(client, s).json()
    h = habit(client, s).json()
    move_to(client, datetime(2026, 10, 17, 23, 30), s, doc)  # 00:30 on 10-18 in Algiers
    assert check(client, s, a, day="2026-10-18", craving=4).status_code == 204
    assert client.put(f"/v1/me/habits/{h['id']}/days/2026-10-18", headers=bearer(s)).status_code == 204
    chart = client.get(f"/v1/staff/patients/{pid(s)}/addictions/{a['id']}/checks", headers=bearer(doc)).json()
    summary = client.get(f"/v1/staff/patients/{pid(s)}/habits", headers=bearer(doc)).json()
    assert [c["day"] for c in chart["checks"]] == ["2026-10-18"]
    assert summary[0]["done_days"] == 1


# --- 9. Audit rows (PRD 5.6 privacy, 8.3) ---------------------------------


def test_recovery_audit_rows_name_the_row_only(client, sms):
    """R-15, R-62, R-67 (R-94): added, relapse, review, habit, prescribe and
    stop are audited by row id, never by substance, note, words or drug."""
    doc, s = doctor_and_patient(client, sms)
    a = add(client, s, substance="Produit QA").json()
    relapse(client, s, a, note="Note privée QA")
    review(client, doc, s, a, "confirm")
    h = habit(client, s, kind="custom", text="Mots à moi").json()
    client.delete(f"/v1/me/habits/{h['id']}", headers=bearer(s))
    med = prescribe(client, doc, s, **COURSE | {"start_date": TODAY}).json()
    client.delete(f"/v1/staff/patients/{pid(s)}/medications/{med['id']}", headers=bearer(doc))
    with Session(engine) as db:
        rows = db.scalars(select(AuditLog)).all()
    by_action = {r.action: r.target for r in rows}
    assert by_action["addiction.added"] == by_action["relapse.logged"] == by_action["addiction.confirmed"] == a["id"]
    assert by_action["habit.added"] == by_action["habit.removed"] == h["id"]
    assert by_action["medication.prescribed"] == by_action["medication.stopped"] == med["id"]
    text = " ".join(f"{r.action} {r.target}" for r in rows)
    for secret in ("Produit QA", "Note privée", "Mots à moi", "Traitement QA", "1 unité", "nicotine", "tobacco"):
        assert secret not in text


# --- 10. Double submissions (PRD 5.6 privacy, 8.3; R-54, R-58) -------------


@contextmanager
def another_request_saves_first(model, twin):
    """Replays a double tap deterministically: right before this request
    inserts its row, the other request's row for the same key lands and
    commits (what two near-simultaneous requests do on a real server)."""
    fired = []

    class Racing(Session):
        def add(self, instance, *args, **kwargs):
            if isinstance(instance, model) and not fired:
                fired.append(True)
                with Session(engine) as other:
                    other.add(twin())
                    other.commit()
            super().add(instance, *args, **kwargs)

    maker = sessionmaker(bind=engine, class_=Racing, autoflush=False, expire_on_commit=False)

    def racing_db():
        with maker() as db:
            yield db

    app.dependency_overrides[get_db] = racing_db
    try:
        yield fired
    finally:
        app.dependency_overrides.pop(get_db, None)


def _double_tap_case(client, sms, kind):
    """(model, twin factory, the request) for one kind of same-day save."""
    doctor = make_doctor()
    doc = staff_session(client, doctor)
    s = linked_patient(client, sms, doctor)
    day = date(2026, 10, 17)
    h = bearer(s)
    if kind == "check":
        a = add(client, s).json()
        twin = lambda: AddictionCheck(addiction_id=uuid.UUID(a["id"]), day=day, used=False,  # noqa: E731
                                      craving=1, signals=NICOTINE, created_at=clock.now())
        body = {"used": False, "craving": 5, "signals": {"irritability": 4, "restlessness": 5}}
        return AddictionCheck, twin, ("PUT", f"/v1/me/addictions/{a['id']}/checks/{TODAY}", body, h)
    if kind == "habit":
        x = habit(client, s).json()
        twin = lambda: HabitLog(habit_id=uuid.UUID(x["id"]), day=day)  # noqa: E731
        return HabitLog, twin, ("PUT", f"/v1/me/habits/{x['id']}/days/{TODAY}", None, h)
    if kind == "tick":
        twin = lambda: DailyCheck(patient_id=uuid.UUID(pid(s)), day=day)  # noqa: E731
        return DailyCheck, twin, ("PUT", f"/v1/me/checkins/{TODAY}", None, h)
    med = prescribe(client, doc, s, **COURSE | {"start_date": TODAY}).json()
    twin = lambda: DoseLog(medication_id=uuid.UUID(med["id"]), day=day, time="08:00",  # noqa: E731
                           status=DoseStatus.skipped)
    body = {"medication_id": med["id"], "day": TODAY, "time": "08:00", "status": "taken"}
    return DoseLog, twin, ("PUT", "/v1/me/doses", body, h)


@pytest.mark.xfail(strict=True, reason="QA API-04: a duplicate same-day save (check, habit tick, v1 tick, dose) that loses the race is a 500, not an idempotent answer")
@pytest.mark.parametrize("kind", ["check", "habit", "tick", "dose"])
def test_a_double_tap_is_not_a_server_error(client, sms, kind):
    model, twin, (method, url, body, headers) = _double_tap_case(client, sms, kind)
    quiet = TestClient(app, raise_server_exceptions=False)
    with another_request_saves_first(model, twin) as fired:
        r = quiet.request(method, url, json=body, headers=headers)
    assert fired, "the replayed race did not happen"
    assert r.status_code in (200, 204, 409), (kind, r.status_code)


@pytest.mark.xfail(strict=True, reason="QA API-05: the 500 of a duplicate daily check carries the craving and signal answers, and uvicorn logs it with its traceback")
def test_a_failed_check_save_keeps_the_answers_out_of_the_error(client, sms):
    """What uvicorn writes to the server log for an unhandled error is the
    exception with its traceback (h11_impl.py: logger.error(..., exc_info))."""
    model, twin, (method, url, body, headers) = _double_tap_case(client, sms, "check")
    logged = ""
    with another_request_saves_first(model, twin):
        try:
            client.request(method, url, json=body, headers=headers)
        except Exception as exc:  # noqa: BLE001 - this is what the server would log
            logged = "".join(traceback.format_exception(exc))
    assert '"irritability": 4' not in logged and '"restlessness": 5' not in logged, logged[-600:]


ON_POSTGRES = engine.dialect.name == "postgresql"


@pytest.mark.skipif(not ON_POSTGRES, reason="needs PostgreSQL (real concurrent transactions)")
@pytest.mark.xfail(strict=True, reason="QA API-04: parallel duplicate same-day saves on PostgreSQL end in 500s")
def test_parallel_duplicate_saves_on_postgresql(client, sms):
    """R-54, R-58 for real: 8 identical requests at once, for several days
    and rows. Relapses are counted too (no unique rule, see API-15)."""
    doc, s = doctor_and_patient(client, sms)
    quiet = TestClient(app, raise_server_exceptions=False)
    h = bearer(s)
    addictions = [add(client, s).json() for _ in range(4)]
    habits = [habit(client, s, kind=k).json() for k in ("sport", "water", "reading", "sleep")]
    requests = []
    for day in ("2026-10-15", "2026-10-16", TODAY):
        for a in addictions:
            requests.append(("PUT", f"/v1/me/addictions/{a['id']}/checks/{day}",
                             {"used": False, "craving": 3, "signals": NICOTINE}))
        for x in habits:
            requests.append(("PUT", f"/v1/me/habits/{x['id']}/days/{day}", None))
        requests.append(("PUT", f"/v1/me/checkins/{day}", None))
    results = []
    with ThreadPoolExecutor(max_workers=8) as pool:
        for method, url, body in requests:
            results += [(url, r.status_code) for r in pool.map(
                lambda _: quiet.request(method, url, json=body, headers=h), range(8))]
        relapses = list(pool.map(lambda _: relapse(quiet, s, addictions[0]), range(8)))
    with Session(engine) as db:
        kept = db.scalar(select(func.count()).select_from(Relapse))
        alerts = db.scalar(select(func.count()).select_from(Alert).where(Alert.type == "relapse"))
    print(f"relapse codes {Counter(r.status_code for r in relapses)}, rows {kept}, alerts {alerts}")
    codes = Counter(code for _, code in results)
    print(f"save codes {codes}")
    assert set(codes) == {204}, codes
