# Concurrency (RACE) — 2026-10-25

Owner: concurrency specialist. Files written: `backend/tests/test_qa_booking_races.py`, this file.

## Run status: run on PostgreSQL

The coordinator started the database container `benmahdia-db-1` (127.0.0.1:5432, db/user `benmahdia`); I did not start or stop it. An earlier `docker info` in this session had failed (`dockerDesktopLinuxEngine` pipe missing).

**Workaround needed (RACE-01).** `tests/conftest.py` overwrites `DATABASE_URL` with `sqlite://`, so the command the coordinator suggested still skips everything. To get a PostgreSQL engine without editing conftest, I loaded a scratch pytest plugin with `-p`. It is not in the repo; it lives at `C:\Users\noufe\AppData\Local\Temp\claude\C--Users-noufe-OneDrive-Desktop-benmahdia\8d83ce99-1349-4a99-9184-e4f32199e495\scratchpad\pgplugin\qa_pg_plugin.py`. It sets the same test env vars as conftest and imports `app.db` first, so the engine is built on the PostgreSQL URL before conftest runs. Use `127.0.0.1`, not `localhost`: with `localhost`, each new connection took seconds on Windows, and the slowness made access tokens expire (401s).

Command (from `backend/`, Git Bash):

```
export PYTHONPATH='<scratchpad>\pgplugin;.'
DATABASE_URL=postgresql+psycopg://benmahdia:benmahdia@127.0.0.1:5432/benmahdia \
  .venv/Scripts/python.exe -m pytest -p qa_pg_plugin tests/test_qa_booking_races.py tests/test_concurrent_holds.py -q -p no:warnings -p no:logging -rfX --tb=line
```

**Result: 5 full runs, each `43 passed, 4 xfailed`, exit 0, no flakes.** Each parametrised race test runs 5 rounds per run, so 25 repetitions in total. The xfail tests loop 10–12 rounds inside the test, so 50–60 iterations each. The existing `test_concurrent_holds.py` passed on PostgreSQL in all 5 runs too.

Without PostgreSQL (`pytest tests/test_qa_booking_races.py -q`), the file collects and skips all 46 cases.

Two harness fixes were made inside my test file:
- An autouse `_fresh_pool` fixture calls `engine.dispose()` after conftest drops and recreates the tables. Without it, pooled psycopg connections kept prepared plans for the old tables and failed with `cached plan must not change result type`.
- The direct-insert constraint test also accepts PostgreSQL's `deadlock detected` as a refusal. Two concurrent INSERTs that conflict on the EXCLUDE constraint can be resolved by PostgreSQL as a deadlock instead of an IntegrityError. The app never reaches this, because `hold_slot` serialises inserts behind the doctor-row lock.

## Tests (`backend/tests/test_qa_booking_races.py`)

After every race, each test checks the database directly (`overlaps()`, a self-join): no two `awaiting_payment`/`confirmed` rows of one doctor may overlap.

| Test | Scenario | Rule | Result on PostgreSQL |
|---|---|---|---|
| test_many_patients_same_slot_exactly_one_wins | 10 patients, one slot → exactly one 201 | R-23 | pass 25/25 |
| test_patients_spread_over_few_slots_one_winner_per_slot | 12 patients over 3 slots → 3 winners | R-23 | pass 25/25 |
| test_db_refuses_overlapping_rows_with_different_starts | direct parallel inserts 08:00–08:15 / 08:10–08:20 → one refused | R-24 | pass 5/5 |
| test_slot_length_change_offset_starts_cannot_overlap | 15-min hold, doctor moves to 10-min slots; 08:10 all refused, 08:20 one winner | R-19/R-24 | pass 25/25 |
| test_one_patient_parallel_holds_same_doctor_keeps_one | 6 parallel holds, one doctor → 1 open hold | R-25 | pass 25/25 |
| test_one_patient_parallel_holds_two_doctors_keeps_one | parallel holds on 2 doctors → 1 open hold | R-25 | **xfail 5/5: RACE-04 confirmed** |
| test_expired_hold_owner_confirms_while_others_grab_the_slot | hold racing expiry | R-26/R-29 | pass 25/25 |
| test_paid_webhook_for_expired_hold_races_new_hold | late paid webhook vs new hold → confirmed XOR refund flag | R-47/R-48 | pass 25/25 |
| test_confirm_racing_release_never_loses_a_confirmed_booking | confirm vs DELETE hold, natural timing | R-27/R-30 | **xfail 5/5: unhandled 500 (StaleDataError)** |
| test_confirm_racing_cancel_is_consistent | confirm vs cancel | R-32 | pass 25/25 |
| test_two_paid_webhooks_in_parallel_confirm_once | same paid event twice at once | R-45 | pass 25/25 |
| test_paid_webhook_racing_release_never_loses_the_money | paid webhook vs DELETE hold, natural timing | R-46/R-48 | pass 5/5 (window not hit, see RACE-02) |
| test_paid_webhook_inside_release_gap_never_loses_the_money | same, release slowed 0.6 s between load and delete | R-46/R-48 | **xfail 5/5: RACE-02 confirmed** |
| test_confirm_inside_release_gap_keeps_the_booking | confirm inside a slowed release | R-27/R-30 | **xfail 5/5: RACE-03 confirmed** |

