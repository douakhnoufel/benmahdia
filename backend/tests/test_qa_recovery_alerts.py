"""QA recovery 2026-10-26, alerts-privacy tester (prefix ALERT).

Alerts (PRD 5.1, 5.3, 5.6, 7, 12.3): craving_high, no_checkin, missed_doses,
relapse and milestone; who receives them, what they carry, de-duplication and
Algiers day boundaries. Privacy (PRD 5.6 Privacy, 8.3): answers, relapse
notes, substance and drug names never reach alerts, logs, SMS or the audit
log. Every name below is a fake marker, never real patient data.

SEC-02 is settled by the shared-clinic rule (PRD 3): every doctor of the
clinic sees every alert; the stored doctor_id is only the doctor it was
raised for."""

import json
import logging
import uuid
from datetime import date, datetime, timedelta

import pytest
from sqlalchemy import event, insert, select
from sqlalchemy.orm import Session

from app import jobs, scheduling
from app.alerts_job import craving_alerts, milestone_alerts, missed_dose_alerts, no_checkin_alerts
from app.clock import clock
from app.db import engine
from app.models import (
    Addiction,
    AddictionCheck,
    Alert,
    AppointmentStatus,
    AuditLog,
    DailyCheck,
)

from .booking_helpers import add_appointment
from .conftest import START, bearer
from .test_medications import prescribe, staff_session
from .test_staff import doc_headers, other_doctor
from .test_substance_tracking import add, check, setup

# Fake markers: if one shows up somewhere it must not, the test says where.
SUBSTANCE = "QA-substance-zx"
NOTE = "QA-relapse-note-zx"
DRUG = "QA-drugname-zx"
AMOUNT = "QA-amount-zx"
INSTRUCTIONS = "QA-instructions-zx"
OWN_WORDS = "QA-own-habit-zx"
MARKERS = (SUBSTANCE, NOTE, DRUG, AMOUNT, INSTRUCTIONS, OWN_WORDS)
# Clinical words an alert must not carry either (the nicotine profile's
# type and signal keys).
CLINICAL = ("nicotine", "tobacco", "irritability", "restlessness")
ALERT_FIELDS = {"id", "patient_id", "patient_phone", "type", "priority", "read", "created_at"}

D = date.fromisoformat


def nightly(day: str) -> datetime:
    """The nightly run on [day]: 00:10 in Algiers, as naive UTC."""
    return scheduling.to_utc(D(day), 10)


def refresh(client, *sessions, doc=None) -> None:
    """Access tokens follow the frozen clock: renew them after a move."""
    for s in sessions:
        r = client.post("/v1/auth/refresh", json={"refresh_token": s["refresh_token"]})
        assert r.status_code == 200, r.text
        s.update(r.json())
    if doc is not None:
        doc.update(staff_session(client, doc["doctor"]))


def seed_checks(addiction_id, *days, craving=4, used=False, signals=None) -> None:
    """Saved checks, written straight to the table the nightly job reads."""
    with Session(engine) as db:
        for day in days:
            db.add(AddictionCheck(
                addiction_id=uuid.UUID(str(addiction_id)), day=D(day), used=used, craving=craving,
                signals=signals or {"irritability": 2, "restlessness": 2},
            ))
        db.commit()


def set_craving(addiction_id, day: str, craving: int) -> None:
    with Session(engine) as db:
        c = db.scalar(select(AddictionCheck).where(
            AddictionCheck.addiction_id == uuid.UUID(str(addiction_id)), AddictionCheck.day == D(day)))
        c.craving = craving
        db.commit()


def created(addiction_id, at: datetime) -> None:
    with Session(engine) as db:
        db.get(Addiction, uuid.UUID(str(addiction_id))).created_at = at
        db.commit()


def run(job) -> int:
    with Session(engine) as db:
        return job(db)


def alerts(kind: str | None = None) -> list[tuple]:
    """(doctor_id, patient_id, type) of every alert, oldest first."""
    with Session(engine) as db:
        query = select(Alert).order_by(Alert.created_at)
        if kind is not None:
            query = query.where(Alert.type == kind)
        return [(a.doctor_id, a.patient_id, a.type) for a in db.scalars(query)]


