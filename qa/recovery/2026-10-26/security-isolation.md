# Security / isolation: recovery QA, 2026-10-26

Tester: security-isolation (prefix SEC). Checked against the PRD §3 role matrix: a patient sees only their own data. A doctor sees every appointment in the clinic, but clinical data only for their own patients. The super admin has doctor rights plus admin screens.

**HEAD:** `c772566` at start and at end. No file under `backend/app`, `apps/mobile/lib`, `apps/dashboard/src` or `docs` changed during the run (`git status` was clean for those paths at the end), so the code under test did not move.

**Test file:** `backend/tests/test_qa_recovery_isolation.py`. This is the only code file I touched. An earlier attempt wrote most of it but never ran it. I ran it, kept it, and added these:
- a locked patient on another patient's ids
- ids smuggled into query strings and bodies
- a sweep of the staff screens outside the patient file
- extra fields in doctors' write bodies
- a real two-thread race on PostgreSQL
- SEC-02 alert routing with a `confirmed` second booking

**Setup** (`world()` in the test file):
- Doctor A is the seeded doctor. Doctor B is a test doctor.
- The super admin holds a DoctorProfile but has no patients.
- Patient A (0661234511) and patient B (0661234512) each have one completed visit, with doctor A and doctor B respectively.
- Each patient has one row of every recovery kind:
  - a nicotine addiction, with substance text `QA-SUBST-x`
  - a relapse, with note `QA-NOTE-x`, which also raises a relapse alert
  - today's check
  - a custom habit `QA-HABIT-x`, ticked today
  - a prescription `QA-DRUG-x` / `QA-AMOUNT-x` / `QA-INSTR-x`, with today's dose answered
  - a v1 tick and a reminder
- No real data: placeholder words only.

## Results

| Run | Command (from `backend/`) | Result |
|-----|---------------------------|--------|
| SQLite (final file) | `.venv/Scripts/python.exe -m pytest tests/test_qa_recovery_isolation.py -p no:cacheprovider -rfEX` | `26 passed, 1 skipped, 7 xfailed, 1 warning in 114.79s (0:01:54)` |
| PostgreSQL 16 (final file) | `DATABASE_URL=postgresql+psycopg://qa:qa@127.0.0.1:55432/qa_recovery_sec .venv/Scripts/python.exe -m pytest tests/test_qa_recovery_isolation.py -p no:cacheprovider -rfEX` | `26 passed, 8 xfailed, 1 warning in 219.09s (0:03:39)` |
| Full backend suite, SQLite | `.venv/Scripts/python.exe -m pytest -p no:cacheprovider -rfX` | `1 failed, 604 passed, 49 skipped, 35 xfailed, 1 warning in 404.42s (0:06:44)`. The one failure is the pre-existing `test_identity.py::test_nothing_readable_is_stored`. There was no XPASS. After this run I changed only how two SEC-02 xfail tests list the routes that open, and the two file runs above are on that final version. |

**Skipped test:** the single skip on SQLite is `test_two_real_simultaneous_first_saves_of_a_check_are_not_a_500`, which needs PostgreSQL.

**PostgreSQL container:** a throwaway container, `qa-recovery-sec-pg` (postgres:16-alpine, 127.0.0.1:55432, started with `--rm`). I stopped it after the runs, so it is gone. I did not touch the shared `benmahdia-db-1` container. conftest drops every table, so it must never point at that database.

**xfails:** every xfail is strict. I ran each one with `--runxfail` and checked that it fails for its stated reason, not from a setup error.

## Findings

