"""QA recovery run 2026-10-26, security-isolation tester.

Checks the PRD 3 role matrix on every recovery route that takes an id or a
patient id: a patient reaches only their own rows, and another patient's id
answers exactly like a random one; a doctor reaches clinical data (addictions,
checks, habits, goals, medications, alerts) only for their own patients; an
unpaid hold, the super admin and a patient token open nothing; audit rows and
logs carry row ids only. Fake data only: test phones 06612345NN, the seeded
doctor plus test doctors, and placeholder words (QA-SUBST-A, QA-DRUG-A...)
instead of real substances, drugs or notes.

A test marked xfail(strict=True) exposes a real bug (see
qa/recovery/2026-10-26/security-isolation.md). When the bug is fixed the test
flips to failing; remove the marker then."""

import logging
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from threading import Barrier

import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.alerts_job import craving_alerts, milestone_alerts, missed_dose_alerts, no_checkin_alerts
from app.clock import clock
from app.config import get_settings
from app.db import engine
from app.jobs import run_once
from app.models import (
    Addiction,
    AddictionCheck,
    Alert,
    AppointmentStatus,
    AuditLog,
    DailyCheck,
    DoseLog,
    Habit,
    HabitLog,
    Medication,
    Relapse,
    Role,
    User,
)

from .booking_helpers import add_appointment, user_id, verified_patient
from .conftest import advance, bearer
from .test_qa_booking_isolation import (
    EMAIL_A,
    EMAIL_ADMIN,
    EMAIL_B,
    RANDOM_ID,
    _call,
    _forged,
    clinical_keys,
    doctor_a,
    reply,
    staff_headers,
    staff_user,
)

# Clock (conftest): 2026-10-17 18:00 UTC = 19:00 in Algiers, same day both ways.
TODAY = "2026-10-17"
YESTERDAY = "2026-10-16"
CLEAN_SINCE = "2026-10-07T18:00:00Z"
RELAPSE_AT = "2026-10-12T10:00:00Z"  # streak of 5 days after it: milestone 3
PAST_VISIT = datetime(2026, 10, 14, 8, 0)  # Wednesday 09:00 Algiers, completed
MONDAY_9 = datetime(2026, 10, 19, 8, 0)  # Monday 09:00 Algiers, outside the notice
PATIENT_PASSWORD = "sobre2026"  # conftest.register's default
EMAIL_ADMIN_NO_PROFILE = "qa.admin.noprofile@example.invalid"

CHECK_SAVED = {"used": False, "craving": 4, "signals": {"irritability": 3, "restlessness": 5}}
CHECK_OTHER = {"used": True, "craving": 1, "signals": {"irritability": 1, "restlessness": 1}}
MED_NEW = {"name": "QA-DRUG-NEW", "amount": "QA-AMOUNT-NEW", "times": ["09:00"], "start_date": TODAY}
# Words that name the substance profiles, signals or types we use: never in an
# audit row, a log line or another patient's reply.
PROFILE_WORDS = ("nicotine", "thc", "tobacco", "cannabis", "irritability", "restlessness")


# --- the clinic -----------------------------------------------------------------


@dataclass
class Patient:
    tag: str
    phone: str
    session: dict
    id: uuid.UUID
    doctor_id: uuid.UUID
    addiction: str
    habit: str
    medication: str
    alert: str

    @property
    def headers(self) -> dict:
        return bearer(self.session)

    def secrets(self) -> list[str]:
        """Strings only this patient's rows contain: their words, their
        prescription and their phone."""
        t = self.tag
        digits = self.phone.lstrip("0")
        return [f"QA-SUBST-{t}", f"QA-NOTE-{t}", f"QA-HABIT-{t}", f"QA-DRUG-{t}",
                f"QA-AMOUNT-{t}", f"QA-INSTR-{t}", digits, str(self.id), self.addiction,
                self.habit, self.medication]


@dataclass
class World:
    doc_a: uuid.UUID
    doc_b: uuid.UUID
    admin: uuid.UUID
    ha: dict
    hb: dict
    hadmin: dict
    pa: Patient
    pb: Patient


def med_body(tag: str) -> dict:
    return {"name": f"QA-DRUG-{tag}", "amount": f"QA-AMOUNT-{tag}", "times": ["08:00"],
            "start_date": "2026-10-10", "end_date": None, "instructions": f"QA-INSTR-{tag}"}


def enrol(client, sms, tag: str, phone: str, doctor_id: uuid.UUID, doctor_headers: dict,
          status=AppointmentStatus.completed) -> Patient:
    """A patient with one paid visit with [doctor_id] and one of every recovery
    row: an addiction with a relapse and a check, a habit ticked today, a
    prescription with today's dose answered, a daily tick and a reminder."""
    s = verified_patient(client, sms, phone)
    pid = user_id(phone)
    add_appointment(doctor_id, pid, PAST_VISIT, status=status)
    h = bearer(s)
    r = client.post("/v1/me/addictions", headers=h,
                    json={"profile": "nicotine", "substance": f"QA-SUBST-{tag}", "clean_since": CLEAN_SINCE})
    assert r.status_code == 201, r.text
    addiction = r.json()["id"]
    r = client.post(f"/v1/me/addictions/{addiction}/relapses", headers=h,
                    json={"at": RELAPSE_AT, "note": f"QA-NOTE-{tag}"})
    assert r.status_code == 201, r.text
    r = client.put(f"/v1/me/addictions/{addiction}/checks/{TODAY}", json=CHECK_SAVED, headers=h)
    assert r.status_code == 204, r.text
    r = client.post("/v1/me/habits", json={"kind": "custom", "text": f"QA-HABIT-{tag}"}, headers=h)
    assert r.status_code == 201, r.text
    habit = r.json()["id"]
    assert client.put(f"/v1/me/habits/{habit}/days/{TODAY}", headers=h).status_code == 204
    r = client.post(f"/v1/staff/patients/{pid}/medications", json=med_body(tag), headers=doctor_headers)
    assert r.status_code == 201, r.text
    medication = r.json()["id"]
    r = client.put("/v1/me/doses", headers=h,
                   json={"medication_id": medication, "day": TODAY, "time": "08:00", "status": "taken"})
    assert r.status_code == 200, r.text
    assert client.put(f"/v1/me/checkins/{TODAY}", headers=h).status_code == 204
    assert client.put("/v1/me/reminder", json={"time": "21:00"}, headers=h).status_code == 200
    with Session(engine) as db:
        alert = db.scalar(select(Alert.id).where(Alert.patient_id == pid, Alert.type == "relapse"))
    assert alert is not None
    return Patient(tag, phone, s, pid, doctor_id, addiction, habit, medication, str(alert))


