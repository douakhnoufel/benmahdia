# API rules: recovery QA, 2026-10-26

Tester: api-rules (prefix API). I tested the recovery rules of `docs/PRD.md` through the HTTP API: §3, §5 intro (unlock), §5.1–5.4, §5.6, §7, §8.6 and §12.3. I took the "api" rows of `rules.md`, uncovered rows first.

**HEAD:** `c772566` at start and at end (2026-10-29). Nothing under `backend/app`, `apps/*/lib`, `apps/dashboard/src` or `docs` changed during the run (`git status` showed the same untracked QA files and the same unrelated `gradle-wrapper.properties` change at start and end). The code under test did not move.

**Test file:** `backend/tests/test_qa_recovery_rules.py`. It is the only code file I touched. An earlier attempt wrote most of it but never ran it. I ran every test, checked each xfail with `--runxfail` to confirm it fails for its stated reason (not from a setup error), and kept what was sound. I then made these changes:
- **New tests:**
  - API-02: a check answered ahead is locked on its own day
  - API-14: the doctor's correction of the entry
  - API-20: the relapse "trigger"
  - relapse note bounds
  - API-08: the quote still picked by a rejected addiction
- **Widened:** the "taken as prescribed" test now covers pregabalin as well as buprenorphine, and also checks that no alert is raised.
- **Fixed:** the answers-in-the-error test now works on both drivers. On PostgreSQL, psycopg prints the bound values as a Python dict, so the old JSON-only check XPASSed there.
- **Split:** the PostgreSQL parallel test is now two tests: an integrity test that must pass, and the 500 check, which is an xfail.

**Fixtures:** fake data only. Phones are 06612345NN, the doctors are seeded, the course is named "Traitement QA" / "1 unité", and texts are placeholders ("Produit QA", "Note QA"). The clock is frozen at 2026-10-17 18:00 UTC (19:00 in Algiers). I reused the existing helpers rather than copying them: `booking_helpers`, `test_medications`, `test_substance_tracking` and `conftest`.

## Results

| Run | Command (from `backend/`) | Result |
|-----|---------------------------|--------|
| SQLite, first run of the inherited file | `.venv/Scripts/python.exe -m pytest tests/test_qa_recovery_rules.py -q -p no:cacheprovider` | exit 0, all dots/x/s. With the `-q` from `addopts` there was no summary line, so I reran without `-q`. |
| SQLite, xfail reasons | `... --runxfail -k "triggers or midnight or plain_ascii or adherence or edit_a_schedule or recovery_stage or quote_library or double_tap_is_not or failed_check_save"` | each fails on its own assertion (see each finding) |
| PostgreSQL 16, race tests (inherited parallel test) | `DATABASE_URL=postgresql+psycopg://benmahdia:benmahdia@127.0.0.1:5432/qa_recovery_rules_tmp ... -k "double_tap or failed_check_save or parallel" -s` | `1 failed, 1 passed, 83 deselected, 5 xfailed`. The failure was the JSON-only answers check XPASSing on psycopg (fixed). Save codes were `{204: 143, 500: 73}`; 8 parallel relapses gave 8 rows and 8 alerts. |
| PostgreSQL 16, race tests (split tests) | same, `-k "double_tap or failed_check_save or parallel"` | `2 passed, 83 deselected, 6 xfailed`. Save codes were `{204: 151, 500: 77, 200: 12}` and `{204: 128, 500: 97, 200: 15}`. Rows: 12 checks, 12 habit ticks, 3 v1 ticks, 3 dose answers (exactly one per key), 8 relapses, 8 relapse alerts. |
| SQLite, new xfails | `... --runxfail -k "given_ahead or corrects_the_patients_entry"` | `2 failed` on the intended asserts (409 `check_locked`; type/substance/date unchanged, only `/profile` tried) |
| PostgreSQL 16, whole file (before the last two edits) | `DATABASE_URL=... .venv/Scripts/python.exe -m pytest tests/test_qa_recovery_rules.py -p no:cacheprovider -rxXsf` | `73 passed, 18 xfailed, 1 warning in 146.95s (0:02:26)` |
| PostgreSQL 16, API-06 check | `DATABASE_URL=... --runxfail -k plain_ascii` | `"21:30\n"` gives `StringDataRightTruncation: value too long for type character varying(5)` (a 500); `"1١:3٠"` gives 200 and is stored |
| SQLite, whole file (final) | `.venv/Scripts/python.exe -m pytest tests/test_qa_recovery_rules.py -p no:cacheprovider -rxXsf` | `73 passed, 2 skipped, 17 xfailed, 1 warning in 58.97s` |
| PostgreSQL 16, whole file (final, fresh throwaway database) | same as the PostgreSQL row above, with `-s` | `74 passed, 18 xfailed, 1 warning in 185.49s (0:03:05)`. Save codes were `{204: 147, 500: 78, 200: 15}` and `{204: 134, 500: 88, 200: 18}`, with one row per key both times. |
| SQLite, full backend suite | `.venv/Scripts/python.exe -m pytest -p no:cacheprovider -rfX` | `1 failed, 616 passed, 50 skipped, 38 xfailed, 1 warning in 477.74s (0:07:57)`. The only failure is the pre-existing `test_identity.py::test_nothing_readable_is_stored`, and there was no XPASS. This run collected my file before the last two edits: one added passing test (`test_question_a_rejected_addiction_still_picks_the_quote`) and the route-count floor raised from 21 to 22. Both final file runs above include them. |

