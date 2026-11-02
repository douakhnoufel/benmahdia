# Alerts and privacy: recovery QA, 2026-10-26

Tester: alerts-privacy (prefix ALERT). I checked against PRD §5.1, §5.3, §5.6 (Alerts, Privacy, Good habits), §7 (alerts inbox), §8.3 and §12.3, and the rules checklist `rules.md`.

**HEAD:** `c772566` at start and at end. No file under `backend/app`, `apps/mobile/lib`, `apps/dashboard/src` or `docs` changed during the run (`git status --short` showed none of them at the end), so the code under test did not move.

**Files I wrote** (nothing else):
- `backend/tests/test_qa_recovery_alerts.py`. An earlier attempt wrote 35 tests and never ran them. I ran them and kept them, with these fixes:
  - The audit test compared upper-case markers with a lower-cased audit row. That check could never fail; it does now.
  - The SEC-07 log test matched the test's own source line in the traceback (a false positive). It now reads the exception text only.
  - One "question" test became the ALERT-03 xfail.
  - The xfail IDs were renumbered.

  I added 10 tests: back-dated courses, a locked-again patient, pending and rejected addictions, repeated relapses, the milestone after a read, `run_once` twice in one night, inbox order and the fixed thresholds. I also widened the two-doctor SEC-02 test to every alert kind. The file now has 45 tests.
- `apps/mobile/test/qa_recovery_privacy_test.dart`: 10 tests, new.
- This report.

**Setup:** the backend uses the default in-memory SQLite with the frozen clock (2026-10-17 18:00 UTC, 19:00 in Algiers). It reuses `setup`/`add`/`check` (test_substance_tracking), `prescribe`/`staff_session` (test_medications), `other_doctor` (test_staff), and `add_appointment`/`make_doctor`/`verified_patient` (booking_helpers). Fake markers only: `QA-substance-zx`, `QA-relapse-note-zx`, `QA-drugname-zx`, `QA-amount-zx`, `QA-instructions-zx`, `QA-own-habit-zx`. Test phones: 0661234567 and 0661234502.

## Results

| Run | Command | Result |
|-----|---------|--------|
| Alerts file, as found (35 tests) | `cd backend && .venv/Scripts/python.exe -m pytest tests/test_qa_recovery_alerts.py -q -p no:cacheprovider -rfEX` | progress `......x................xx....x...x.` = 30 passed, 5 xfailed. pyproject already sets `-q`, so `-q` again hid the summary line. |
| Its 5 xfails, forced | same, `--runxfail -k "<the 5 names>"` | 5 failed, each on its own assert (none in setup). One was a false positive (see the SEC-07 fix above). |
| Alerts file, final (45 tests) | `cd backend && .venv/Scripts/python.exe -m pytest tests/test_qa_recovery_alerts.py -p no:cacheprovider -rfEX` | `39 passed, 6 xfailed, 1 warning in 54.14s` |
| Final xfails, forced | `cd backend && .venv/Scripts/python.exe -m pytest tests/test_qa_recovery_alerts.py -p no:cacheprovider --runxfail` | `6 failed, 39 passed, 1 warning in 55.77s`: the 6 failures are exactly the 6 xfails |
| Full backend suite | `cd backend && .venv/Scripts/python.exe -m pytest -p no:cacheprovider -rfX` | `1 failed, 613 passed, 49 skipped, 36 xfailed, 1 warning in 737.86s (0:12:17)`. The one failure is the pre-existing `tests/test_identity.py::test_nothing_readable_is_stored`. There was no XPASS. |
| Mobile privacy | `cd apps/mobile && flutter test test/qa_recovery_privacy_test.dart --no-pub` | `00:05 +10: All tests passed!` |
| Mobile analyzer | `cd apps/mobile && flutter analyze --no-pub test/qa_recovery_privacy_test.dart` | `No issues found! (ran in 15.0s)` |

**xfails:** every xfail in my file is strict. With `--runxfail`, each one fails on its stated assert:
- ALERT-01: `assert 0 == 1`, no `craving_high` ever.
- ALERT-02: `assert [] == [patient]`, no alert on deletion.
- ALERT-03: `assert 1 == 0`, `no_checkin` raised.
- SEC-02, cancelled booking: the relapse goes to the other doctor.
- SEC-02, two doctors: `[('craving_high', 'other'), ('milestone', 'other'), ('missed_doses', 'first'), ('relapse', 'other')]`.
- SEC-07: the exception text contains `1, 5, '{"irritability": 5, "restlessness": 4}'`.