def world(client, sms) -> World:
    """Doctor A (the seeded doctor) with patient A, doctor B with patient B,
    and a super admin who holds the Doctor role but has no patient."""
    doc_a = doctor_a().user_id
    doc_b = staff_user(EMAIL_B, Role.doctor)
    admin = staff_user(EMAIL_ADMIN, Role.super_admin)
    ha, hb = staff_headers(client, EMAIL_A), staff_headers(client, EMAIL_B)
    hadmin = staff_headers(client, EMAIL_ADMIN)
    pa = enrol(client, sms, "A", "0661234511", doc_a, ha)
    pb = enrol(client, sms, "B", "0661234512", doc_b, hb)
    return World(doc_a, doc_b, admin, ha, hb, hadmin, pa, pb)


def run_alert_jobs() -> None:
    with Session(engine) as db:
        for job in (missed_dose_alerts, craving_alerts, no_checkin_alerts, milestone_alerts):
            job(db)


def state(pid: uuid.UUID) -> dict:
    """Everything clinical stored for one patient, to show a refused call
    changed nothing."""
    def rows(items):
        return sorted(items, key=repr)

    with Session(engine) as db:
        adds = db.scalars(select(Addiction).where(Addiction.patient_id == pid)).all()
        add_ids = [a.id for a in adds]
        habits = db.scalars(select(Habit).where(Habit.patient_id == pid)).all()
        meds = db.scalars(select(Medication).where(Medication.patient_id == pid)).all()
        return {
            "addictions": rows((a.id, a.type, a.profile, a.substance, a.sobriety_start, a.goal_days,
                                a.milestone_seen, a.review_status, a.reviewed_by, a.reviewed_at,
                                a.active, a.past_days, a.longest_past_days) for a in adds),
            "relapses": rows((r.addiction_id, r.occurred_at, r.note)
                             for r in db.scalars(select(Relapse).where(Relapse.addiction_id.in_(add_ids)))),
            "checks": rows((c.addiction_id, c.day, c.used, c.craving, sorted(c.signals.items()))
                           for c in db.scalars(select(AddictionCheck).where(AddictionCheck.addiction_id.in_(add_ids)))),
            "habits": rows((h.id, h.kind, h.text, h.reminder_time, h.active) for h in habits),
            "habit_days": rows((log.habit_id, log.day) for log in db.scalars(
                select(HabitLog).where(HabitLog.habit_id.in_([h.id for h in habits])))),
            "medications": rows((m.id, m.name, m.amount, tuple(m.times), m.start_date, m.end_date,
                                 m.instructions, m.active, m.prescribed_by) for m in meds),
            "doses": rows((d.medication_id, d.day, d.time, d.status) for d in db.scalars(
                select(DoseLog).where(DoseLog.medication_id.in_([m.id for m in meds])))),
            "alerts": rows((al.id, al.doctor_id, al.type, al.read)
                           for al in db.scalars(select(Alert).where(Alert.patient_id == pid))),
            "daily": rows(db.scalars(select(DailyCheck.day).where(DailyCheck.patient_id == pid))),
            "reminder": db.get(User, pid).reminder_time,
        }


def fill(template: str, patient: Patient | None = None, **ids) -> str:
    """A route path with this patient's ids, or the ones given."""
    values = {}
    if patient is not None:
        p = patient
        values = {"p": p.id, "a": p.addiction, "h": p.habit, "m": p.medication, "al": p.alert}
    values |= ids
    values.setdefault("day", TODAY)
    return template.format(**values)


def fill_body(body, p: Patient | None = None, **ids):
    if body is None or "{m}" not in str(body):
        return body
    m = ids.get("m", p.medication if p else RANDOM_ID)
    return {k: (m if v == "{m}" else v) for k, v in body.items()}


# Every staff route that reads or changes one patient's clinical data, in an
# order that keeps the data in place for the owner's own run (reads first).
STAFF_CLINICAL = [
    ("get", "/v1/staff/patients/{p}/addictions", None),
    ("get", "/v1/staff/patients/{p}/addictions/{a}/checks", None),
    ("get", "/v1/staff/patients/{p}/addictions/{a}/checks?days=90", None),
    ("get", "/v1/staff/patients/{p}/habits", None),
    ("get", "/v1/staff/patients/{p}/medications", None),
    ("post", "/v1/staff/patients/{p}/addictions/{a}/confirm", None),
    ("post", "/v1/staff/patients/{p}/addictions/{a}/reject", None),
    ("put", "/v1/staff/patients/{p}/addictions/{a}/profile", {"profile": "thc"}),
    ("post", "/v1/staff/patients/{p}/medications", MED_NEW),
    ("delete", "/v1/staff/patients/{p}/medications/{m}", None),
]
STAFF_READS = [r for r in STAFF_CLINICAL if r[0] == "get"]
STAFF_OTHER = [
    ("get", "/v1/staff/alerts", None),
    ("get", "/v1/staff/alerts?unread=true", None),
    ("post", "/v1/staff/alerts/{al}/read", None),
    ("get", "/v1/staff/recovery/profiles", None),
    ("get", "/v1/staff/patients", None),
]