### SEC-06: A doctor reading a patient's clinical data leaves no audit row
- Severity: high
- Rule: R-93 (PRD §8.3 "Audit log of who viewed or changed patient data"); rules.md lists it as gap G-16
- Where: backend/app/routers/staff_recovery.py:57, backend/app/routers/addiction_checks.py:254, backend/app/routers/habits.py:232, backend/app/routers/medications.py:155 (none of these GET routes calls `audit.record`)
- Repro: `test_a_doctor_reading_clinical_data_is_audited` in backend/tests/test_qa_recovery_isolation.py (xfail strict). Doctor A reads five clinical routes for patient A: addictions with relapse notes, the 30-day and 90-day checks chart, habits, and medications. The number of doctor A's audit rows goes from 2 to 2.
- Expected (PRD): every view of a patient's clinical data is in the audit log (who, which patient or row, when). Only changes are audited today.
- Actual: only writes are audited (`addiction.confirmed/rejected/profile_set`, `medication.prescribed/stopped`). Views leave no trace. With SEC-02 open, this matters more: a second doctor reading a patient's file cannot be detected afterwards.

### SEC-07: Two simultaneous first saves of one daily check cause a 500 whose error text carries the patient's answers
- Severity: critical
- Rule: R-54 (PRD §5.6 Privacy "answers never appear in … logs", §8.3); R-95
- Where: backend/app/routers/addiction_checks.py:150-164 (select, then insert, with no handling of the unique violation on `addiction_checks(addiction_id, day)`); backend/app/db.py:24 (engine without `hide_parameters`)
- Repro (deterministic, any DB): `test_a_second_simultaneous_first_save_of_a_check_is_not_a_500`. A second save commits right after this request read "no check yet".
- Repro (real race, PostgreSQL only): `test_two_real_simultaneous_first_saves_of_a_check_are_not_a_500`. Two threads send the same first save at once, on 12 (addiction, day) pairs. In three probe runs, 11, 11 and 10 of the 12 pairs ended in the error. The test xfailed in 5 of 5 separate runs.
- Expected (PRD): a double tap, a retry, or two phones answering at once give 204 or 409. The answers never reach a log.
- Actual: unhandled `IntegrityError`, which the server returns as a 500. The exception text, observed in the run on PostgreSQL, includes the SQL parameters: `'used': True, 'craving': 1, 'signals': Json({'irritability': 1, 'restlessness': 1})`. The signal names also reveal the substance profile (nicotine).
- Production log (by reading, not by run): the Dockerfile serves the app with uvicorn (backend/Dockerfile:17). uvicorn logs every unhandled exception as "Exception in ASGI application" with the full traceback (.venv/Lib/site-packages/uvicorn/protocols/http/h11_impl.py:415), so these values are written to the server log.
- Severity: critical, because medical answers reach a log. The trigger is a concurrent first save, but the real race hit about 10 times in 12 attempts.

### SEC-08: Screenshots are not blocked on any screen
- Severity: medium
- Rule: R-97 (PRD §8.3 "No sensitive data in … app screenshots (screenshot blocking on sensitive screens)")
- Where: apps/mobile/android/app/src/main/kotlin/dz/benmahdia/benmahdia_mobile/MainActivity.kt:5 (a plain `class MainActivity : FlutterActivity()`)
- Repro: by inspection, with no automated test because I own no Flutter test file.
  - `grep -rni "FLAG_SECURE\|screenshot\|ScreenProtector\|secure_screen" apps/mobile/lib apps/mobile/android/app/src apps/mobile/ios/Runner apps/mobile/pubspec.yaml` finds nothing.
  - The only "secure" hits are a welcome-screen footer string and a TODO about secure token storage.
- Expected (PRD): the recovery, daily check and medication screens cannot be captured, and they are hidden in the app switcher.
- Actual: any screen, including relapse history, check answers and doses, can be captured and appears in the Android recent-apps thumbnail.

### SEC-02 (carried, not new): any doctor with a non-hold booking reads and changes the patient's recovery data and receives their alerts
Recovery evidence added in this run. All tests are xfail strict and fail for the stated reason.
- `test_sec02_two_paid_doctors_do_not_both_read_recovery_data`: patient A has a completed visit with doctor A and a **future confirmed** booking with doctor B. Both doctors get 200 on all five clinical read routes:
  - addictions, with relapse notes and the current goal
  - the checks chart, 30 days
  - the checks chart, 90 days
  - habits, with the patient's own words
  - medications