**PostgreSQL:** the shared `benmahdia-db-1` container was already running when I started (up 4 days). I did not start it and did not stop it. I created a throwaway database, `qa_recovery_rules_tmp`, inside it (conftest drops every table, so it must never point at `benmahdia`). I dropped that database after the runs.

**Skipped on SQLite:** the two `*_on_postgresql` tests need real concurrent transactions. Both ran on PostgreSQL above.

## Findings

### API-01: A daily check saved just after midnight in Algiers locks at 01:00 the same day
- Severity: medium
- Rule: R-46 (PRD §5.6 "One answer per addiction per day, editable the same day"; §8.6, the clinic is in Algeria; gap G-03)
- Where: backend/app/routers/addiction_checks.py:158 (`check.created_at.date() != now.date()`, both dates in UTC); :108-109 (`_today()` is the UTC date)
- Repro: `test_a_check_saved_after_midnight_in_algiers_stays_editable_that_day` in backend/tests/test_qa_recovery_rules.py (xfail strict). The patient saves the check for 10-18 at 00:30 Algiers time (23:30 UTC on 10-17), then edits it at 01:10 Algiers time on the same day.
- Expected (PRD): the answer can be edited all through the day it was given, as the patient lives it (Algiers).
- Actual: `409 check_locked`. The lock follows the UTC date. A check saved between 00:00 and 01:00 Algiers locks at 01:00. The reverse also happens: a check saved at 23:30 Algiers stays editable until 00:59 the next Algiers day.

### API-02: A check answered the evening before its day is locked on that day
- Severity: medium
- Rule: R-45, R-48 (PRD §5.6 "One answer per addiction per day, editable the same day")
- Where: backend/app/routers/addiction_checks.py:143-145 (window: UTC today −2 to **+1**); :158 (the lock follows the day the row was created, not the day it is about)
- Repro: `test_a_check_given_ahead_can_still_be_corrected_on_its_day` (xfail strict). At 19:00 Algiers on 10-17, the API accepts an answer about 10-18, a day that has not begun anywhere in Algeria. At 10:00 on 10-18 the patient corrects it.
- Expected (PRD): an answer about a day can be corrected during that day.
- Actual: `409 check_locked` on 10-18. A whole day ahead is open at any hour, because the +1 day is meant for the UTC/Algiers offset but is applied to the UTC date. An answer given early (or by a phone with a wrong date) is then frozen on the day it describes. Whether the API should accept an answer about tomorrow at all is part of G-03.

### API-03: Recovery "today" is the UTC date in the week strip and the doctor's views, so the first hour of the Algiers day goes missing
- Severity: medium
- Rule: R-47, R-49, R-118, R-63 (PRD §5.4 week strip, §5.6 "What the doctor sees", "Doctor also sees"; gap G-03)
- Where:
  - backend/app/routers/addiction_checks.py:196 (`a.created_at.date() <= day`, a UTC date)
  - backend/app/routers/addiction_checks.py:267 and :275 (the chart ends at UTC today)
  - backend/app/routers/habits.py:241-248 (the habit summary ends at UTC today)