# Every patient route that takes the id of one of the patient's rows, in an
# order that keeps the rows usable for the owner's own run.
PATIENT_BY_ID = [
    ("put", "/v1/me/addictions/{a}/checks/{day}", CHECK_OTHER),
    ("put", "/v1/me/addictions/{a}/checks/2026-01-01", CHECK_OTHER),
    ("put", "/v1/me/addictions/{a}/goal", {"days": 14}),
    ("post", "/v1/me/addictions/{a}/milestone/seen", None),
    ("post", "/v1/me/addictions/{a}/relapses", {"note": "QA-NOTE-X"}),
    ("put", "/v1/me/habits/{h}/reminder", {"time": "09:00"}),
    ("put", "/v1/me/habits/{h}/days/" + YESTERDAY, None),
    ("delete", "/v1/me/habits/{h}/days/{day}", None),
    ("put", "/v1/me/doses", {"medication_id": "{m}", "day": TODAY, "time": "08:00", "status": "skipped"}),
    ("delete", "/v1/me/habits/{h}", None),
]
PATIENT_LISTS = [
    ("get", "/v1/me/addictions", None),
    ("post", "/v1/me/addictions", {"type": "other", "clean_since": CLEAN_SINCE}),
    ("get", "/v1/me/addiction-checks?since=2020-01-01", None),
    ("get", "/v1/me/recovery/profiles", None),
    ("get", "/v1/me/checkins?since=2020-01-01", None),
    ("put", f"/v1/me/checkins/{YESTERDAY}", None),
    ("get", "/v1/me/reminder", None),
    ("put", "/v1/me/reminder", {"time": "07:00"}),
    ("get", "/v1/me/habits", None),
    ("get", "/v1/me/habits/catalog", None),
    ("post", "/v1/me/habits", {"kind": "water"}),
    ("get", f"/v1/me/doses?day={TODAY}", None),
    ("get", "/v1/me/quote", None),
]


def no_secrets(text: str, p: Patient) -> list[str]:
    return [s for s in p.secrets() if s in text]


def clinical_secrets(p: Patient) -> list[str]:
    """What only this patient's clinical rows contain. Not their phone or id:
    the clinic-wide agenda may show those (PRD 3)."""
    t = p.tag
    return [f"QA-SUBST-{t}", f"QA-NOTE-{t}", f"QA-HABIT-{t}", f"QA-DRUG-{t}", f"QA-AMOUNT-{t}",
            f"QA-INSTR-{t}", p.addiction, p.habit, p.medication, p.alert]


# --- R-82: patient A on patient B's ids ------------------------------------------------


def test_another_patients_ids_answer_like_random_ids_and_change_nothing(client, sms):
    w = world(client, sms)
    a, b = w.pa, w.pb
    before = state(b.id)
    for method, path, body in PATIENT_BY_ID:
        theirs = _call(client, method, fill(path, b), fill_body(body, b), a.headers)
        random = _call(client, method, fill(path, a=RANDOM_ID, h=RANDOM_ID), fill_body(body, m=RANDOM_ID), a.headers)
        assert theirs.status_code == 404, (path, theirs.text)
        assert reply(theirs) == reply(random), path
    assert state(b.id) == before
    # The same calls by B on B's rows go through: the refusal was ownership,
    # not a bad body.
    for method, path, body in PATIENT_BY_ID:
        if "2026-01-01" in path:
            continue
        r = _call(client, method, fill(path, b), fill_body(body, b), b.headers)
        assert r.status_code < 300, (path, r.text)


def test_a_locked_patient_gets_the_same_lock_on_anothers_ids_as_on_random_ids(client, sms):
    """Patient C only holds an unpaid slot: every id route answers the lock,
    the same for B's ids and random ones, so the lock is no existence oracle
    and the hold opens nothing (R-02)."""
    w = world(client, sms)
    c = verified_patient(client, sms, "0661234513")
    add_appointment(w.doc_b, user_id("0661234513"), MONDAY_9 + timedelta(hours=1),
                    status=AppointmentStatus.awaiting_payment,
                    hold_expires_at=clock.now() + timedelta(minutes=10), method=None)
    before = state(w.pb.id)
    for method, path, body in PATIENT_BY_ID:
        theirs = _call(client, method, fill(path, w.pb), fill_body(body, w.pb), bearer(c))
        random = _call(client, method, fill(path, a=RANDOM_ID, h=RANDOM_ID), fill_body(body, m=RANDOM_ID), bearer(c))
        assert reply(theirs) == reply(random) == (403, {"detail": {"code": "recovery_locked"}}), path
    assert state(w.pb.id) == before


def test_patient_lists_carry_only_their_own_rows(client, sms):
    w = world(client, sms)
    a, b = w.pa, w.pb
    blob = ""
    for path in ("/v1/me", "/v1/me/addictions", "/v1/me/addiction-checks?since=2020-01-01",
                 "/v1/me/checkins?since=2020-01-01", "/v1/me/habits", f"/v1/me/doses?day={TODAY}",
                 f"/v1/me/doses?day={YESTERDAY}", "/v1/me/quote", "/v1/me/reminder"):
        r = client.get(path, headers=a.headers)
        assert r.status_code == 200, (path, r.text)
        blob += r.text
    assert no_secrets(blob, b) == []
    # Naming the other patient (or their row) in the query changes nothing.
    smuggled = f"patient_id={b.id}&user_id={b.id}&addiction_id={b.addiction}&medication_id={b.medication}"
    for path in ("/v1/me/addictions", "/v1/me/addiction-checks?since=2020-01-01", "/v1/me/checkins",
                 "/v1/me/habits", f"/v1/me/doses?day={TODAY}", "/v1/me/reminder"):
        r = client.get(path + ("&" if "?" in path else "?") + smuggled, headers=a.headers)
        assert r.status_code == 200, (path, r.text)
        assert [s for s in b.secrets() if s in r.text and s not in smuggled] == [], path
        assert r.json() == client.get(path, headers=a.headers).json(), path
    assert [x["id"] for x in client.get("/v1/me/addictions", headers=a.headers).json()] == [a.addiction]
    checks = client.get("/v1/me/addiction-checks?since=2020-01-01", headers=a.headers).json()["checks"]
    assert {c["addiction_id"] for c in checks} == {a.addiction}
    assert [h["id"] for h in client.get("/v1/me/habits", headers=a.headers).json()] == [a.habit]
    doses = client.get(f"/v1/me/doses?day={TODAY}", headers=a.headers).json()
    assert {d["medication_id"] for d in doses} == {a.medication}


