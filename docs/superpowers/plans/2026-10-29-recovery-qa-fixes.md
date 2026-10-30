# Recovery QA (PR #2): integrate and fix

Spec: docs/PRD.md (binding), CLAUDE.md rules. QA findings: qa/recovery/2026-10-26/rules.md
and the strict-xfail tests in backend/tests/test_qa_recovery_*.py, apps/mobile/test/qa_recovery_flow_test.dart.

Branch: `claude/stoic-edison-oeygz5` (= master after PR #1). PR #2's branch
`origin/claude/qa-recovery-tests` is merged into it (merge commit, no rebase); the result
ships as a new PR that supersedes PR #2.

## Global Constraints

- Access rule (CLAUDE.md, PRD §3): every doctor of the clinic sees every clinic patient's clinical
  data; opening a colleague's patient file is audited (ids only); visit notes private to their
  author unless shared; clinic staff never see clinical data; a patient sees only their own data.
  A "clinic patient" has a booked visit (not an unpaid hold). Alerts are seen by every doctor.
- No medical content (answers, drug names, doses, addiction types) in notifications, alerts text,
  logs, error bodies or the audit log. Audit stores row ids only.
- The patient's day is the Africa/Algiers calendar day, never the UTC day.
- Every backend endpoint change has tests. A fixed QA bug: remove its `xfail` so the test runs
  as a normal passing test. Never delete or skip a QA test to get green.
- Arabic RTL + French on every screen; design tokens only.
- Small commits. Backend: `cd backend && .venv/bin/pytest -q -p no:warnings -o addopts=""`.
  Dashboard: `cd apps/dashboard && npx tsc -b && npm run lint && npx vitest run`.
  Mobile: `cd apps/mobile && flutter test`.

## Task 1: Integrate PR #2

- `git merge origin/claude/qa-recovery-tests` into the working branch.
- Resolve conflicts in apps/dashboard/src/App.tsx, api.ts, i18n.tsx keeping both sides
  (PR #1's notes/shared files and PR #2's articles/milestone alert).
- Alembic ids collide (both sides have 0013 and 0014). Renumber PR #2's migrations:
  `0013_articles.py` → `0015_articles.py` (revision "0015", down_revision "0014"),
  `0014_milestones.py` → `0016_milestones.py` (revision "0016", down_revision "0015").
  Update the "Revision ID / Revises" docstrings too. One head after: `alembic heads`.
- Run all three suites. Record pass/fail/xfail counts in the report. Expected failures at this
  point: only the QA tests that assume the old "own patients only" rule (fixed in Task 2) and the
  known mobile failures (Task 8). Anything else failing is a merge defect: fix it here.

## Task 2: Re-baseline QA access tests to shared clinic files

In test_qa_recovery_isolation.py and test_qa_recovery_alerts.py:
- SEC-02 tests (two doctors read recovery data; a second doctor stops a medicine; a doctor whose
  only visit was cancelled reads data; relapse alert target): rewrite to assert the shared rule —
  any clinic doctor may read and manage a clinic patient's clinical data, and alerts appear in every
  doctor's alert list. Drop their xfail. Keep tests that a non-clinic patient (only an unpaid hold,
  or no booking) is 404 for doctors, and that clinic staff get no clinical data.
- SEC-06: rewrite to the PRD rule — a doctor opening a colleague's patient file writes one
  `patient_file.opened` audit row with ids only; opening one's own patient's file writes none.
  If it already passes against master's code, drop the xfail; otherwise fix in app code.
- Do not change app code beyond what SEC-06 needs.

## Task 3: Algiers calendar day (API-01, API-03)

Make the same-day edit window, the addiction week strip, and the doctor's chart/habit summary use
the Africa/Algiers date. Prefer one shared helper (e.g. `clock.today_algiers()` / a date-of
function) used by every place that currently takes `.date()` of a UTC time for a patient's day.
Remove the three xfails (rules.py lines ~502, ~530, ~796 before merge).

## Task 4: Duplicate same-day saves (API-04, API-05, SEC-07, ALERT-02)

A second save of the same day's check, habit tick, v1 tick or dose that loses the race must return
the same success answer as an idempotent save (the stored row), never a 500. A database error on a
recovery write must not put the patient's answers into the log or the response: catch
`IntegrityError` and re-read/upsert, and make sure no exception text containing bound parameters
reaches the logger (e.g. log a generic message). Covers the PostgreSQL parallel tests too.
Remove the corresponding xfails.

## Task 5: Strict HH:MM (API-06)

Times accept exactly `^[0-2][0-9]:[0-5][0-9]$` in ASCII with hour ≤ 23 — no trailing newline, no
non-ASCII digits (use `re.fullmatch` with `[0-9]` / `re.ASCII`). Remove the xfail.

## Task 6: Account deletion notifies the doctors (ALERT-04, PRD 12.5 step 2)

Deleting an account creates an alert of a new type `account_deleted` for the patient (seen by every
doctor, like other alerts), with no medical content. Dashboard shows the type with AR + FR labels.
Remove the xfail.

## Task 7: Late check never completes a craving_high run (ALERT-01)

Reproduce with the QA test, root-cause, fix in alerts_job so a day checked after the nightly run
still counts toward the run. Remove the xfail.

## Task 9: Data integrity — keys, constraints, indexes

Audit (2026-10-29, PostgreSQL): `alembic check` reports no drift between models and migrations;
all patient-owned tables already have FKs with indexes. One migration `0017_integrity.py`
(PostgreSQL + SQLite batch mode), with matching model changes and tests:

1. Missing foreign keys (ON DELETE RESTRICT: a clinical record keeps who wrote it):
   `medications.prescribed_by` → doctor_profiles.user_id, `articles.author_id` → doctor_profiles.user_id,
   `addictions.reviewed_by` → doctor_profiles.user_id (nullable). `audit_log.actor_id` stays without
   an FK on purpose: the audit trail must outlive the account.
2. Wrong cascade: `appointment_notes.doctor_id` is ON DELETE CASCADE, so removing a doctor's profile
   silently deletes their clinical notes. Change to RESTRICT.
3. Check constraints (the API already validates these; the database becomes the last line):
   appointments `price_dzd >= 0`; payments `amount_dzd > 0`; addiction_checks `craving BETWEEN 1 AND 5`;
   addictions `goal_days > 0`, `milestone_seen >= 0`, `milestone_alerted >= 0`, `longest_past_days >= 0`,
   `past_days >= 0`; medications `end_date IS NULL OR end_date >= start_date`;
   articles `language IN ('ar','fr')`, `published = false OR published_at IS NOT NULL`;
   alerts `priority IN ('normal','high')`; dose_logs `time`, habits `reminder_time`: on PostgreSQL a
   regex check `^([01][0-9]|2[0-3]):[0-5][0-9]$`.
   Before adding each check the migration counts violating rows and aborts with a clear message
   naming the table and constraint (never the row content) instead of deleting or rewriting data.
4. Indexes for the queries the dashboard runs: `appointments(start_utc)` (clinic-wide day lists across
   doctors; the existing (doctor_id, start_utc) index cannot serve them),
   `appointments(status, hold_expires_at)` (hold expiry), `alerts(created_at)` (newest-first list),
   `audit_log(action, created_at)`, `articles(published, published_at)`.
5. Tests: one test per constraint proving the database refuses a bad row (IntegrityError), the FK
   RESTRICT tests, and `alembic upgrade head` / `downgrade -1` / `upgrade head` on PostgreSQL.

Out of scope (PRD question, PRD §16 open item "data retention"): users → appointments/payments are
ON DELETE CASCADE, so hard-deleting a patient erases visit and payment records. The PRD says those
follow a retention policy not yet agreed with the clinic; do not change these cascades.

## Task 8: Mobile QA failures

Run `flutter test`; for each failing test in qa_recovery_flow_test.dart (and any other), decide:
real layout/RTL bug (fix in app code, tokens only) or wrong test expectation (fix the test, with
the reason in the commit message). No test may be deleted or skipped.

## Out of scope: PRD questions (stay xfail, listed for the user)

API-09 (triggers/severity per addiction), API-10 (staff view of dose answers), API-11 (edit a
medicine's schedule), API-12 (quote stage), API-13 (quote library management). These are features
the PRD may not ask for; do not build them.