- Repro:
  - `test_adding_an_addiction_after_midnight_in_algiers_keeps_yesterday_done` (xfail strict). 10-17 is fully checked. At 00:30 Algiers on 10-18, the patient adds a second addiction. 10-17 then drops out of `done_days`: `[] == ['2026-10-17']`.
  - `test_the_doctor_sees_the_patients_day_right_after_midnight_in_algiers` (xfail strict). At 00:30 Algiers on 10-18, the patient answers 10-18 and ticks a habit. The doctor's chart shows `[]`, and the habit summary has 0 done days.
- Expected (PRD): the week strip and the doctor's 30-day views follow the patient's day. Doses and the quote already do: medications.py:46-47 uses `scheduling.clinic_today`, and `test_doses_and_ticks_follow_the_algiers_day_after_midnight` passes.
- Actual: between 00:00 and 01:00 Algiers, the week strip treats a new addiction as existing "yesterday", so yesterday is no longer done. The doctor's chart and habit summary leave out the patient's current day. Checks, habits and ticks use UTC; doses, the quote and the alert job use the clinic day. Two "todays" exist side by side.

### API-04: A duplicate same-day save that loses the race is a 500 (check, habit tick, v1 tick, dose)
- Severity: medium
- Rule: R-54, R-45, R-58, R-39, R-70 (PRD §5.6 one answer per day, one tick per habit per day; §5.4; §5.3; §8.6 "slow 3G/4G", where retries and double taps are normal)
- Where:
  - backend/app/routers/addiction_checks.py:150-164
  - backend/app/routers/habits.py:200-203
  - backend/app/routers/checkins.py:59-64
  - backend/app/routers/medications.py:278-289

  All four select first, then insert, and none of them catches the unique violation.
- Repro:
  - Deterministic, any database: `test_a_double_tap_is_not_a_server_error[check|habit|tick|dose]` (xfail strict). The other request's row commits right before this request inserts. All four return 500.
  - Real race, PostgreSQL: `test_parallel_duplicate_saves_are_not_server_errors_on_postgresql` (xfail strict). 8 identical requests at once, for 10 keys on each of 3 days. Across four runs of the 240-request workload, 77, 97, 78 and 88 requests were 500s; the first, inherited run gave 73 of 216.
- Expected (PRD): a double tap or a retry gets the same answer as the first save (204/200, or 409). The patient never sees a server error for an answer that was in fact saved.
- Actual: 500 with an unhandled `IntegrityError`. Integrity holds: `test_parallel_duplicate_saves_keep_one_row_per_day_on_postgresql` passes, with exactly one row per key. The phone shows a failure for data that was saved.
- Privacy side: the error text of a lost check save carries the craving and signal answers, and uvicorn logs it. That part is **SEC-07** (critical, security tester); I do not report it again. My test `test_a_failed_check_save_keeps_the_answers_out_of_the_error` (xfail strict, reason "QA SEC-07 (carried)") reproduces it on SQLite and on PostgreSQL. On PostgreSQL the text includes `'craving': 5, 'signals': Json({'irritability': 4, 'restlessness': 5})`. A lost dose save puts `status: taken/skipped` and the medication id in the same kind of error text. That is adherence data, but no drug name.

**API-05 is not used.** I had numbered the answers-in-the-error case API-05 before I read the security report. It is the same defect as SEC-07, so the test now carries "QA SEC-07 (carried)" and this id is retired.

### API-06: The HH:MM check accepts a trailing newline and non-ASCII digits
- Severity: low
- Rule: R-40, R-60, R-65 (PRD §5.4 and §5.6 "time picker, 24-hour"; §5.3 times per day)
- Where: backend/app/routers/checkins.py:28 (`^([01]\d|2[0-3]):[0-5]\d$`). Here `$` matches before a final `\n`, and `\d` matches any Unicode digit. medications.py:39 has the same pattern, and habits.py:21 imports it. The columns are `String(5)` (backend/app/models.py:75 and :505).
- Repro: `test_reminder_times_are_plain_ascii_hh_mm["21:30\n"]` and `["1١:3٠"]` (xfail strict). The daily reminder PUT, the habit reminder PUT and the prescription times all accept them.
- Expected (PRD): a 24-hour `HH:MM` time.
- Actual:
  - On SQLite both values are accepted with a 200.
  - On PostgreSQL, `"21:30\n"` is a 500 (`StringDataRightTruncation`, varchar(5)).
  - `"1١:3٠"` is stored and served back to the phone. The app's parser expects ASCII digits.