# --- R-68 / R-19 / R-20 / R-15: what the patient cannot change -----------------------


def test_patient_has_no_route_to_change_medications_reviews_or_history(client, sms):
    w = world(client, sms)
    a = w.pa
    before = state(a.id)
    no_route = [
        ("put", "/v1/me/addictions/{a}", {"clean_since": "2020-01-01T00:00:00Z"}),
        ("patch", "/v1/me/addictions/{a}", {"clean_since": "2020-01-01T00:00:00Z"}),
        ("delete", "/v1/me/addictions/{a}", None),
        ("get", "/v1/me/addictions/{a}/relapses", None),
        ("put", "/v1/me/addictions/{a}/relapses", {"note": "x"}),
        ("delete", "/v1/me/addictions/{a}/relapses", None),
        ("put", "/v1/me/addictions/{a}/profile", {"profile": "thc"}),
        ("post", "/v1/me/addictions/{a}/confirm", None),
        ("put", "/v1/me/addictions/{a}/review", {"review_status": "confirmed"}),
        ("delete", "/v1/me/addictions/{a}/checks/{day}", None),
        ("get", "/v1/me/medications", None),
        ("post", "/v1/me/medications", MED_NEW),
        ("put", "/v1/me/medications/{m}", MED_NEW),
        ("delete", "/v1/me/medications/{m}", None),
        ("delete", "/v1/me/doses", None),
        ("delete", "/v1/me/checkins/{day}", None),
    ]
    for method, path, body in no_route:
        r = _call(client, method, fill(path, a), body, a.headers)
        assert r.status_code in (404, 405), (method, path, r.status_code)
    # The staff writes refuse the patient, even on their own file.
    for method, path, body in STAFF_CLINICAL:
        r = _call(client, method, fill(path, a), body, a.headers)
        assert reply(r) == (403, {"detail": {"code": "forbidden"}}), path
    assert state(a.id) == before


def test_extra_fields_cannot_set_review_or_medication_fields(client, sms):
    w = world(client, sms)
    a = w.pa
    base = f"/v1/staff/patients/{a.id}/addictions/{a.addiction}"
    assert client.post(f"{base}/confirm", headers=w.ha).status_code == 200
    assert client.put(f"{base}/profile", json={"profile": "thc"}, headers=w.ha).status_code == 200
    reviewed = state(a.id)["addictions"]
    # A new addiction with review fields of its own stays pending and is the caller's.
    r = client.post("/v1/me/addictions", headers=a.headers, json={
        "type": "other", "clean_since": CLEAN_SINCE, "review_status": "confirmed",
        "reviewed_by": str(w.doc_a), "reviewed_at": "2026-10-17T10:00:00Z", "patient_id": str(w.pb.id),
        "longest_past_days": 900, "past_days": 900, "milestone_seen": 365})
    assert r.status_code == 201, r.text
    assert (r.json()["review_status"], r.json()["longest_past_days"], r.json()["past_days"]) == ("pending", 0, 0)
    with Session(engine) as db:
        new = db.get(Addiction, uuid.UUID(r.json()["id"]))
        assert (new.patient_id, new.reviewed_by, new.reviewed_at, new.milestone_seen) == (a.id, None, None, 0)
    # The goal and relapse bodies cannot carry the doctor's fields or move the start back.
    r = client.put(f"/v1/me/addictions/{a.addiction}/goal", headers=a.headers, json={
        "days": 14, "review_status": "rejected", "profile": "nicotine", "type": "other",
        "clean_since": "2020-01-01T00:00:00Z", "reviewed_by": str(w.doc_b)})
    assert r.status_code == 200, r.text
    after = [row for row in state(a.id)["addictions"] if str(row[0]) == a.addiction][0]
    original = [row for row in reviewed if str(row[0]) == a.addiction][0]
    assert after[:5] + after[6:] == original[:5] + original[6:]  # only goal_days moved
    assert after[5] == 14
    # A dose answer cannot rewrite the prescription.
    meds = state(a.id)["medications"]
    r = client.put("/v1/me/doses", headers=a.headers, json={
        "medication_id": a.medication, "day": TODAY, "time": "08:00", "status": "skipped",
        "name": "QA-CHANGED", "amount": "QA-CHANGED", "times": ["09:00"], "active": False,
        "end_date": TODAY, "prescribed_by": str(w.doc_b)})
    assert r.status_code == 200, r.text
    assert state(a.id)["medications"] == meds
    # A check, a habit or a tick naming patient B's rows lands on A's own rows only.
    before_b = state(w.pb.id)
    # (The doctor set the THC profile above, so its two signals.)
    r = client.put(f"/v1/me/addictions/{a.addiction}/checks/{YESTERDAY}", headers=a.headers, json={
        "used": False, "craving": 2, "signals": {"sleep": 2, "irritability": 2},
        "addiction_id": w.pb.addiction, "patient_id": str(w.pb.id), "day": TODAY})
    assert r.status_code == 204, r.text
    r = client.post("/v1/me/habits", headers=a.headers, json={"kind": "water", "patient_id": str(w.pb.id),
                                                               "id": w.pb.habit, "active": True})
    assert r.status_code == 201 and r.json()["id"] != w.pb.habit, r.text
    with Session(engine) as db:
        assert db.get(Habit, uuid.UUID(r.json()["id"])).patient_id == a.id
    r = client.put(f"/v1/me/checkins/{YESTERDAY}", headers=a.headers, json={"patient_id": str(w.pb.id)})
    assert r.status_code == 204, r.text
    assert state(w.pb.id) == before_b
    assert YESTERDAY in {c["day"] for c in client.get("/v1/me/addiction-checks?since=2020-01-01",
                                                      headers=a.headers).json()["checks"]}


