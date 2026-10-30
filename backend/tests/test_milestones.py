"""Milestones (PRD 5.1): the app celebrates each one once, and the daily job
tells the doctor once per milestone, with no medical content."""

import pytest
from sqlalchemy.orm import Session

from app.alerts_job import milestone_alerts
from app.db import engine
from app.substances import reached_milestone

from .conftest import bearer
from .test_substance_tracking import add, later, setup


@pytest.mark.parametrize(
    ("days", "milestone"),
    [(0, 0), (1, 1), (2, 1), (3, 3), (29, 14), (30, 30), (364, 180), (365, 365), (729, 365), (730, 730)],
)
def test_ladder_then_every_year(days, milestone):
    assert reached_milestone(days) == milestone


def run_job() -> int:
    with Session(engine) as db:
        return milestone_alerts(db)


def alerts(client, doc):
    return [a["type"] for a in client.get("/v1/staff/alerts", headers=bearer(doc)).json()]


def test_counter_says_which_milestone_to_celebrate(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()  # clean for 10 days
    assert (a["milestone"], a["milestone_seen"]) == (7, 0)

    r = client.post(f"/v1/me/addictions/{a['id']}/milestone/seen", headers=bearer(s))
    assert r.status_code == 200, r.text
    assert (r.json()["milestone"], r.json()["milestone_seen"]) == (7, 7)
    listed = client.get("/v1/me/addictions", headers=bearer(s)).json()[0]
    assert listed["milestone_seen"] == 7

    later(client, s, days=4)  # 14 days: the next one is due
    listed = client.get("/v1/me/addictions", headers=bearer(s)).json()[0]
    assert (listed["milestone"], listed["milestone_seen"]) == (14, 7)


def test_a_relapse_starts_a_new_ladder(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    client.post(f"/v1/me/addictions/{a['id']}/milestone/seen", headers=bearer(s))
    r = client.post(f"/v1/me/addictions/{a['id']}/relapses", json={}, headers=bearer(s))
    assert (r.json()["milestone"], r.json()["milestone_seen"]) == (0, 0)


def test_only_the_patient_marks_their_milestone_seen(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    _, other = setup(client, sms, "0771234567")
    url = f"/v1/me/addictions/{a['id']}/milestone/seen"
    assert client.post(url).status_code == 401
    assert client.post(url, headers=bearer(other)).status_code == 404


def test_the_doctor_is_told_once_per_milestone(client, sms):
    doc, s = setup(client, sms)
    a = add(client, s).json()  # 10 days: the highest reached is 7, told once
    assert run_job() == 1
    assert run_job() == 0
    assert alerts(client, doc) == ["milestone"]

    later(client, s, days=4, doc=doc)  # 14 days
    assert run_job() == 1

    client.post(f"/v1/me/addictions/{a['id']}/relapses", json={}, headers=bearer(s))
    later(client, s, days=1, doc=doc)  # day 1 of the new streak
    assert run_job() == 1
    assert alerts(client, doc).count("milestone") == 3


def test_the_alert_names_no_addiction(client, sms):
    doc, s = setup(client, sms)
    add(client, s, substance="Lyrica")
    run_job()
    milestone = [a for a in client.get("/v1/staff/alerts", headers=bearer(doc)).json() if a["type"] == "milestone"]
    assert len(milestone) == 1
    assert "Lyrica" not in str(milestone) and "nicotine" not in str(milestone)