def pid(s) -> uuid.UUID:
    return uuid.UUID(s["user"]["id"])


# --- craving_high (R-104, R-105) -------------------------------------------
# Frozen clock: 2026-10-17 19:00 Algiers; the last three full days are
# 10-14, 10-15 and 10-16.


def test_high_days_split_across_two_addictions_raise_nothing(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    b = add(client, s, profile="thc").json()
    seed_checks(a["id"], "2026-10-15", "2026-10-16", craving=5)
    seed_checks(b["id"], "2026-10-14", craving=5)
    # Every day of the window had a high craving, but on two addictions.
    assert run(craving_alerts) == 0
    seed_checks(a["id"], "2026-10-14", craving=5)
    assert run(craving_alerts) == 1


def test_a_day_without_a_check_breaks_the_craving_run(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    seed_checks(a["id"], "2026-10-13", "2026-10-14", "2026-10-16", craving=5)  # 10-15 missing
    assert run(craving_alerts) == 0
    seed_checks(a["id"], "2026-10-15", craving=4)
    assert run(craving_alerts) == 1


def test_craving_exactly_four_counts_and_three_does_not(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    seed_checks(a["id"], "2026-10-14", "2026-10-15", craving=4)
    seed_checks(a["id"], "2026-10-16", craving=3)
    assert run(craving_alerts) == 0
    set_craving(a["id"], "2026-10-16", 4)
    assert run(craving_alerts) == 1


def test_two_high_addictions_give_one_alert_for_the_patient(client, sms):
    doc, s = setup(client, sms)
    a = add(client, s).json()
    b = add(client, s, profile="thc").json()
    for x in (a, b):
        seed_checks(x["id"], "2026-10-14", "2026-10-15", "2026-10-16", craving=5)
    assert run(craving_alerts) == 1
    assert alerts() == [(doc["doctor"].user_id, pid(s), "craving_high")]


def test_craving_alert_is_not_repeated_within_three_days_even_once_read(client, sms):
    doc, s = setup(client, sms)
    a = add(client, s).json()
    seed_checks(a["id"], "2026-10-14", "2026-10-15", "2026-10-16", craving=5)
    assert run(craving_alerts) == 1
    [alert] = client.get("/v1/staff/alerts", headers=bearer(doc)).json()
    assert client.post(f"/v1/staff/alerts/{alert['id']}/read", headers=bearer(doc)).status_code == 200
    assert run(craving_alerts) == 0  # the same day, and reading it does not re-arm it
    # The cravings stay high every day after.
    for n, yesterday in ((1, "2026-10-17"), (2, "2026-10-18")):
        clock.frozen = START + timedelta(days=n)
        seed_checks(a["id"], yesterday, craving=5)
        assert run(craving_alerts) == 0, f"day +{n}"
    clock.frozen = START + timedelta(days=3)
    seed_checks(a["id"], "2026-10-19", craving=5)
    assert run(craving_alerts) == 1  # a fresh 3-day run, three days later (G-05)
    assert len(alerts("craving_high")) == 2


def test_craving_window_is_three_algiers_days_at_the_nightly_run(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    seed_checks(a["id"], "2026-10-17", "2026-10-18", "2026-10-19", craving=5)
    # 00:10 on 10-20 in Algiers is still 10-19 in UTC: a UTC window would
    # be 10-16..10-18 and miss the run.
    clock.frozen = nightly("2026-10-20")
    assert clock.frozen == datetime(2026, 10, 19, 23, 10)
    assert run(craving_alerts) == 1


@pytest.mark.xfail(strict=True, reason="QA ALERT-01: a day checked after the nightly run never completes a craving_high run")
def test_a_check_saved_after_the_nightly_run_still_completes_three_high_days(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    seed_checks(a["id"], "2026-10-18", "2026-10-19", craving=5)
    clock.frozen = nightly("2026-10-21")
    assert run(craving_alerts) == 0  # 10-20 is not filled in yet
    # 08:00 in Algiers: the patient fills in yesterday (the API accepts up
    # to two days back), then today with a lower craving.
    clock.frozen = scheduling.to_utc(D("2026-10-21"), 8 * 60)
    refresh(client, s)
    assert check(client, s, a, day="2026-10-20", craving=5).status_code == 204
    assert check(client, s, a, day="2026-10-21", craving=2).status_code == 204
    clock.frozen = nightly("2026-10-22")
    run(craving_alerts)
    # 10-18, 10-19 and 10-20 were three high days in a row.
    assert len(alerts("craving_high")) == 1


# --- no_checkin (R-106, R-107) ---------------------------------------------


def _old_addiction(client, s, **over) -> dict:
    """An addiction tracked since well before the 3-day window."""
    a = add(client, s, **over).json()
    created(a["id"], START - timedelta(days=7))
    return a


def test_no_checkin_is_not_repeated_within_three_days_even_once_read(client, sms):
    doc, s = setup(client, sms)
    _old_addiction(client, s)
    assert run(no_checkin_alerts) == 1
    [alert] = client.get("/v1/staff/alerts", headers=bearer(doc)).json()
    assert alert["type"] == "no_checkin"
    client.post(f"/v1/staff/alerts/{alert['id']}/read", headers=bearer(doc))
    assert run(no_checkin_alerts) == 0
    for n in (1, 2):
        clock.frozen = START + timedelta(days=n)
        assert run(no_checkin_alerts) == 0, f"day +{n}"
    clock.frozen = START + timedelta(days=3)
    assert run(no_checkin_alerts) == 1  # still nothing checked (G-05)


def test_a_check_on_one_of_two_addictions_counts_as_the_days_check(client, sms):
    # QUESTION (rules G-06/G-07 family): with several addictions, one check
    # on any of them is enough for the code; the week strip wants them all.
    _, s = setup(client, sms)
    a = _old_addiction(client, s)
    _old_addiction(client, s, profile="thc")
    seed_checks(a["id"], "2026-10-15")
    assert run(no_checkin_alerts) == 0


def test_a_v1_tick_counts_as_the_days_check(client, sms):
    _, s = setup(client, sms)
    _old_addiction(client, s)
    with Session(engine) as db:
        db.add(DailyCheck(patient_id=pid(s), day=D("2026-10-14")))
        db.commit()
    assert run(no_checkin_alerts) == 0


def test_question_checks_on_a_new_addiction_do_not_count_for_no_checkin(client, sms):
    # QUESTION: the patient checks the addiction added two days ago every
    # day, skips the old one, and still gets no_checkin, although a check on
    # any old addiction would have been enough (test above).
    _, s = setup(client, sms)
    _old_addiction(client, s)
    new = add(client, s, profile="thc").json()
    created(new["id"], START - timedelta(days=2))
    seed_checks(new["id"], "2026-10-15", "2026-10-16")
    assert run(no_checkin_alerts) == 1


def test_question_a_patient_with_no_addiction_never_gets_no_checkin(client, sms):
    # QUESTION G-06: v1 tick only, nothing ticked for days.
    _, s = setup(client, sms)
    clock.frozen = START + timedelta(days=5)
    assert run(no_checkin_alerts) == 0


def test_no_checkin_window_is_three_algiers_days_at_the_nightly_run(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()  # added 10-17 18:00 UTC, before the window
    seed_checks(a["id"], "2026-10-17")  # the day before the window
    seed_checks(a["id"], "2026-10-21")  # the clinic's new day, not a full day yet
    # 00:10 on 10-21 in Algiers (10-20 23:10 UTC): the window is 10-18..10-20.
    # A UTC window (10-17..10-19) would see the 10-17 check.
    clock.frozen = nightly("2026-10-21")
    assert run(no_checkin_alerts) == 1


def test_an_addiction_added_after_midnight_in_algiers_is_new_for_no_checkin(client, sms):
    doc, s1 = setup(client, sms)
    _, s2 = setup(client, sms, "0661234502")
    a1 = add(client, s1).json()
    a2 = add(client, s2).json()
    # Both on 10-17 in UTC; in Algiers a1 is 23:30 on 10-17 and a2 is 00:30
    # on 10-18, the first day of the 10-18..10-20 window.
    created(a1["id"], datetime(2026, 10, 17, 22, 30))
    created(a2["id"], datetime(2026, 10, 17, 23, 30))
    clock.frozen = nightly("2026-10-21")
    assert run(no_checkin_alerts) == 1
    assert alerts("no_checkin") == [(doc["doctor"].user_id, pid(s1), "no_checkin")]


# --- missed doses (R-101, R-102) -------------------------------------------
# MED starts 2026-10-10 with doses at 08:00 and 20:00.


def _answer(client, s, med, day, time="08:00", status="taken"):
    r = client.put("/v1/me/doses", headers=bearer(s),
                   json={"medication_id": med["id"], "day": day, "time": time, "status": status})
    assert r.status_code == 200, r.text


def test_one_missed_day_after_a_taken_day_raises_nothing(client, sms):
    doc, s = setup(client, sms)
    med = prescribe(client, doc, s).json()
    _answer(client, s, med, "2026-10-15")  # 10-16: nothing; 10-15: taken
    assert run(missed_dose_alerts) == 0


def test_missed_doses_once_a_day_even_once_read_then_again_the_next_day(client, sms):
    doc, s = setup(client, sms)
    prescribe(client, doc, s)
    assert run(missed_dose_alerts) == 1
    [alert] = client.get("/v1/staff/alerts", headers=bearer(doc)).json()
    client.post(f"/v1/staff/alerts/{alert['id']}/read", headers=bearer(doc))
    assert run(missed_dose_alerts) == 0
    clock.frozen = START + timedelta(days=1)
    assert run(missed_dose_alerts) == 1  # misses go on: daily repeat (G-05)


def test_a_dose_taken_on_the_algiers_day_counts_at_the_nightly_run(client, sms):
    doc, s = setup(client, sms)
    med = prescribe(client, doc, s).json()
    _answer(client, s, med, "2026-10-17")
    # 00:10 on 10-18 in Algiers (10-17 23:10 UTC): the full days are 10-17
    # (taken) and 10-16. A UTC day would look at 10-15 and 10-16 instead.
    clock.frozen = nightly("2026-10-18")
    assert run(missed_dose_alerts) == 0


def test_missed_doses_dedupe_follows_the_algiers_day(client, sms):
    doc, s = setup(client, sms)
    prescribe(client, doc, s)
    clock.frozen = nightly("2026-10-18")  # 10-17 23:10 UTC
    assert run(missed_dose_alerts) == 1
    clock.frozen += timedelta(hours=1)  # a new UTC day, the same Algiers day
    assert run(missed_dose_alerts) == 0
    clock.frozen = nightly("2026-10-19")
    assert run(missed_dose_alerts) == 1


def test_question_skipped_doses_count_as_missed(client, sms):
    # QUESTION G-04: "skipped" on both days raises missed_doses.
    doc, s = setup(client, sms)
    med = prescribe(client, doc, s).json()
    for day in ("2026-10-15", "2026-10-16"):
        for t in ("08:00", "20:00"):
            _answer(client, s, med, day, t, "skipped")
    assert run(missed_dose_alerts) == 1


def test_question_one_dose_of_two_taken_clears_the_day(client, sms):
    # QUESTION G-04: half the doses missed on both days raises nothing.
    doc, s = setup(client, sms)
    med = prescribe(client, doc, s).json()
    for day in ("2026-10-15", "2026-10-16"):
        _answer(client, s, med, day, "08:00", "taken")
    assert run(missed_dose_alerts) == 0


# --- relapse and milestone (R-99, R-32) ------------------------------------


def test_relapse_alert_is_high_priority_and_carries_no_note(client, sms):
    doc, s = setup(client, sms)
    a = add(client, s, substance=SUBSTANCE).json()
    r = client.post(f"/v1/me/addictions/{a['id']}/relapses", json={"note": NOTE}, headers=bearer(s))
    assert r.status_code == 201, r.text
    [alert] = client.get("/v1/staff/alerts", headers=bearer(doc)).json()
    assert alert["type"] == "relapse" and alert["priority"] == "high"
    assert alert["patient_id"] == s["user"]["id"] and set(alert) == ALERT_FIELDS
    assert NOTE not in json.dumps(alert) and SUBSTANCE not in json.dumps(alert)


def test_milestone_reached_tells_the_doctor(client, sms):
    doc, s = setup(client, sms)
    add(client, s)  # 10 days clean: milestone 7
    assert run(milestone_alerts) == 1
    assert alerts() == [(doc["doctor"].user_id, pid(s), "milestone")]


# --- recipient (R-99, R-100; fix 71d844c; SEC-02) ---------------------------


def test_nightly_alerts_skip_a_doctor_the_patient_only_holds_a_slot_with(client, sms):
    doc, s = setup(client, sms)  # paid visit three days ago
    held = other_doctor()
    add_appointment(held, pid(s), START + timedelta(days=2),
                    status=AppointmentStatus.awaiting_payment, hold_expires_at=START + timedelta(minutes=10))
    a = add(client, s).json()
    seed_checks(a["id"], "2026-10-14", "2026-10-15", "2026-10-16", craving=5)
    assert run(craving_alerts) == 1
    assert run(milestone_alerts) == 1
    clock.frozen = START + timedelta(days=4)  # nothing checked since
    assert run(no_checkin_alerts) == 1
    kinds = alerts()
    assert {k for _, _, k in kinds} == {"craving_high", "milestone", "no_checkin"}
    assert {d for d, _, _ in kinds} == {doc["doctor"].user_id}


def _listed_to(client, headers) -> list[tuple]:
    r = client.get("/v1/staff/alerts", headers=headers)
    assert r.status_code == 200, r.text
    return sorted((x["patient_id"], x["type"]) for x in r.json())


def test_a_doctor_the_patient_cancelled_with_still_sees_the_alert(client, sms):
    """QA SEC-02, re-baselined to the shared-clinic rule (PRD 3): alerts go
    to every doctor of the clinic, so a doctor with only a cancelled visit
    sees the relapse alert too. One alert row is stored, not one per doctor."""
    doc, s = setup(client, sms)
    other = other_doctor()
    add_appointment(other, pid(s), START + timedelta(days=5), status=AppointmentStatus.cancelled)
    a = add(client, s).json()
    client.post(f"/v1/me/addictions/{a['id']}/relapses", json={}, headers=bearer(s))
    assert [(p, k) for _, p, k in alerts("relapse")] == [(pid(s), "relapse")]
    expected = [(str(pid(s)), "relapse")]
    assert _listed_to(client, bearer(doc)) == expected
    assert _listed_to(client, doc_headers(client, "other@example.invalid")) == expected


def test_one_patients_alerts_reach_every_doctor_of_the_clinic(client, sms):
    """QA SEC-02, re-baselined (PRD 3): with two paid doctors, the relapse
    and the missed-dose alerts are listed to both of them, the same list."""
    doc, s = setup(client, sms)
    other = other_doctor()
    prescribe(client, doc, s)  # by the first doctor
    add_appointment(other, pid(s), START + timedelta(days=5))  # next paid visit, another doctor
    a = add(client, s).json()
    client.post(f"/v1/me/addictions/{a['id']}/relapses", json={}, headers=bearer(s))
    run(missed_dose_alerts)
    first = _listed_to(client, bearer(doc))
    second = _listed_to(client, doc_headers(client, "other@example.invalid"))
    assert first == second
    assert {k for _, k in first} >= {"relapse"}
    assert {p for p, _ in first} == {str(pid(s))}


# --- what an alert carries (R-96) ------------------------------------------


def test_every_alert_kind_names_only_the_kind_and_the_patient(client, sms):
    doc, s = setup(client, sms)
    a = add(client, s, substance=SUBSTANCE).json()
    seed_checks(a["id"], "2026-10-14", "2026-10-15", "2026-10-16", craving=5, used=True,
                signals={"irritability": 5, "restlessness": 5})
    prescribe(client, doc, s, name=DRUG, amount=AMOUNT, instructions=INSTRUCTIONS)
    assert run(craving_alerts) == 1
    assert run(milestone_alerts) == 1
    assert run(missed_dose_alerts) == 1
    client.post(f"/v1/me/addictions/{a['id']}/relapses", json={"note": NOTE}, headers=bearer(s))
    _, s2 = setup(client, sms, "0661234502")
    _old_addiction(client, s2, substance=SUBSTANCE)
    assert run(no_checkin_alerts) == 1

    listed = client.get("/v1/staff/alerts", headers=bearer(doc)).json()
    assert {x["type"] for x in listed} == {"craving_high", "milestone", "missed_doses", "relapse", "no_checkin"}
    for x in listed:
        assert set(x) == ALERT_FIELDS, x["type"]
    text = json.dumps(listed).lower()
    for word in MARKERS + CLINICAL:
        assert word.lower() not in text, word


def test_the_alert_table_has_no_room_for_medical_content():
    assert {c.name for c in Alert.__table__.columns} == {
        "id", "doctor_id", "patient_id", "type", "priority", "read", "created_at"}


# --- logs, SMS and the audit log (R-94, R-95) ------------------------------


def _everything(client, sms, doc, s) -> None:
    """Every recovery write with medical content, then a week of nightly runs."""
    h = bearer(s)
    a = add(client, s, substance=SUBSTANCE).json()
    assert check(client, s, a, craving=5, used=True).status_code == 204
    base = f"/v1/staff/patients/{s['user']['id']}/addictions/{a['id']}"
    assert client.post(f"{base}/confirm", headers=bearer(doc)).status_code == 200
    assert client.put(f"{base}/profile", json={"profile": "thc"}, headers=bearer(doc)).status_code == 200
    r = client.post(f"/v1/me/addictions/{a['id']}/relapses", json={"note": NOTE}, headers=h)
    assert r.status_code == 201, r.text
    med = prescribe(client, doc, s, name=DRUG, amount=AMOUNT, instructions=INSTRUCTIONS).json()
    _answer(client, s, med, "2026-10-17", "08:00", "skipped")
    r = client.post("/v1/me/habits", json={"kind": "custom", "text": OWN_WORDS, "reminder_time": "20:00"},
                    headers=h)
    assert r.status_code == 201, r.text
    assert client.put(f"/v1/me/habits/{r.json()['id']}/days/2026-10-17", headers=h).status_code < 300
    assert client.delete(f"/v1/me/habits/{r.json()['id']}", headers=h).status_code < 300
    client.get("/v1/staff/alerts", headers=bearer(doc))
    client.get(f"{base}/checks", headers=bearer(doc))
    client.get(f"/v1/staff/patients/{s['user']['id']}/addictions", headers=bearer(doc))
    url = f"/v1/staff/patients/{s['user']['id']}/medications"
    assert client.delete(f"{url}/{med['id']}", headers=bearer(doc)).status_code == 204
    prescribe(client, doc, s, name=DRUG, amount=AMOUNT, instructions=INSTRUCTIONS)
    for n in range(1, 8):
        clock.frozen = nightly("2026-10-17") + timedelta(days=n)
        with Session(engine) as db:
            assert None not in jobs.run_once(db).values()
    assert alerts("missed_doses") and alerts("no_checkin") and alerts("milestone")


def test_recovery_writes_and_nightly_jobs_log_no_medical_content(client, sms, caplog):
    caplog.set_level(logging.DEBUG)
    doc, s = setup(client, sms)
    _everything(client, sms, doc, s)
    logged = caplog.text + " ".join(repr(r.args) for r in caplog.records)
    for word in MARKERS:
        assert word not in logged, word
    assert '"irritability"' not in logged and '"sleep"' not in logged


def test_a_failing_job_logs_no_medical_content(client, sms, caplog, monkeypatch):
    doc, s = setup(client, sms)
    prescribe(client, doc, s, name=DRUG, amount=AMOUNT, instructions=INSTRUCTIONS)

    def broken(db):
        # A real database error inside a job's work (the alerts table is gone).
        db.connection().exec_driver_sql("DROP TABLE alerts")
        return missed_dose_alerts(db)

    monkeypatch.setattr(jobs, "missed_dose_alerts", broken)
    caplog.set_level(logging.DEBUG)
    with Session(engine) as db:
        assert jobs.run_once(db)["missed_dose_alerts"] is None
    assert "job missed_dose_alerts failed" in caplog.text
    for word in MARKERS:
        assert word not in caplog.text, word


@pytest.mark.xfail(strict=True, reason="QA ALERT-02: a database error on a recovery write carries the answers into the server log")
def test_a_database_error_on_a_check_does_not_put_answers_in_the_log(client, sms):
    # Two first saves of one check at the same moment (R-54): the other
    # request's row lands between this one's lookup and its insert. uvicorn
    # logs an unhandled error with its traceback ("Exception in ASGI
    # application"), so the formatted exception is what reaches the log.
    _, s = setup(client, sms)
    a = add(client, s).json()
    raced = []

    def other_request_wins(session, flush_context, instances):
        if raced:
            return
        raced.append(True)
        session.connection().execute(insert(AddictionCheck).values(
            id=uuid.uuid4(), addiction_id=uuid.UUID(a["id"]), day=D("2026-10-17"), used=False,
            craving=1, signals={"irritability": 1, "restlessness": 1},
            created_at=START, updated_at=START,
        ))

    event.listen(Session, "before_flush", other_request_wins)
    try:
        with pytest.raises(Exception) as err:
            check(client, s, a, craving=5, used=True, signals={"irritability": 5, "restlessness": 4})
    finally:
        event.remove(Session, "before_flush", other_request_wins)
    assert raced
    logged = logging.Formatter().formatException((err.type, err.value, err.tb))
    assert "IntegrityError" in logged  # the race really happened
    assert '"irritability": 5' not in logged


def test_no_recovery_event_sends_an_sms(client, sms):
    doc, s = setup(client, sms)
    before = list(sms.sent)
    _everything(client, sms, doc, s)
    assert sms.sent == before


def test_recovery_audit_rows_hold_row_ids_only(client, sms):
    doc, s = setup(client, sms)
    _everything(client, sms, doc, s)
    with Session(engine) as db:
        rows = db.scalars(select(AuditLog)).all()
    actions = {r.action for r in rows}
    assert {"addiction.added", "addiction.confirmed", "addiction.profile_set", "relapse.logged",
            "medication.prescribed", "medication.stopped", "habit.added", "habit.removed"} <= actions
    recovery = ("addiction.", "relapse.", "medication.", "habit.", "dose.", "check.", "alert.")
    for r in rows:
        if r.action.startswith(recovery) and r.target is not None:
            uuid.UUID(r.target)  # a row id, nothing else
        for word in MARKERS + CLINICAL:
            assert word not in f"{r.action} {r.target}".lower(), (r.action, word)


# --- habits, deleted accounts (R-64, R-110) ---------------------------------


def test_habits_never_raise_an_alert(client, sms):
    _, s = setup(client, sms)
    r = client.post("/v1/me/habits", json={"kind": "sport", "reminder_time": "18:00"}, headers=bearer(s))
    assert r.status_code == 201, r.text
    clock.frozen = START + timedelta(days=6)  # never done
    with Session(engine) as db:
        results = jobs.run_once(db)
    assert None not in results.values()
    assert alerts() == []


@pytest.mark.xfail(strict=True, reason="QA ALERT-04: deleting the account does not notify the doctor (PRD 12.5 step 2)")
def test_the_doctor_is_told_when_a_patient_deletes_their_account(client, sms):
    doc, s = setup(client, sms)
    r = client.request("DELETE", "/v1/me", json={"password": "sobre2026"}, headers=bearer(s))
    assert r.status_code == 204, r.text
    assert [p for _, p, _ in alerts()] == [pid(s)]


def test_question_nightly_alerts_continue_for_a_deleted_account(client, sms):
    # QUESTION G-12: the account is disabled at once (PRD 12.5), its file is
    # 404 for the doctor, yet craving alerts (with the phone) keep coming.
    doc, s = setup(client, sms)
    a = add(client, s).json()
    seed_checks(a["id"], "2026-10-14", "2026-10-15", "2026-10-16", craving=5)
    r = client.request("DELETE", "/v1/me", json={"password": "sobre2026"}, headers=bearer(s))
    assert r.status_code == 204, r.text
    assert run(craving_alerts) == 1
    url = f"/v1/staff/patients/{s['user']['id']}/addictions"
    assert client.get(url, headers=bearer(doc)).status_code == 404
