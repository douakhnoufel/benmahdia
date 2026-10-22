"""Daily jobs, run by one small process (`python -m app.jobs`, the `jobs`
service in infra/docker-compose.yml): erase accounts past their grace period
(PRD 12.5) and raise missed-dose alerts (PRD 5.3). It wakes up at 00:10
Algiers time every night. A failing job is logged and does not stop the other
or tomorrow's run."""

import logging
import time
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from . import scheduling
from .alerts_job import missed_dose_alerts
from .clock import clock
from .db import SessionLocal
from .purge import purge

log = logging.getLogger("benmahdia.jobs")

RUN_AT_MINUTE = 10  # minutes after midnight, clinic time


def seconds_until_next_run(now_utc: datetime) -> int:
    """Seconds from [now_utc] (naive UTC) to the next 00:10 in Algiers."""
    today = scheduling.clinic_today(now_utc)
    for day in (today, today + timedelta(days=1)):
        run = scheduling.to_utc(day, RUN_AT_MINUTE)
        if run > now_utc:
            return int((run - now_utc).total_seconds())
    raise AssertionError("unreachable")  # tomorrow's run is always ahead


def run_once(db: Session) -> dict[str, int | None]:
    """Runs every job once; a job that fails reports None."""
    results: dict[str, int | None] = {}
    for name, job in (("purge", purge), ("missed_dose_alerts", missed_dose_alerts)):
        try:
            results[name] = job(db)
        except Exception:  # noqa: BLE001 - one job must not stop the others
            db.rollback()
            log.exception("job %s failed", name)
            results[name] = None
    return results


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    while True:
        wait = seconds_until_next_run(clock.now())
        log.info("next run in %d s", wait)
        time.sleep(wait)
        with SessionLocal() as db:
            log.info("ran: %s", run_once(db))


if __name__ == "__main__":
    main()