- Why low: the app always sends ASCII `HH:MM` (apps/mobile/lib/features/recovery/api_recovery_repository.dart:385), so only another client can send these values.

### API-09: The doctor cannot record triggers or a severity level per addiction
- Severity: medium
- Rule: R-18 (PRD §3 "Per addiction: … triggers noted by the doctor, severity level"; "The doctor can correct it and adds triggers and severity"; §9 data model; §10 Phase 2 "addiction profiles")
- Where: backend/app/models.py:393-426 (`Addiction` has no `triggers` or `severity` column); backend/app/routers/staff_recovery.py (only confirm and reject)
- Repro: `test_the_doctor_records_triggers_and_severity` (xfail strict). The staff addiction row has neither field.
- Expected (PRD): the doctor adds triggers and a severity level when reviewing.
- Actual: no field and no route. This is not built.

### API-10: The doctor cannot see medication adherence
- Severity: medium
- Rule: R-74 (PRD §7 patient file "medication adherence"; §5.3 "history syncs to the server")
- Where: backend/app/routers/medications.py:155-167 (the staff GET returns the schedule only). No staff route reads `DoseLog`.
- Repro: `test_the_doctor_reads_medication_adherence` (xfail strict). The test probes every staff GET under `/v1/staff/patients/{patient_id}` for the patient's "taken" answer: medications, addictions, the checks chart and habits are all 200 and none of them shows it.
- Expected (PRD): the patient file shows the patient's dose history.
- Actual: the server keeps the answers, but only the nightly `missed_doses` alert uses them. The doctor never sees them.

### API-11: The doctor can prescribe and stop a medicine, but not edit its schedule
- Severity: low
- Rule: R-66 (PRD §7 "Medications: create and edit schedules per patient")
- Where: backend/app/routers/medications.py:127 (POST) and :170 (DELETE). There is no PUT or PATCH.
- Repro: `test_the_doctor_can_edit_a_schedule` (xfail strict). The item route has only `delete`.
- Expected (PRD): the doctor edits a schedule (times, dose, end date).
- Actual: the only way is stop and re-prescribe. That workaround hides the stopped course's past answers from the patient (see question API-19) and restarts the "course newer than 2 days" grace of the `missed_doses` alert.

### API-12: The quote of the day ignores the recovery stage
- Severity: low
- Rule: R-77 (PRD §5.2 "chosen by addiction type and recovery stage")
- Where: backend/app/models.py:569-580 (`Quote` has no stage); backend/app/routers/medications.py:301-323 (the choice uses type only)
- Repro: `test_the_quote_is_chosen_by_recovery_stage` (xfail strict)
- Expected (PRD): a quote that fits the patient's stage (for example, early days versus a long streak).
- Actual: the stage is not modelled. What a "stage" is remains open (G-13).

### API-13: Nobody can manage the quote library from the dashboard
- Severity: medium
- Rule: R-79 (PRD §5.2 "Library managed by the super admin; doctors can add their own"; §3 super admin "manage quotes library"; §7 super admin screens)
- Where: no route. backend/app/main.py:44-62 registers no quote router. Quotes come only from `backend/app/quotes_seed.py`.
- Repro: `test_the_quote_library_is_managed_from_the_dashboard` (xfail strict). There is no `/v1/staff/*quote*` path.
- Expected (PRD): the super admin adds, edits and deactivates quotes, and doctors add their own.
- Actual: changing a quote needs a code change or SQL.

### API-14: The doctor can correct only the substance profile, not the clean-since date, the substance or a generic type
- Severity: medium
- Rule: R-17 (PRD §3: the patient enters "substance profile or type, substance, 'clean since' date"; "The doctor can correct it". After that "only a relapse moves the counter"; gap G-09)
- Where: backend/app/routers/addiction_checks.py:231-251 (only `profile`; `None` keeps the type); backend/app/routers/staff_recovery.py:93-112 (confirm and reject only)
- Repro: `test_the_doctor_corrects_the_patients_entry` (xfail strict). The patient enters a generic "other" addiction, substance "Produit QA", clean since 10-07. The doctor sends type gambling, substance "Jeux QA" and clean since 10-09 to every staff PUT/PATCH under the addiction. Only `PUT …/profile` exists; it answers 200 and changes nothing of the three.
- Expected (PRD): the doctor corrects the entry, including a wrong clean-since date, before the counter is locked.
- Actual: a mistyped start date can never be fixed. The patient has no edit route (R-19, tested), and the doctor has none either. The only lever is a fake relapse, which moves the date forward only, adds a relapse to the history and sends a high alert. A generic addiction's type and the substance text cannot be corrected either.