# --- R-83 / R-86 / R-88 / R-02: doctors without a paid visit ---------------------------


def _foreign_actor(client, w: World, actor: str) -> dict:
    victim = w.pb
    if actor == "other_doctor":
        return w.ha
    if actor == "super_admin":
        return w.hadmin
    if actor == "hold_only":
        add_appointment(w.doc_a, victim.id, MONDAY_9, status=AppointmentStatus.awaiting_payment,
                        hold_expires_at=clock.now() + timedelta(minutes=10), method=None)
        return w.ha
    if actor == "expired_hold":
        add_appointment(w.doc_a, victim.id, MONDAY_9, status=AppointmentStatus.awaiting_payment,
                        hold_expires_at=clock.now() - timedelta(minutes=1), method=None)
        return w.ha
    raise AssertionError(actor)


@pytest.mark.parametrize("actor", ["other_doctor", "super_admin", "hold_only", "expired_hold"])
def test_doctor_without_a_paid_visit_reaches_none_of_the_patients_clinical_data(client, sms, actor):
    """Patient B belongs to doctor B. Doctor A (also with an unpaid hold, live
    or expired) and the super admin get, on every clinical route, exactly the
    answer a random patient id gets, see nothing of B and change nothing."""
    w = world(client, sms)
    victim = w.pb
    h = _foreign_actor(client, w, actor)
    before = state(victim.id)
    for method, path, body in STAFF_CLINICAL:
        theirs = _call(client, method, fill(path, victim), body, h)
        random = _call(client, method, fill(path, victim, p=RANDOM_ID), body, h)
        assert theirs.status_code == 404, (path, theirs.text)
        assert reply(theirs) == reply(random), path
    read = client.post(f"/v1/staff/alerts/{victim.alert}/read", headers=h)
    assert reply(read) == reply(client.post(f"/v1/staff/alerts/{RANDOM_ID}/read", headers=h))
    assert read.status_code == 404
    listed = ""
    for path in ("/v1/staff/alerts", "/v1/staff/alerts?unread=true", "/v1/staff/patients"):
        r = client.get(path, headers=h)
        assert r.status_code == 200
        listed += r.text
    assert no_secrets(listed, victim) == []
    assert state(victim.id) == before
    # The patient's new events still reach their own doctor only (the hold
    # does not make doctor A the recipient).
    assert client.post(f"/v1/me/addictions/{victim.addiction}/relapses", json={}, headers=victim.headers).status_code == 201
    run_alert_jobs()
    with Session(engine) as db:
        doctors = set(db.scalars(select(Alert.doctor_id).where(Alert.patient_id == victim.id)))
    assert doctors == {w.doc_b}


def test_own_patient_path_with_another_patients_row_ids_looks_unknown(client, sms):
    w = world(client, sms)
    own, victim = w.pa, w.pb
    before_own, before_victim = state(own.id), state(victim.id)
    for method, path, body in STAFF_CLINICAL:
        if "{a}" not in path and "{m}" not in path:
            continue
        theirs = _call(client, method, fill(path, own, a=victim.addiction, m=victim.medication), body, w.ha)
        random = _call(client, method, fill(path, own, a=RANDOM_ID, m=RANDOM_ID), body, w.ha)
        assert theirs.status_code == 404, (path, theirs.text)
        assert reply(theirs) == reply(random), path
    assert state(victim.id) == before_victim
    assert state(own.id) == before_own


def test_the_patients_own_doctor_reaches_every_route(client, sms):
    """Sanity for the refusals above: the same calls by doctor B on B's
    patient succeed, so a 404 elsewhere is about ownership, not the body."""
    w = world(client, sms)
    for method, path, body in STAFF_CLINICAL:
        r = _call(client, method, fill(path, w.pb), body, w.hb)
        assert r.status_code < 300, (path, r.text)
    r = client.post(f"/v1/staff/alerts/{w.pb.alert}/read", headers=w.hb)
    assert r.status_code == 200 and r.json()["read"] is True


def test_screens_outside_the_patient_file_carry_no_clinical_content(client, sms):
    """The clinic-wide agenda, the patient list, the sign-ups queue and the
    alerts, for the super admin and for doctor A: nothing of patient B's
    clinical rows and no clinical field (B's visit itself may show: agendas
    are shared clinic-wide, PRD 3). Doctor A's own patient file carries
    nothing of B's either."""
    w = world(client, sms)
    run_alert_jobs()
    screens = ("/v1/staff/agenda", "/v1/staff/agenda?day=2026-10-14", "/v1/staff/agenda?day=2026-10-19",
               "/v1/staff/patients", "/v1/staff/signups", "/v1/staff/alerts", "/v1/staff/alerts?unread=true")
    for h in (w.hadmin, w.ha):
        for path in screens:
            r = client.get(path, headers=h)
            assert r.status_code == 200, (path, r.text)
            assert [s for s in clinical_secrets(w.pb) if s in r.text] == [], path
            assert clinical_keys(r.json()) == [], path
    agenda = client.get("/v1/staff/agenda?day=2026-10-14", headers=w.hadmin).json()
    assert {str(w.pa.id), str(w.pb.id)} <= {x["patient_id"] for x in agenda}  # the sweep saw B's visit
    for method, path, body in STAFF_READS:
        r = _call(client, method, fill(path, w.pa), body, w.ha)
        assert r.status_code == 200, (path, r.text)
        assert no_secrets(r.text, w.pb) == [], path