The two "gap" tests use a monkeypatched `_mine` that sleeps only when called from `release_hold`. This makes the window between the release's status check and its delete wide enough to hit every time, as a slow request or a GC pause would.

## What holds (R-23, R-24): confirmed by the run

The doctor-row `SELECT … FOR UPDATE` (`appointments.py:133-135`) plus the overlap check, backed by the `EXCLUDE USING gist` constraint (`models.py:514-522`, migration `0002_appointments.py:95-97`), held in every round. No double booking was seen in 25 repetitions of each hold race, including offset starts after a slot-length change.

## Findings

### RACE-01: PostgreSQL race tests cannot run as documented: conftest forces SQLite
- Severity: medium
- Rule: R-23, R-24 (PRD §4.3 AC 1)
- Where: backend/tests/conftest.py:4 (`os.environ["DATABASE_URL"] = "sqlite://"`, unconditional)
- Repro: `DATABASE_URL=postgresql+psycopg://… pytest tests/test_concurrent_holds.py` skips without connecting (observed).
- Expected (PRD): AC 1 is proven on the real database by the documented command.
- Actual: only the out-of-repo `-p` plugin workaround runs them. Fix (test-only): keep an existing PostgreSQL `DATABASE_URL`, and dispose the pool after `create_all`. **Confirmed by run.**

### RACE-02: A paid webhook inside a hold release deletes the paid booking, with no refund flag
- Severity: high
- Rule: R-46, R-48 (PRD §4.4)
- Where: backend/app/routers/appointments.py:185-197 (`release_hold`: status read in memory, then `db.delete` by primary key, no row lock); backend/app/routers/payments.py:106-125
- Repro: test_paid_webhook_inside_release_gap_never_loses_the_money. Observed: `release=204: payment paid, appointment gone, no refund flag`.
- Expected (PRD): money received gives a confirmed visit, or the payment is flagged `payment.needs_refund`.
- Actual: the payment is `paid`, the appointment row is deleted (`payments.appointment_id` set NULL), and there is no refund flag. With natural timing it did not trigger in 60 iterations: the async webhook holds the event loop, so the window is narrow in a single-worker deploy. It is still reachable (slow request, more workers). The mobile app avoids releasing while a checkout is open (`book_confirm_screen.dart:69,156`), but the API does not stop it. The same pattern by reading: a `checkout.failed/expired` event that loaded the hold before a `paid` commit would delete the confirmed visit and overwrite `paid` with `failed` (not run). **Confirmed by run (with injected delay).**

### RACE-03: Confirm racing release: told "confirmed" with a check-in code, then the booking is deleted, or a 500
- Severity: medium
- Rule: R-27, R-30 (PRD §4.3)
- Where: backend/app/routers/appointments.py:185-197, 200-226
- Repro: (a) test_confirm_inside_release_gap_keeps_the_booking. Observed: confirm returned 200 with a check-in code, release returned 204, and the row was gone. (b) test_confirm_racing_release_never_loses_a_confirmed_booking, natural timing. Observed: confirm got an unhandled `StaleDataError: UPDATE … expected to update 1 row(s); 0 were matched`, i.e. HTTP 500.
- Expected (PRD): a confirmed visit stays booked; a hold that is gone gets a clean 409.
- Actual: as above. Reachable from the app: `dispose()` releases while `_booked` is still false during an in-flight confirm, so tapping Confirm then Back can trigger it (book_confirm_screen.dart:150-157). **Confirmed by run.**

