"""Difficult moments: craving logs (habit-tracking design, step 1)."""

import uuid
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.clock import clock
from app.db import engine
from app.models import AuditLog, CravingLog

from .conftest import advance, bearer, register
from .test_medications import unlocked
from .test_staff import login, other_doctor
from .test_substance_tracking import setup


def start(client, s, **body):
    return client.post(
        "/v1/me/cravings", json={"intensity": 7, "triggers": ["tired"]} | body, headers=bearer(s)
    )


def passed(client, s, craving_id, intensity=3):
    return client.patch(
        f"/v1/me/cravings/{craving_id}", json={"intensity": intensity}, headers=bearer(s)
    )


def test_log_a_craving_then_it_passes(client, sms):
    _, s = setup(client, sms)
    r = start(client, s, triggers=["hungry", "tired", "hungry"])
    assert r.status_code == 201, r.text
    c = r.json()
    assert (c["intensity_before"], c["triggers"], c["passed_at"], c["intensity_after"]) == (
        7, ["hungry", "tired"], None, None
    )
    r = passed(client, s, c["id"], 2)
    assert r.status_code == 200
    assert r.json()["intensity_after"] == 2 and r.json()["passed_at"] is not None
    # Once only.
    r = passed(client, s, c["id"], 1)
    assert r.status_code == 409 and r.json()["detail"]["code"] == "craving_already_passed"
    [row] = client.get("/v1/me/cravings", headers=bearer(s)).json()
    assert (row["intensity_before"], row["intensity_after"]) == (7, 2)


def test_triggers_are_optional(client, sms):
    _, s = setup(client, sms)
    r = start(client, s, triggers=[])
    assert r.status_code == 201 and r.json()["triggers"] == []
    r = client.post("/v1/me/cravings", json={"intensity": 4}, headers=bearer(s))
    assert r.status_code == 201 and r.json()["triggers"] == []


def test_intensity_is_1_to_10_and_triggers_are_halt(client, sms):
    _, s = setup(client, sms)
    for bad in (0, 11, -1):
        assert start(client, s, intensity=bad).status_code == 422, bad
    assert start(client, s, triggers=["bored"]).status_code == 422
    c = start(client, s, intensity=10).json()
    assert passed(client, s, c["id"], 0).status_code == 422
    assert passed(client, s, c["id"], 11).status_code == 422
    assert start(client, s, intensity=1).status_code == 201


def test_list_is_newest_first_and_limited_to_the_window(client, sms):
    _, s = setup(client, sms)
    old = start(client, s, intensity=5).json()
    # Moved 40 days back by hand: outside the default 30-day window.
    with Session(engine) as db:
        row = db.get(CravingLog, uuid.UUID(old["id"]))
        row.started_at = clock.now() - timedelta(days=40)
        db.commit()
    start(client, s, intensity=8)
    # The frozen clock would stamp both rows with the same started_at.
    advance(minutes=5)
    start(client, s, intensity=6)
    r = client.get("/v1/me/cravings", headers=bearer(s))
    assert r.status_code == 200, r.text
    rows = r.json()
    assert [r["intensity_before"] for r in rows] == [6, 8]
    rows = client.get("/v1/me/cravings?days=90", headers=bearer(s)).json()
    assert [r["intensity_before"] for r in rows] == [6, 8, 5]


def test_patient_reaches_only_own_cravings(client, sms):
    _, s = setup(client, sms)
    c = start(client, s).json()
    _, other = setup(client, sms, "0771234567")
    assert client.get("/v1/me/cravings", headers=bearer(other)).json() == []
    assert passed(client, other, c["id"]).status_code == 404
    assert passed(client, s, "00000000-0000-0000-0000-000000000000").status_code == 404


def test_cravings_are_locked_and_patient_only(client, sms):
    locked = register(client, sms)
    for r in (client.get("/v1/me/cravings", headers=bearer(locked)), start(client, locked)):
        assert r.status_code == 403 and r.json()["detail"]["code"] == "recovery_locked"
    doc, _ = setup(client, sms, "0771234567")
    assert client.get("/v1/me/cravings", headers=bearer(doc)).status_code == 403
    assert client.get("/v1/me/cravings").status_code == 401


def test_doctor_sees_a_patients_cravings(client, sms):
    doc, s = setup(client, sms)
    c = start(client, s, intensity=9, triggers=["lonely"]).json()
    passed(client, s, c["id"], 4)
    [row] = client.get(f"/v1/staff/patients/{s['user']['id']}/cravings", headers=bearer(doc)).json()
    assert (row["intensity_before"], row["triggers"], row["intensity_after"]) == (9, ["lonely"], 4)


def test_colleague_sees_cravings_and_is_audited(client, sms):
    _, s = setup(client, sms)
    start(client, s)
    other_doctor()
    other = login(client, "other@example.invalid").json()
    url = f"/v1/staff/patients/{s['user']['id']}/cravings"
    assert client.get(url, headers=bearer(other)).status_code == 200
    with Session(engine) as db:
        targets = db.scalars(select(AuditLog.target).where(AuditLog.actor_id.is_not(None))).all()
    assert any(t and s["user"]["id"] in t for t in targets)
    assert client.get(url, headers=bearer(s)).status_code == 403
    assert client.get(url).status_code == 401


def test_unknown_patient_is_not_found(client, sms):
    doc, _ = setup(client, sms)
    stranger = unlocked(client, sms, "0771234567")
    r = client.get(f"/v1/staff/patients/{stranger['user']['id']}/cravings", headers=bearer(doc))
    assert r.status_code == 200
    r = client.get("/v1/staff/patients/00000000-0000-0000-0000-000000000000/cravings",
                   headers=bearer(doc))
    assert r.status_code == 404