def test_staff_write_bodies_cannot_move_rows_to_another_patient_or_doctor(client, sms):
    """Extra fields in a doctor's write (patient, prescriber, reviewer, row id,
    counters) are ignored: the row stays the path's patient's and the caller's."""
    w = world(client, sms)
    a, b = w.pa, w.pb
    before_b = state(b.id)
    base = f"/v1/staff/patients/{a.id}"
    r = client.post(f"{base}/medications", headers=w.ha, json=MED_NEW | {
        "id": b.medication, "patient_id": str(b.id), "prescribed_by": str(w.doc_b), "active": False})
    assert r.status_code == 201, r.text
    assert r.json()["id"] != b.medication
    with Session(engine) as db:
        m = db.get(Medication, uuid.UUID(r.json()["id"]))
        assert (m.patient_id, m.prescribed_by, m.active) == (a.id, w.doc_a, True)
    with Session(engine) as db:
        row = db.get(Addiction, uuid.UUID(a.addiction))
        kept = (row.patient_id, row.substance, row.sobriety_start, row.past_days, row.longest_past_days)
    r = client.post(f"{base}/addictions/{a.addiction}/confirm", headers=w.ha, json={
        "reviewed_by": str(w.doc_b), "review_status": "rejected", "patient_id": str(b.id)})
    assert r.status_code == 200 and r.json()["review_status"] == "confirmed", r.text
    r = client.put(f"{base}/addictions/{a.addiction}/profile", headers=w.ha, json={
        "profile": "thc", "patient_id": str(b.id), "clean_since": "2020-01-01T00:00:00Z",
        "sobriety_start": "2020-01-01T00:00:00Z", "substance": "QA-CHANGED", "review_status": "rejected",
        "reviewed_by": str(w.doc_b), "past_days": 900, "longest_past_days": 900})
    assert r.status_code == 200, r.text
    with Session(engine) as db:
        row = db.get(Addiction, uuid.UUID(a.addiction))
        assert (row.patient_id, row.substance, row.sobriety_start, row.past_days, row.longest_past_days) == kept
        assert (row.reviewed_by, row.review_status.value, row.profile.value) == (w.doc_a, "confirmed", "thc")
    assert state(b.id) == before_b


def test_super_admin_without_a_doctor_profile_is_refused_everywhere(client, sms):
    w = world(client, sms)
    staff_user(EMAIL_ADMIN_NO_PROFILE, Role.super_admin, with_profile=False)
    h = staff_headers(client, EMAIL_ADMIN_NO_PROFILE)
    before = state(w.pa.id)
    for method, path, body in STAFF_CLINICAL + STAFF_OTHER:
        r = _call(client, method, fill(path, w.pa), body, h)
        assert reply(r) == (403, {"detail": {"code": "forbidden"}}), path
    assert state(w.pa.id) == before


# --- R-87 / R-96 / R-100: alerts ----------------------------------------------------------


def test_each_doctor_lists_and_marks_only_their_own_patients_alerts(client, sms):
    w = world(client, sms)
    run_alert_jobs()
    for h, own, other in ((w.ha, w.pa, w.pb), (w.hb, w.pb, w.pa)):
        for path in ("/v1/staff/alerts", "/v1/staff/alerts?unread=true"):
            r = client.get(path, headers=h)
            assert r.status_code == 200
            assert {x["patient_id"] for x in r.json()} == {str(own.id)}, path
            assert {x["type"] for x in r.json()} >= {"relapse", "missed_doses", "milestone"}
            assert no_secrets(r.text, other) == []
            for x in r.json():
                assert set(x) == {"id", "patient_id", "patient_phone", "type", "priority", "read", "created_at"}
            # Alerts carry no medical content of the doctor's own patient either.
            assert [s for s in own.secrets()[:6] if s in r.text] == []
    assert client.get("/v1/staff/alerts", headers=w.hadmin).json() == []
    with Session(engine) as db:
        for p in (w.pa, w.pb):
            assert set(db.scalars(select(Alert.doctor_id).where(Alert.patient_id == p.id))) == {p.doctor_id}
    # Doctor A and the super admin cannot mark doctor B's alert read.
    for h in (w.ha, w.hadmin):
        theirs = client.post(f"/v1/staff/alerts/{w.pb.alert}/read", headers=h)
        assert theirs.status_code == 404
        assert reply(theirs) == reply(client.post(f"/v1/staff/alerts/{RANDOM_ID}/read", headers=h))
    with Session(engine) as db:
        assert db.get(Alert, uuid.UUID(w.pb.alert)).read is False
    assert client.post(f"/v1/staff/alerts/{w.pb.alert}/read", headers=w.hb).json()["read"] is True


# --- R-90 / R-06 / R-91: tokens and roles -------------------------------------------------


def _every_route(w: World):
    for method, path, body in STAFF_CLINICAL + STAFF_OTHER:
        yield method, fill(path, w.pa), body
    for method, path, body in PATIENT_BY_ID:
        yield method, fill(path, w.pa), fill_body(body, w.pa)
    for method, path, body in PATIENT_LISTS:
        yield method, path, body


@pytest.mark.parametrize("token", ["none", "garbage", "forged", "refresh", "expired", "deleted"])
def test_missing_bad_or_dead_token_is_401_on_every_recovery_route(client, sms, token):
    w = world(client, sms)
    if token == "deleted":
        r = client.request("DELETE", "/v1/me", json={"password": PATIENT_PASSWORD}, headers=w.pa.headers)
        assert r.status_code == 204, r.text
    before = state(w.pa.id), state(w.pb.id)
    if token == "expired":
        advance(minutes=get_settings().access_token_minutes + 1)
    headers = {
        "none": {},
        "garbage": {"Authorization": "Bearer not.a.jwt"},
        "forged": {"Authorization": f"Bearer {_forged()}"},
        "refresh": {"Authorization": f"Bearer {w.pa.session['refresh_token']}"},
        "expired": w.pa.headers,
        "deleted": w.pa.headers,
    }[token]
    for method, path, body in _every_route(w):
        r = _call(client, method, path, body, headers)
        assert r.status_code == 401, (method, path, r.text)
        assert r.json()["detail"]["code"] in ("not_authenticated", "token_invalid"), path
    if token == "expired":
        for method, path, body in STAFF_CLINICAL[:1]:
            assert _call(client, method, fill(path, w.pa), body, w.ha).status_code == 401
    assert (state(w.pa.id), state(w.pb.id)) == before