## Findings

### ALERT-01: A high-craving day saved after the nightly run never completes a craving_high run
- Severity: medium
- Rule: R-104, R-105 (PRD §5.6 Alerts)
- Where: backend/app/alerts_job.py:79 (`_check_window`: only the three full days before the run) and backend/app/alerts_job.py:112 (`craving_alerts`); backend/app/routers/addiction_checks.py:143 (a check is accepted up to two days back)
- Repro: `test_a_check_saved_after_the_nightly_run_still_completes_three_high_days` in backend/tests/test_qa_recovery_alerts.py (xfail strict).
  1. Craving 5 is saved on 10-18 and 10-19.
  2. The 10-21 00:10 run sees 10-20 empty: no alert, which is correct.
  3. At 08:00 on 10-21 the patient saves 10-20 with craving 5 (204), then 10-21 with craving 2.
  4. The 10-22 run looks at 10-19 to 10-21: no alert.
- Expected (PRD): "craving 4 or more on 3 days in a row for one addiction". 10-18, 10-19 and 10-20 qualify, so the doctor gets one alert.
- Actual: no `craving_high` is ever raised for that run. A day filled in after its nightly run is never read again together with the two days before it.
- Reach in the app: the daily-check screen keeps the day it was opened on (apps/mobile/lib/features/recovery/recovery_screen.dart:245). Opened before midnight and saved after 00:10, it saves the earlier day after its run. Any client using the API's two-day window reaches it too.

### ALERT-02: Deleting the account does not notify the doctor
- Severity: medium
- Rule: none in rules.md (PRD §12.5 step 2, "The account is disabled at once and the doctor is notified"); it sits next to R-110 / G-12
- Where: backend/app/routers/me.py:65 (`# TODO(dashboard): notify the patient's doctor once doctors are linked.`)
- Repro: `test_the_doctor_is_told_when_a_patient_deletes_their_account` (xfail strict). `DELETE /v1/me` returns 204, and the alerts table stays empty.
- Expected (PRD): the patient's doctor gets an alert naming only the event and the patient.
- Actual: no alert. The patient's file silently turns 404 for the doctor, yet the nightly craving, missed-check and missed-dose alerts for that account keep coming (see question Q-06).
- Why medium and not high: §12.5 is outside the sections listed for this run, and the code already marks it as a TODO.

### ALERT-03: no_checkin ignores checks on an addiction added in the last three days
- Severity: low
- Rule: R-106, R-107 (PRD §5.6 Alerts, "`no_checkin`: 3 days in a row with no daily check")
- Where: backend/app/alerts_job.py:134 (only addictions created before the window are collected). backend/app/alerts_job.py:141 then looks up checks on those addictions only.
- Repro: `test_checks_on_a_newly_added_addiction_count_as_daily_checks` (xfail strict).
  - The patient has an addiction 7 days old and a new one created on 10-15.
  - They check only the new one, on 10-15 and 10-16.
  - The run on 10-17 raises one `no_checkin`.
- Expected (PRD): the patient did a daily check on two of the three days, so there is no "3 days with no daily check" alert. The job counts one check on any single older addiction as the day's check (`test_a_check_on_one_of_two_addictions_counts_as_the_days_check` passes). A check on the new addiction should count the same way.
- Actual: the doctor is told the patient missed three days of checks.
- Why low: the app saves every addiction's check together, oldest first (apps/mobile/lib/features/recovery/daily_check_screen.dart:76 `_complete`; recovery_screen.dart:260). Only a client that saves the new addiction alone reaches this. Which definition is right ("any addiction checked" or, like the week strip, "every addiction checked") is question Q-05.

### SEC-02 (carried, not new): alerts follow the latest-starting booking, and one patient's alerts are split between doctors
- `test_one_patients_alerts_reach_one_doctor` (xfail strict). The patient has a past paid visit with doctor A, who also prescribes, and a **future** confirmed booking with doctor B. `craving_high`, `milestone` and `relapse` go to B, a doctor who has not seen the patient yet. `missed_doses` goes to A, the prescriber (R-100, G-01).
- `test_a_doctor_the_patient_cancelled_with_gets_no_alerts` (xfail strict): the next relapse alert goes to the doctor of a **cancelled** booking (R-85).
- What holds: an unpaid hold with another doctor (fix 71d844c) does not draw any nightly kind away from the paying doctor. `craving_high`, `milestone` and `no_checkin` all reach the paid doctor (`test_nightly_alerts_skip_a_doctor_the_patient_only_holds_a_slot_with`).

