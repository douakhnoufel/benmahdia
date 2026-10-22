from datetime import datetime

from sqlalchemy.orm import Session

from app import jobs
from app.db import engine


def test_waits_until_ten_past_midnight_in_algiers():
    # 2026-10-17 18:00 UTC is 19:00 in Algiers: 5 h 10 min to go.
    assert jobs.seconds_until_next_run(datetime(2026, 10, 17, 18, 0)) == 5 * 3600 + 10 * 60
    # Just before the run time today (23:05 UTC = 00:05 Algiers): 5 minutes.
    assert jobs.seconds_until_next_run(datetime(2026, 10, 17, 23, 5)) == 5 * 60
    # Exactly at the run time, or after it: tomorrow's.
    assert jobs.seconds_until_next_run(datetime(2026, 10, 17, 23, 10)) == 24 * 3600
    assert jobs.seconds_until_next_run(datetime(2026, 10, 17, 23, 30)) == 24 * 3600 - 20 * 60


def test_run_once_runs_both_jobs_and_survives_a_failure(client, monkeypatch):
    seen = []
    monkeypatch.setattr(jobs, "purge", lambda db: seen.append("purge") or 0)

    def broken(db):
        seen.append("alerts")
        raise RuntimeError("boom")

    monkeypatch.setattr(jobs, "missed_dose_alerts", broken)
    with Session(engine) as db:
        results = jobs.run_once(db)
    assert seen == ["purge", "alerts"]
    assert results["purge"] == 0 and results["missed_dose_alerts"] is None


def test_run_once_raises_alerts_for_real(client, sms):
    from .booking_helpers import make_doctor
    from .conftest import bearer
    from .test_medications import linked_patient, prescribe, staff_session

    doctor = make_doctor()
    doc = staff_session(client, doctor)
    s = linked_patient(client, sms, doctor)
    prescribe(client, doc, s)  # a medicine nobody answered for two days
    with Session(engine) as db:
        assert jobs.run_once(db)["missed_dose_alerts"] == 1
    assert len(client.get("/v1/staff/alerts", headers=bearer(doc)).json()) == 1