## Questions (PRD silent, not bugs)

Each one is pinned by a `test_question_*` test that passes and records today's behaviour.

- **API-07 (R-05, G-02): a paid visit cancelled later locks recovery again.** `test_question_a_paid_visit_cancelled_later_locks_recovery_again`. Every patient recovery route answers `403 recovery_locked` again, and the data stays. The doctor still reads the file (see SEC-02) and keeps getting alerts (alerts tester, Q-03). Should a once-paid patient keep tracking?
- **API-08 (R-16, R-13, G-07): a rejected addiction is only half gone.** `test_question_a_rejected_addiction_still_takes_relapses_goals_and_a_slot` and `test_question_a_rejected_addiction_still_picks_the_quote`. It leaves the patient's list, the daily check and the week strip. But its id still takes:
  - a relapse (201, which raises a high `relapse` alert; the alert side is the alerts tester's Q-04)
  - a goal (200)
  - a milestone seen (200)

  It also still counts toward the 10-addiction limit: with 9 visible, the 10th is refused `too_many_addictions`. And its type still picks the quote of the day: a gambling-only quote is served after the gambling addiction was rejected. Sources: `recovery.py:139-143` (`_own` ignores `review_status`), `recovery.py:174-178`, `medications.py:307-311`.
- **API-15: a double tap on "I relapsed" logs two relapses and two high alerts.** `test_question_a_double_tap_on_i_relapsed_logs_two_relapses`. On PostgreSQL, 8 parallel relapses gave 8 rows and 8 alerts, with the counters consistent. Should two relapses seconds apart be one event?
- **API-16 (R-34, G-10): after 4 weeks no other goal step can be chosen.** `test_question_after_four_weeks_no_other_step_can_be_chosen`. On day 35, 60, 90, 180 and 365 are all refused `goal_invalid`; only 1–28 are accepted (`recovery.py:247`).
- **API-17 (R-71, G-11): Snooze is not something the server keeps.** `test_question_snooze_is_not_an_answer_the_server_keeps`. `snooze`, `snoozed`, `missed` and `due` are all 422. Is Snooze local only, and how long does it last?
- **API-18 (G-04): a dose can be answered for tomorrow.** `test_question_a_dose_can_be_answered_for_tomorrow`. The window is clinic today −2 to +1, so "taken" for tomorrow's dose is accepted and counts as taken for `missed_doses`. Unlike checks (API-02), dose answers stay editable, so the only question is whether "tomorrow" should be open at all.
- **API-19 (R-73): a stopped medicine disappears from the patient's past days.** `test_question_a_stopped_medicine_leaves_the_patients_past_days`. The answers stay in the database (1 row), but `GET /v1/me/doses?day=…` no longer lists them (`medications.py:232-233`).
- **API-20 (R-23, G-08): a relapse has no "trigger" apart from its note.** `test_question_a_relapse_has_no_trigger_apart_from_its_note`. A `trigger` field is dropped without a word (201, nothing stored). Is "note or trigger" one free-text field?

## Carried, not new

- **SEC-02:** "own patient" is any non-hold booking. Unlock and alerts depend on it in API-07. Not re-reported.
- **SEC-07:** answers in the error text and the log of a racing check save. Reproduced by `test_a_failed_check_save_keeps_the_answers_out_of_the_error` on both databases; see API-04.

## What passed (rules held)

- **Unlock (R-01, R-02, R-03).** The test sweeps every `/v1/me` route tagged `recovery`, read from the API's own route table (22 routes, the same 22 as the rules.md inventory, including the milestone seen, the habit reminder, habit days PUT/DELETE, habit delete and the goal). All of them answer `403 recovery_locked` before a paid visit and open after one. `completed` and `no_show` keep recovery open, and a confirmed visit still to come unlocks it.
- **Addictions (R-10, R-14, R-15).** All six profiles map to their PRD types, and a contradicting type is 422. A new addiction is `pending`. Confirm and reject record `reviewed_by`/`reviewed_at` and are audited with the row id only. The doctor can change their mind.
- **Start date and relapse history (R-19, R-20).** PUT/PATCH on the patient or staff addiction is 404/405. A `clean_since` slipped into the goal, milestone or profile bodies is ignored. There is no DELETE or PUT on relapses or on the addiction.
- **Relapse (R-21, R-22, R-24, R-25, R-27 API side).** A "when" in the future (over 5 minutes of slack) or before the current start is refused. An offset is converted to UTC, and the hour is kept so the app can show hours. The note is trimmed (blank becomes none), with 500 characters accepted and 501 refused. Longest streak and total survive repeated relapses. A relapse restarts the milestone ladder and sets the goal back to 1 day. "Used" in the check alone logs no relapse and no alert.
- **Ladder (R-29, R-31, R-33, R-35).** Milestone and automatic goal are correct through the API for 0, 1, 2, 3, 6, 7, 14, 27, 28, 30, 60, 90, 180, 364, 365 and 730 days. "Seen" never runs ahead of the milestone reached. A chosen goal, once reached, moves on to the next step.
- **Small goals (R-34).** Higher and lower choices work. Bad values (1, 2, 4, 30, −1, a missing field) are 422 `goal_invalid`.
- **Daily check (R-43, R-44, R-45, R-48, R-49).** The six profiles ask exactly the PRD's signals, in the PRD's order. Another profile's keys, one missing key or none at all give `signals_mismatch`; generic means craving only. Ratings are whole numbers 1–5: 0, 6, −1, 2.5, null, text and a missing field are 422, and 1 and 5 are accepted. There is one row per addiction per day. Yesterday and two days ago can be answered; three days ago is out of range. An answer locks once its day is over (in UTC: API-01). The week strip counts only the addictions that existed that day.
- **Taken as prescribed (PRD §5.6 Goal).** A buprenorphine or pregabalin dose taken does not move the counter, the checks, the relapses or the alerts.
- **Habits (R-57, R-58, R-60, R-62).** Five active at most, and the 6th is `too_many_habits`. Removing one frees its slot, keeps its done day, and makes every route on it 404. It is audited by row id. One tick per habit per day; unticking a day never ticked is harmless.
- **Times (R-40, R-60, R-65).** 00:00, 09:05 and 23:59 are accepted. 24:00, 23:60, 9:05, 09:5, 09:05:00, " 09:05", 09h05, "", -1:00 and "9 PM" are refused on all four entry points.
- **Doses (R-68, R-69, R-70).**
  - The last day of a course can be answered; the day after is `dose_not_scheduled`, and three days back is `dose_day_out_of_range`.
  - A second answer replaces the first. Past answers read back on their day, and an unanswered past dose is `missed`.
  - Another patient's, a stopped or an unknown medicine is 404.
  - The patient has no medication write route (404/405 on `/v1/me/medications*`, 403 on the staff routes).
- **Quote (R-75, R-78).** It changes at midnight in Algiers, not at midnight UTC. Both languages are non-empty.
- **Day boundary for doses and ticks (R-47, partly).** At 00:30 Algiers, today's doses and their answer are the Algiers day's, and a v1 tick or habit tick for the Algiers day is accepted.
- **Audit (R-94, R-15, R-62, R-67).** `addiction.added`, `relapse.logged`, `addiction.confirmed`, `habit.added`, `habit.removed`, `medication.prescribed` and `medication.stopped` carry the row id only. No substance, note, own words, drug name, dose, profile or type appears.

## Rules covered

**Tested in this file:** R-01, R-02, R-03, R-05, R-10, R-13, R-14, R-15, R-16, R-17, R-18, R-19, R-20, R-21, R-22, R-23, R-24, R-25, R-27 (API side), R-29, R-31, R-33, R-34, R-35, R-39 (day boundary), R-40, R-43, R-44, R-45, R-46, R-47, R-48, R-49, R-54, R-57, R-58, R-60, R-62, R-63, R-65 (times), R-66, R-67 (audit), R-68, R-69, R-70, R-71, R-73, R-74, R-75, R-76 (rejected type), R-77, R-78, R-79, R-94 (recovery write actions), R-118.

**API rows left to their existing tests (already covered in rules.md, not re-tested):** R-04, R-09, R-11, R-12, R-38, R-52, R-53, R-55, R-56, R-81.

## Not run

- Nothing in my area. Both PostgreSQL-only tests ran against a throwaway database. Mobile and dashboard rows belong to other roles.