### SEC-07 (carried from the security tester, not new): answers in the error text of a racing check save
`test_a_database_error_on_a_check_does_not_put_answers_in_the_log` (xfail strict) checks SEC-07 from the log side (R-95). The `IntegrityError` text that uvicorn would log contains the craving and the signals JSON.

### UX-07 (carried from the flow tester): no medication reminder exists
R-72 cannot be tested for neutral text: the phone schedules no dose reminder. My home test confirms that no scheduled notification names the drug, the dose or the instructions, and that the scheduled set holds only the daily-check and habit reminders.

## Questions (PRD silent: not bugs)

Each one has a passing test that pins today's behaviour.

- **Q-01 (G-04, R-102):** a "skipped" answer counts as missed. Two days of skipped doses raise `missed_doses` (`test_question_skipped_doses_count_as_missed`). One dose of two taken on each day clears both days (`test_question_one_dose_of_two_taken_clears_the_day`).
- **Q-02 (G-04, R-103):** days before the course was entered count as missed. A course entered today with a start date a week back raises `missed_doses` at the first nightly run (`test_question_days_before_the_course_was_entered_count_as_missed`).
- **Q-03 (G-02/G-12, R-08, R-110):** the patient's only paid visit was cancelled, so every recovery route answers `403 recovery_locked`. The doctor can still prescribe (201), and the nightly job raises `missed_doses` for doses the patient has no screen to answer (`test_question_a_patient_locked_again_still_raises_missed_doses`).
- **Q-04 (G-07, R-109, R-16):**
  - Pending (unreviewed) addictions raise `craving_high` and `milestone` (`test_question_a_pending_addiction_raises_alerts_before_review`).
  - A rejected addiction raises no nightly alert (`test_a_rejected_addiction_raises_no_nightly_alert`).
  - A relapse posted on a rejected addiction's id is accepted (201) and sends a high-priority `relapse` alert, although that addiction left the patient's list (`test_question_a_relapse_on_a_rejected_addiction_still_alerts`).
- **Q-05 (R-106, §5.4 vs §5.6):** with several addictions, one check on any one older addiction is the day's check for `no_checkin`. A v1 tick also counts. The week strip asks for every addiction. Which is right? See ALERT-03.
- **Q-06 (G-12, R-110):** a deleted account (grace period) keeps raising nightly alerts that carry its phone, while its file is 404 for the doctor (`test_question_nightly_alerts_continue_for_a_deleted_account`).
- **Q-07 (G-06, R-107):** a patient with no addiction, who uses v1 ticks only, never gets `no_checkin` (`test_question_a_patient_with_no_addiction_never_gets_no_checkin`).
- **Q-08 (G-18, R-113):** the inbox is newest first. A newer `milestone` (normal) sits above an older `relapse` (high) (`test_question_inbox_lists_newest_first_not_by_priority`).
- **Q-09 (G-05):** repeats while the condition lasts.
  - `missed_doses` repeats every clinic day.
  - `craving_high` and `no_checkin` repeat every 3 days.
  - Reading an alert does not re-arm it early.
  - Each relapse is its own alert, even twice in one day after the first was read.
  - A milestone alert is raised once per milestone.

## What holds (tests pass)

**craving_high (R-104, R-105):**
- High days split across two addictions raise nothing until one addiction has all three.
- A day with no check breaks the run.
- Craving exactly 4 counts, and 3 does not.
- Two high addictions give one alert for the patient.
- The alert is not repeated within 3 days, even once read, and comes back on a fresh run 3 days later.

**no_checkin (R-106, R-107):**
- It is not repeated within 3 days, even once read.
- A check on one of two older addictions, or a v1 tick, counts as the day's check.
- An addiction added inside the window is skipped.

**missed_doses (R-101, R-102):**
- One missed day after a taken day raises nothing.
- At most one alert per clinic day, even once read, and again the next day while the misses go on.
- Dedupe follows the Algiers day, not the UTC day.

**Algiers day boundaries:** at the 00:10 run (23:10 UTC the day before), every window uses the three or two full **Algiers** days:
- A 10-17 check falls outside the 10-18 to 10-20 window.
- A dose taken on the Algiers day 10-17 counts at the run on 10-18.
- An addiction created at 00:30 Algiers on 10-18 is new for the 10-18 to 10-20 window. One created at 23:30 Algiers on 10-17 is not.