def test_patient_token_is_refused_on_every_staff_recovery_route(client, sms):
    w = world(client, sms)
    before = state(w.pa.id), state(w.pb.id)
    for victim in (w.pa, w.pb):  # their own file too
        for method, path, body in STAFF_CLINICAL + STAFF_OTHER:
            r = _call(client, method, fill(path, victim), body, w.pa.headers)
            assert reply(r) == (403, {"detail": {"code": "forbidden"}}), path
    assert (state(w.pa.id), state(w.pb.id)) == before


def test_doctor_and_super_admin_tokens_are_refused_on_patient_recovery_routes(client, sms):
    w = world(client, sms)
    before = state(w.pa.id)
    for h in (w.ha, w.hadmin):
        for method, path, body in list(_every_route(w))[len(STAFF_CLINICAL + STAFF_OTHER):]:
            r = _call(client, method, path, body, h)
            assert reply(r) == (403, {"detail": {"code": "forbidden"}}), path
    assert state(w.pa.id) == before


def test_a_deleted_patients_file_looks_unknown_to_their_doctor(client, sms):
    w = world(client, sms)
    r = client.request("DELETE", "/v1/me", json={"password": PATIENT_PASSWORD}, headers=w.pa.headers)
    assert r.status_code == 204
    for method, path, body in STAFF_CLINICAL:
        theirs = _call(client, method, fill(path, w.pa), body, w.ha)
        random = _call(client, method, fill(path, w.pa, p=RANDOM_ID), body, w.ha)
        assert theirs.status_code == 404, (path, theirs.text)
        assert reply(theirs) == reply(random), path
    assert str(w.pa.id) not in client.get("/v1/staff/patients", headers=w.ha).text


# --- R-94 / R-95: audit rows and logs --------------------------------------------------------

RECOVERY_ACTIONS = {"addiction.added", "relapse.logged", "addiction.confirmed", "addiction.rejected",
                    "addiction.profile_set", "medication.prescribed", "medication.stopped",
                    "habit.added", "habit.removed"}


def _doctor_and_patient_actions(client, w: World) -> None:
    for p, h in ((w.pa, w.ha), (w.pb, w.hb)):
        base = f"/v1/staff/patients/{p.id}"
        assert client.post(f"{base}/addictions/{p.addiction}/confirm", headers=h).status_code == 200
        assert client.post(f"{base}/addictions/{p.addiction}/reject", headers=h).status_code == 200
        assert client.put(f"{base}/addictions/{p.addiction}/profile", json={"profile": "thc"}, headers=h).status_code == 200
        for path in ("/addictions", f"/addictions/{p.addiction}/checks", "/habits", "/medications"):
            assert client.get(base + path, headers=h).status_code == 200
        assert client.delete(f"{base}/medications/{p.medication}", headers=h).status_code == 204
        assert client.delete(f"/v1/me/habits/{p.habit}", headers=p.headers).status_code == 204


def test_recovery_audit_rows_carry_row_ids_only(client, sms):
    w = world(client, sms)
    _doctor_and_patient_actions(client, w)
    with Session(engine) as db:
        lines = db.scalars(select(AuditLog)).all()
    row_ids = {p.addiction for p in (w.pa, w.pb)} | {p.habit for p in (w.pa, w.pb)} | {
        p.medication for p in (w.pa, w.pb)}
    seen = set()
    for line in lines:
        if line.action in RECOVERY_ACTIONS:
            seen.add(line.action)
            assert line.target in row_ids, (line.action, line.target)
        text = f"{line.action} {line.target} {line.ip}"
        for p in (w.pa, w.pb):
            assert [s for s in p.secrets()[:6] if s in text] == [], line.action
        assert [word for word in PROFILE_WORDS if word in text.lower()] == [], line.action
    assert seen == RECOVERY_ACTIONS


def test_no_recovery_content_reaches_the_logs(client, sms, caplog):
    # Production logs at INFO (app/main.py basicConfig).
    caplog.set_level(logging.INFO)
    w = world(client, sms)
    _doctor_and_patient_actions(client, w)
    with Session(engine) as db:
        run_once(db)
    text = "\n".join(r.getMessage() + (str(r.exc_info[1]) if r.exc_info else "") for r in caplog.records)
    for p in (w.pa, w.pb):
        assert [s for s in p.secrets()[:6] if s in text] == []
    assert [word for word in PROFILE_WORDS if word in text.lower()] == []
    assert '"craving"' not in text and "irritab" not in text


@pytest.mark.xfail(strict=True, reason="QA SEC-06: a doctor reading a patient's clinical data writes no audit row; PRD 8.3 audits who viewed patient data")
def test_a_doctor_reading_clinical_data_is_audited(client, sms):
    w = world(client, sms)
    with Session(engine) as db:
        before = db.query(AuditLog).filter(AuditLog.actor_id == w.doc_a).count()
    for method, path, body in STAFF_READS:
        assert _call(client, method, fill(path, w.pa), body, w.ha).status_code == 200
    with Session(engine) as db:
        after = db.query(AuditLog).filter(AuditLog.actor_id == w.doc_a).count()
    assert after - before >= len(STAFF_READS)


# --- R-54: two first saves of one check at the same time ------------------------------------