- `test_sec02_second_doctor_cannot_stop_another_doctors_prescription`: in the same setup, doctor B stops doctor A's prescription (204).
- `test_sec02_a_cancelled_booking_opens_no_clinical_data`: doctor B, whose only booking with patient A was **cancelled**, gets 200 on the same five read routes. This is R-85.
- `test_sec02_a_relapse_alert_stays_with_the_patients_doctor[cancelled]` and `[confirmed]`: the patient's next relapse alert goes to doctor B, the doctor of the latest-starting booking. This happens even when that booking is cancelled, or is a future visit that has not happened yet. The nightly `missed_doses` alert still goes to doctor A, the prescriber, so one patient's alerts are split between two doctors (R-100, G-01). `_doctor_of` is at backend/app/routers/recovery.py:270-282.

### SEC-04 (carried, not new): there is no clinic-staff role
"Clinic staff never see clinical data" (R-89) holds only because no such account can exist (`Role` at backend/app/models.py:33-36). The existing xfail is `test_qa_booking_isolation.py::test_a_clinic_staff_role_exists`. A super admin with no DoctorProfile, the closest thing to a non-doctor staff login, gets `403 forbidden` on every staff recovery route (`test_super_admin_without_a_doctor_profile_is_refused_everywhere`).

## What holds (tests pass on SQLite and PostgreSQL)

**Patient vs patient (R-82):**
- On every patient route that takes an id (check PUT, including a day outside the window; goal; milestone seen; relapse; habit reminder; habit tick and untick; habit delete; dose answer), patient B's id gets the same status and body as a random UUID: `404 not_found`. B's data does not change.
- The same calls by B on B's rows succeed, so the 404 is about ownership, not the body (`test_another_patients_ids_answer_like_random_ids_and_change_nothing`).
- A patient who only holds an unpaid slot gets `403 recovery_locked` on B's ids and on random ids alike. The lock is not an existence oracle, and the hold unlocks nothing (R-02) (`test_a_locked_patient_gets_the_same_lock_on_anothers_ids_as_on_random_ids`).
- None of the patient's own list or read responses carries another patient's words, prescription, phone or ids: `/v1/me`, addictions, checks, checkins, habits, doses (today and yesterday), quote and reminder.
- Adding `patient_id`, `user_id`, `addiction_id` or `medication_id` of patient B to the query string changes nothing (`test_patient_lists_carry_only_their_own_rows`).

**What the patient cannot change (R-19, R-20, R-68, R-15):**
- These routes do not exist: PUT, PATCH or DELETE on an addiction; read, PUT or DELETE of relapses; a patient profile, confirm or review route; DELETE of a check, a dose or a tick; any `/v1/me/medications` route. Each answers 404 or 405.
- Every staff write answers `403 forbidden` to a patient token, even on the patient's own file. Nothing is stored (`test_patient_has_no_route_to_change_medications_reviews_or_history`).
- Extra fields are ignored and the row stays the caller's (`test_extra_fields_cannot_set_review_or_medication_fields`):
  - review fields, counters, `milestone_seen` or `patient_id` in a new addiction
  - doctor fields, `clean_since` or `profile` in a goal
  - prescription fields in a dose answer
  - another patient's ids in a check, habit or tick body

**Doctor vs other doctors' patients (R-83, R-86, R-88, R-92):**
- These callers get exactly the same status and body as a random patient id (`404 patient_not_found`) on every clinical route, read and write:
  - doctor A
  - the super admin
  - doctor A holding a live unpaid hold with patient B
  - doctor A holding an expired unpaid hold with patient B
