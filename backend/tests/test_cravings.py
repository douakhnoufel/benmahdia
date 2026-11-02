"""Difficult moments: the craving log behind the urge-surfing screen."""

import uuid
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import engine
from app.models import AuditLog, CravingLog

from .conftest import bearer
from .test_medications import unlocked
from .test_staff import login, other_doctor
from .test_substance_tracking import setup


def start(client, s, **over):
    body = {"intensity_before": 8, "halt": ["tired", "lonely"]} | over
    return client.post("/v1/me/cravings", json=body, headers=bearer(s))


def passed(client, s, craving, after=3):
    return client.post(
        f"/v1/me/cravings/{craving['id']}/passed",
        json={"intensity_after": after},
        headers=bearer(s),
    )


def mine(client, s, **params):
    return client.get("/v1/me/cravings", params=params, headers=bearer(s))


def test_start_then_passed_keeps_before_and_after(client, sms):
    _, s = setup(client, sms)
    r = start(client, s)
    assert r.status_code == 201
    c = r.json()
    assert c["intensity_before"] == 8 and c["intensity_after"] is None
    assert c["halt"] == ["tired", "lonely"] and c["passed_at"] is None
    r = passed(client, s, c, 3)
    assert r.status_code == 200
    body = r.json()
    assert body["intensity_before"] == 8 and body["intensity_after"] == 3
    assert body["passed_at"] is not None
    assert mine(client, s).json() == [body]


def test_halt_is_optional_and_deduplicated(client, sms):
    _, s = setup(client, sms)
    assert start(client, s, halt=[]).json()["halt"] == []
    assert start(client, s, halt=["tired", "tired", "hungry"]).json()["halt"] == ["tired", "hungry"]


def test_intensity_must_be_1_to_10(client, sms):
    _, s = setup(client, sms)
    for bad in (0, 11, -1):
        assert start(client, s, intensity_before=bad).status_code == 422
    c = start(client, s).json()
    for bad in (0, 11):
        assert passed(client, s, c, bad).status_code == 422
    assert start(client, s, intensity_before=1).status_code == 201
    assert start(client, s, intensity_before=10).status_code == 201


def test_halt_accepts_only_the_four_states(client, sms):
    _, s = setup(client, sms)
    assert start(client, s, halt=["bored"]).status_code == 422
    assert start(client, s, halt=["I am sad because of ..."]).status_code == 422


def test_a_moment_passes_only_once(client, sms):
    _, s = setup(client, sms)
    c = start(client, s).json()
    assert passed(client, s, c).status_code == 200
    r = passed(client, s, c, 2)
    assert r.status_code == 409 and r.json()["detail"]["code"] == "craving_already_passed"
    assert mine(client, s).json()[0]["intensity_after"] == 3


def test_newest_first_and_window(client, sms):
    _, s = setup(client, sms)
    older = start(client, s, intensity_before=4).json()
    # Age the first one past the default 30 days; refresh tokens do not
    # survive that long a clock jump, so the row is moved, not the clock.
    with Session(engine) as db:
        row = db.get(CravingLog, uuid.UUID(older["id"]))
        row.created_at = row.created_at - timedelta(days=40)
        db.commit()
    newer = start(client, s, intensity_before=9).json()
    assert [c["id"] for c in mine(client, s).json()] == [newer["id"]]
    assert [c["id"] for c in mine(client, s, days=90).json()] == [newer["id"], older["id"]]
    assert mine(client, s, days=0).status_code == 422
    assert mine(client, s, days=91).status_code == 422


def test_a_patient_sees_and_changes_only_their_own(client, sms):
    _, a = setup(client, sms)
    b = unlocked(client, sms, "0771234567")
    mine_a = start(client, a).json()
    assert mine(client, b).json() == []
    r = passed(client, b, mine_a)
    assert r.status_code == 404
    assert mine(client, a).json()[0]["intensity_after"] is None


def test_needs_a_signed_in_patient(client, sms):
    doc, s = setup(client, sms)
    assert client.post("/v1/me/cravings", json={"intensity_before": 5}).status_code == 401
    assert client.get("/v1/me/cravings").status_code == 401
    assert client.get("/v1/me/cravings", headers=bearer(doc)).status_code == 403


def test_doctor_reads_a_clinic_patients_cravings(client, sms):
    doc, s = setup(client, sms)
    c = start(client, s).json()
    passed(client, s, c, 2)
    url = f"/v1/staff/patients/{s['user']['id']}/cravings"
    rows = client.get(url, headers=bearer(doc)).json()
    assert [(r["intensity_before"], r["intensity_after"]) for r in rows] == [(8, 2)]
    assert rows[0]["halt"] == ["tired", "lonely"]


def test_other_doctor_of_the_clinic_reads_them_but_a_patient_cannot(client, sms):
    _, s = setup(client, sms)
    start(client, s)
    other_doctor()
    other = login(client, "other@example.invalid").json()
    url = f"/v1/staff/patients/{s['user']['id']}/cravings"
    assert len(client.get(url, headers=bearer(other)).json()) == 1
    assert client.get(url, headers=bearer(s)).status_code == 403
    assert client.get(url).status_code == 401
    unknown = "/v1/staff/patients/00000000-0000-0000-0000-000000000000/cravings"
    assert client.get(unknown, headers=bearer(other)).status_code == 404


def test_audit_lines_carry_ids_only(client, sms):
    _, s = setup(client, sms)
    c = start(client, s, halt=["tired"]).json()
    passed(client, s, c)
    with Session(engine) as db:
        lines = list(
            db.scalars(select(AuditLog).where(AuditLog.action.in_(["craving.started", "craving.passed"])))
        )
        row = db.get(CravingLog, uuid.UUID(c["id"]))
    assert sorted(line.action for line in lines) == ["craving.passed", "craving.started"]
    assert all(line.target == c["id"] for line in lines)
    assert row is not None and row.halt == ["tired"]