@pytest.mark.xfail(strict=True, raises=IntegrityError,
                   reason="QA SEC-07: a second simultaneous first save of one check is an unhandled IntegrityError (500) whose text, logged by the server, carries the answers")
def test_a_second_simultaneous_first_save_of_a_check_is_not_a_500(client, sms, monkeypatch):
    """Two phones (or a double tap) save the first check of one addiction and
    day at the same moment. Deterministic on any database: the other save
    commits right after this request read "no check yet". The real race is
    the PostgreSQL-only test below (about 10 of 12 pairs collided per run)."""
    w = world(client, sms)
    a = w.pa
    day = date(2026, 10, 16)
    original = Session.scalar
    fired = []

    def scalar(self, statement, *args, **kwargs):
        descriptions = getattr(statement, "column_descriptions", None) or [{}]
        if descriptions[0].get("entity") is AddictionCheck and not fired:
            fired.append(True)
            with Session(engine) as other:
                other.add(AddictionCheck(addiction_id=uuid.UUID(a.addiction), day=day, used=False,
                                         craving=2, signals={"irritability": 2, "restlessness": 2},
                                         created_at=clock.now()))
                other.commit()
            return None  # what this request read before the other save landed
        return original(self, statement, *args, **kwargs)

    monkeypatch.setattr(Session, "scalar", scalar)
    r = client.put(f"/v1/me/addictions/{a.addiction}/checks/{YESTERDAY}", json=CHECK_OTHER, headers=a.headers)
    assert fired
    assert r.status_code in (204, 409), r.text


@pytest.mark.skipif(engine.dialect.name != "postgresql", reason="needs PostgreSQL: two requests really in parallel")
@pytest.mark.xfail(strict=True, raises=IntegrityError,
                   reason="QA SEC-07: two real simultaneous first saves of one check end in an unhandled IntegrityError (500)")
def test_two_real_simultaneous_first_saves_of_a_check_are_not_a_500(client, sms):
    """The same race as above without any injection: two threads send the
    first save of one addiction and day at the same moment, on every free
    (addiction, day) pair of the window."""
    w = world(client, sms)
    a = w.pa
    addictions = [a.addiction]
    for _ in range(3):
        r = client.post("/v1/me/addictions", headers=a.headers, json={"profile": "nicotine", "clean_since": CLEAN_SINCE})
        assert r.status_code == 201, r.text
        addictions.append(r.json()["id"])
    pairs = [(x, d) for x in addictions for d in ("2026-10-15", YESTERDAY, "2026-10-18")]

    def save(addiction: str, day: str):
        try:
            return client.put(f"/v1/me/addictions/{addiction}/checks/{day}", json=CHECK_OTHER, headers=a.headers).status_code
        except IntegrityError as e:
            return e

    outcomes = []
    for addiction, day in pairs:
        gate = Barrier(2)

        def run(_):
            gate.wait()
            return save(addiction, day)

        with ThreadPoolExecutor(max_workers=2) as pool:
            outcomes += list(pool.map(run, range(2)))
    errors = [o for o in outcomes if isinstance(o, Exception)]
    if errors:
        raise errors[0]
    assert set(outcomes) <= {204, 409}, outcomes


# --- SEC-02 (known, carried): every doctor with a non-hold booking is "own" -------------


def _second_doctor_booking(w: World, status, start=MONDAY_9) -> None:
    add_appointment(w.doc_b, w.pa.id, start, status=status)


@pytest.mark.xfail(strict=True, reason="QA SEC-02: two doctors with a paid booking both read the patient's recovery data (checks, habits, goals, medications)")
def test_sec02_two_paid_doctors_do_not_both_read_recovery_data(client, sms):
    w = world(client, sms)
    _second_doctor_booking(w, AppointmentStatus.confirmed)
    readers = 0
    for h in (w.ha, w.hb):
        readers += any(_call(client, m, fill(p, w.pa), b, h).status_code == 200 for m, p, b in STAFF_READS)
    assert readers <= 1


@pytest.mark.xfail(strict=True, reason="QA SEC-02: a second doctor with a paid booking can stop the prescriber's medicine")
def test_sec02_second_doctor_cannot_stop_another_doctors_prescription(client, sms):
    w = world(client, sms)
    _second_doctor_booking(w, AppointmentStatus.confirmed)
    r = client.delete(f"/v1/staff/patients/{w.pa.id}/medications/{w.pa.medication}", headers=w.hb)
    assert r.status_code in (403, 404)


@pytest.mark.xfail(strict=True, reason="QA SEC-02: a doctor whose only appointment with the patient was cancelled reads the patient's recovery data")
def test_sec02_a_cancelled_booking_opens_no_clinical_data(client, sms):
    w = world(client, sms)
    _second_doctor_booking(w, AppointmentStatus.cancelled)
    for method, path, body in STAFF_READS:
        r = _call(client, method, fill(path, w.pa), body, w.hb)
        assert r.status_code == 404, path


@pytest.mark.xfail(strict=True, reason="QA SEC-02: a relapse alert goes to the doctor of the latest-starting booking (a cancelled one, or a future one the patient has not had yet), not to the doctor who saw the patient and prescribes")
@pytest.mark.parametrize("status", [AppointmentStatus.cancelled, AppointmentStatus.confirmed])
def test_sec02_a_relapse_alert_stays_with_the_patients_doctor(client, sms, status):
    w = world(client, sms)
    _second_doctor_booking(w, status)
    assert client.post(f"/v1/me/addictions/{w.pa.addiction}/relapses", json={}, headers=w.pa.headers).status_code == 201
    run_alert_jobs()
    with Session(engine) as db:
        recipients = db.scalars(select(Alert.doctor_id).where(Alert.patient_id == w.pa.id)).all()
    # The setup relapse went to doctor A; the new relapse and the nightly
    # alerts must too: doctor B never had a visit with this patient.
    assert w.doc_b not in recipients