- The clinical routes are: addictions, checks (30 and 90 days), habits, medications, confirm, reject, profile, prescribe, stop. B's data does not change, and B's next relapse alert still goes to doctor B only (`test_doctor_without_a_paid_visit_reaches_none_of_the_patients_clinical_data`, 4 actors).
- An own-patient path carrying another patient's addiction or medication id returns `addiction_not_found` / `medication_not_found`, the same as a random id (R-86).

**Screens outside the patient file:**
- The clinic-wide agenda (today, 2026-10-14 and 2026-10-19), the patient list, the sign-ups queue and the alerts, read as the super admin and as doctor A, carry none of patient B's clinical rows and no clinical field name.
- Doctor A's reads of their own patient's file carry nothing of B's (`test_screens_outside_the_patient_file_carry_no_clinical_content`).

**Extra fields in doctors' write bodies:**
- A prescription body naming B's patient id, doctor B as prescriber, `active: false` or B's medication id still creates a row for the path's patient, prescribed by the caller.
- Confirm and profile bodies cannot change the reviewer, the review status, the substance, the start date or the counters (`test_staff_write_bodies_cannot_move_rows_to_another_patient_or_doctor`).

**Alerts (R-87, R-96, R-99):**
- After the nightly jobs, each doctor lists only their own patient's alerts (relapse, missed_doses, milestone). The fields are exactly `{id, patient_id, patient_phone, type, priority, read, created_at}`, and there is no medical content, not even about the doctor's own patient. The super admin's list is empty.
- Doctor A and the super admin get `404 alert_not_found` on doctor B's alert, identical to a random id, and the alert stays unread (`test_each_doctor_lists_and_marks_only_their_own_patients_alerts`).

**Tokens and roles (R-06, R-90, R-91):**
- No token, a garbage token, a forged-signature token, a refresh token used as access, an expired token, and the token of a just-deleted account all get 401 (`not_authenticated` / `token_invalid`) on every recovery route, patient and staff. Nothing changes (`test_missing_bad_or_dead_token_is_401_on_every_recovery_route`, 6 cases).
- A patient token gets `403 forbidden` on every staff recovery route, for any patient.
- Doctor and super-admin tokens get `403 forbidden` on every patient recovery route.
- A deleted patient's file looks unknown to their own doctor and leaves the patient list.

**Audit and logs (R-94, R-95):**
- Every recovery audit action the code has (`addiction.added`, `relapse.logged`, `addiction.confirmed`, `addiction.rejected`, `addiction.profile_set`, `medication.prescribed`, `medication.stopped`, `habit.added`, `habit.removed`) has the row id as its target. No audit row carries a substance, note, habit word, drug, amount, instruction, profile or signal name (`test_recovery_audit_rows_carry_row_ids_only`).
- At INFO level, a full round of patient and doctor actions plus `run_once` logs none of that content (`test_no_recovery_content_reaches_the_logs`). The exception is the SEC-07 500 path.

## Rules covered

R-02 (doctor and patient side of a hold), R-06, R-15 (review fields and audit target), R-19, R-20, R-54 (SEC-07), R-68, R-82, R-83, R-84 and R-85 (SEC-02), R-86, R-87, R-88, R-89 (SEC-04, by absence), R-90, R-91, R-92, R-93 (SEC-06), R-94, R-95, R-96, R-97 (SEC-08, by inspection), R-99 (an unpaid hold is not the alert recipient), R-100 (SEC-02 routing).

## Not run / not covered by me

- **R-42, R-61, R-98:** the AR text of the mobile reminders, and no push. These rows are security-area but live in Flutter code. I own no Flutter file, so I wrote no test. The flow tester's `apps/mobile/test/qa_recovery_flow_test.dart` is the place for them.
- **R-97 (SEC-08):** checked by grep only. There is no Flutter or Android test, for the same reason.
- **R-123:** transfer or share of a patient is not built. It is part of the SEC-02 family, so I filed no separate finding.
- **SEC-07 production log line:** confirmed by reading the uvicorn source, not by running a uvicorn server and reading its output. The 500 and the exception text with the answers were observed in runs on SQLite and PostgreSQL.