### RACE-04: "One open hold per patient" breaks with parallel holds on two doctors
- Severity: medium
- Rule: R-25 (PRD §12.2.1)
- Where: backend/app/routers/appointments.py:133-151 (lock is per doctor; no partial unique index on `patient_id WHERE status='awaiting_payment'`)
- Repro: test_one_patient_parallel_holds_two_doctors_keeps_one. Observed: `round 1: patient has 2 open holds`.
- Expected (PRD): at most one open hold per patient.
- Actual: two open holds. **Confirmed by run.**

### RACE-05: Card webhook and pay-at-the-clinic confirm can both win; method and code overwritten
- Severity: medium
- Rule: R-28, R-44 (PRD §4.3 Pilot payment, §4.4)
- Where: backend/app/routers/appointments.py:214-226; backend/app/routers/payments.py:108-115
- Repro: by reading. Both read `awaiting_payment` without a lock and both confirm. The last commit sets `method`, possibly `clinic` on a card-paid visit. Each runs `checkin.issue` on a NULL code, so the code shown by the first response can be replaced.
- Expected (PRD): one confirmation path, recorded truthfully.
- Actual: as above. **By reading, not run** (no test written for this pair).

### RACE-06: A concurrent delete turns confirm or the webhook into an unhandled 500
- Severity: low
- Rule: none (question): robustness
- Where: backend/app/routers/appointments.py:220-226; backend/app/routers/payments.py:110-116
- Repro: the confirm half was observed in RACE-03(b) (`StaleDataError`, 500). The webhook half is by reading: it rolls back with the payment still `pending`, and the refund flag only appears when Chargily retries (test_paid_webhook_for_expired_hold_races_new_hold simulates that retry and passed).
- Expected: 409 for the app; refund flagged on the first delivery.
- Actual: 500. **Confirm half confirmed by run; webhook half by reading.**

### RACE-07: The webhook does sync database work inside `async def`: serialised today, double-processing latent
- Severity: low
- Rule: R-45 (PRD §4.4 AC 3)
- Where: backend/app/routers/payments.py:84-130; backend/Dockerfile:17 (single uvicorn worker)
- Repro: test_two_paid_webhooks_in_parallel_confirm_once passed 25/25, as predicted: the blocking handler serialises webhooks on the event loop. With more than one worker, both would pass the unlocked `status != pending` check. It also stalls the loop while it runs.
- **Not confirmed (latent), by reading.**

### RACE-08: The global expired-hold cleanup could deadlock holds for different doctors
- Severity: low
- Rule: R-26
- Where: backend/app/routers/appointments.py:92-100, 144
- Repro: by reading. No deadlock appeared in the hold races, but those mostly use one doctor. PostgreSQL did produce `deadlock detected` for two concurrent conflicting INSERTs outside the doctor lock (direct-insert test), so deadlocks are a real failure mode here, and the app catches only `IntegrityError`.
- **Not confirmed, by reading.**

## Summary

| ID | Severity | Title | Status |
|---|---|---|---|
| RACE-01 | medium | PostgreSQL race tests cannot run as documented (conftest forces SQLite) | confirmed by run |
| RACE-02 | high | Paid webhook inside a hold release deletes the paid booking, no refund flag | confirmed by run (injected delay) |
| RACE-03 | medium | Confirm racing release: booking deleted after 200, or 500 | confirmed by run |
| RACE-04 | medium | One open hold per patient broken across two doctors | confirmed by run |
| RACE-05 | medium | Card webhook + clinic confirm both win; method/code overwritten | by reading, not run |
| RACE-06 | low | Concurrent delete gives unhandled 500 (StaleDataError) | confirm half confirmed; webhook half by reading |
| RACE-07 | low | Webhook sync DB in async def; double-processing latent | not confirmed (latent) |
| RACE-08 | low | Global expired-hold cleanup may deadlock across doctors | not confirmed, by reading |

No double booking: R-23/R-24 hold on PostgreSQL across 25 repetitions of every hold race.