**Relapse and milestone (R-99, R-32):**
- A relapse raises one `relapse` alert at `priority=high` with no note or substance.
- The milestone alert is raised once. After it is read it does not come back. The next milestone (14 days) raises a new one.

**Dedupe (R-111):** every job twice in one night (00:10, then 03:10) gives `{missed_dose_alerts: 1, craving_alerts: 1, no_checkin_alerts: 1, milestone_alerts: 2}`, then all zero. The next night only `missed_doses` repeats.

**Thresholds fixed (R-108):** `HIGH_CRAVING=4`, `CHECK_DAYS_IN_A_ROW=3`, `DAYS_IN_A_ROW=2` are code constants. No setting can change them.

**Habits (R-64):** no habit ever raises an alert, even after six days of a habit never done.

**Alert payload (R-96):**
- The alert table has exactly `id, doctor_id, patient_id, type, priority, read, created_at`.
- Each of the five kinds is listed with exactly `{id, patient_id, patient_phone, type, priority, read, created_at}`.
- No marker or clinical word (`nicotine`, `tobacco`, `irritability`, `restlessness`) appears in an alert, even when the check said "used" with every signal at 5.

**Logs (R-95):** with caplog at DEBUG, I ran a full round of writes:
- add, check, confirm, profile change, relapse with a note
- prescribe, skip a dose, stop the medicine, prescribe again
- a custom habit: add, tick, remove
- v1 tick, reminder, goal, milestone seen, mark alerts read
- the doctor's reads
- seven nightly `run_once`

No marker and no signal key appears in the log messages or their args. A job that fails on a real database error logs `job missed_dose_alerts failed` and nothing of the prescription. The exception is the SEC-07 path.

**SMS:** the same round sends no SMS at all (`sms.sent` unchanged).

**Audit (R-94):** every recovery audit row present has a UUID as its target. That covers `addiction.added`, `addiction.confirmed`, `addiction.profile_set`, `relapse.logged`, `medication.prescribed`, `medication.stopped`, `habit.added` and `habit.removed`. No row holds a marker or a clinical word.

**Mobile, AR and FR (R-42, R-61, R-98):**
- The daily-check reminder is exactly "Rappel" / "C'est l'heure de votre rappel du jour." in FR and "تذكير" / "حان وقت تذكيرك اليومي." in AR. It names no profile, signal, addiction type or marker.
- Each of the six list habits is named in the app's language, never the other one ("C'est l'heure : …" / "حان وقت: …").
- A custom habit shows only "C'est l'heure de votre habitude." / "حان وقت عادتك.", even if the catalog wrongly carried an entry for `custom`.
- A list habit missing from the catalog falls back to the same neutral text.
- I pumped the real home (HomeShell) with an addiction carrying a substance marker, a due dose carrying drug, amount and instruction markers, a list habit and an own-words habit. It schedules exactly 21 recovery notifications: the daily check plus two habits, for 7 days each, all with the neutral texts. No notification the phone holds names a marker or a clinical word, and that includes the shared service's appointment reminder.

## Rules covered

R-08 (Q-03), R-16 (alert side, Q-04), R-32, R-42, R-61, R-64, R-72 (neutral side only; not built, UX-07), R-94, R-95, R-96, R-98 (recovery reminders only go to the local service), R-99, R-100 (SEC-02), R-101, R-102, R-103, R-104, R-105, R-106, R-107, R-108, R-109, R-110, R-111, R-112 (read and the unread filter, used along the way), R-113 (Q-08).

## Not run / not covered by me

- **R-114, R-115:** the dashboard inbox labels and the unread count. I own no dashboard file. Existing tests cover them: `recovery.test.tsx`, `tracking.test.tsx`, `booking-alerts.test.tsx`.
- **PostgreSQL:** my backend tests ran on SQLite only. The alert jobs are plain selects and inserts with no race. The race on PostgreSQL is SEC-07, which the security tester already ran.
- **The real Android notification:** the mobile tests check the text handed to the local-notifications service, through a fake service. I did not run them on a device or emulator.
- **Production log output:** checked through caplog and the exception text, not by running uvicorn.
- **Language switch while the home is open:** the scheduled reminders keep the language they were written in. The only language toggle is on the welcome, intro and sign-in screens, and the saved language is a TODO (apps/mobile/lib/main.dart). No patient can reach this today, so I filed nothing and kept no test for it.
