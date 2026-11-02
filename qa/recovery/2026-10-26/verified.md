# Verified findings: recovery QA, 2026-10-26

**Verifier:** independent. I wrote none of the tests and changed no test or app file.

**How each finding was checked:**
1. **PRD wording.** Does docs/PRD.md (or DESIGN.md) state the expected behaviour in those words? If not, the finding is a QUESTION.
2. **Code.** Does the code at "Where" match the description? I re-read it at HEAD.
3. **Repro test.** Does the test fail on its own assertion?
   - Backend: every xfail was re-run with `--runxfail`, on SQLite. The PostgreSQL-only ones were also run on a throwaway PostgreSQL 16.
   - Mobile: every Flutter bug group was run with `--dart-define=QA_RUN_BUGS=true`.
   - Dashboard: every `it.fails` was run with `QA_RUN_BUGS=true`.

**Severity guide** (from the run's ground rules):
- **critical:** another patient's data is visible; a doctor sees an unshared patient's clinical data (beyond the known SEC-02 case); or medical content reaches a notification, alert, log or audit row.
- **high:** a PRD rule is broken in a way a patient or doctor would hit.
- **medium:** a rule is broken in an edge case, or an error or empty state is missing.
- **low:** wording, tokens, polish.

**HEAD:** `c772566` at start and at end of verification. `git status` showed no change under `backend/app`, `apps/mobile/lib`, `apps/dashboard/src` (outside test files) or `docs`, so the code under test did not move. Only untracked QA files are new.

**Test fixes:** none were needed. Every xfail, skip and `it.fails` fails for the reason it states. No failure comes from a setup mistake (helper, clock, time zone).

## Totals

| Verdict | Count | Notes |
|---|---|---|
| CONFIRMED | **31 distinct** (34 reported bugs: 1 moved to question, 2 merged) | API-04 merged into SEC-07; API-03 merged into API-01 |
| QUESTION | 1 tester bug moved to question (API-02), plus the tester questions | Deduplicated list below |
| REJECTED | 0 | — |
| Carried, not new | SEC-02, SEC-04 | Not counted above |

**Confirmed by severity:**
- critical: 1
- high: 2
- medium: 15
- low: 13

No severity was raised or lowered except through the two merges. Each merge kept the higher severity.

## Confirmed

| ID | Sev | Title | Where | Repro | Verdict note |
|---|---|---|---|---|---|
| **SEC-07** (+API-04, API-05 retired; carried by ALERT) | critical | Two near-simultaneous first saves of a daily check end in an unhandled `IntegrityError` (500), and the server log carries the answers (used, craving, signal names and values). The same select-then-insert race gives a 500 on a habit tick, a v1 tick and a dose answer. | backend/app/routers/addiction_checks.py:150-164; habits.py:200-203; checkins.py:59-64; medications.py:278-289; db.py:24 (no `hide_parameters`) | test_qa_recovery_isolation.py::test_a_second_simultaneous_first_save_of_a_check_is_not_a_500, ::test_two_real_simultaneous_first_saves_of_a_check_are_not_a_500 (PG); test_qa_recovery_rules.py::test_a_double_tap_is_not_a_server_error[check\|habit\|tick\|dose], ::test_a_failed_check_save_keeps_the_answers_out_of_the_error, ::test_parallel_duplicate_saves_are_not_server_errors_on_postgresql (PG); test_qa_recovery_alerts.py::test_a_database_error_on_a_check_does_not_put_answers_in_the_log | PRD §5.6 Privacy: "answers never appear in … logs". **I confirmed this with a live uvicorn run, not just by reading.** A scratch probe served the real app with uvicorn (as backend/Dockerfile:17 does) and replayed the race. The response was `500`, and uvicorn's own log printed "Exception in ASGI application", then `[parameters: (…, 1, 5, '{"irritability": 4, "restlessness": 5}', …)]`. On PostgreSQL, 77 and 86 of 240 duplicate saves were 500s, the error text was `'craving': 5, 'signals': Json({...})`, and integrity held (one row per key). The trigger is a concurrent first save: rare from the app's daily-check Save, which sends one request, but reachable by retries or two phones. Critical per the guide (answers in a log). API-04 has the same root cause: no handling of the unique violation. |
| **UX-07** (carried by ALERT) | high | Medication reminders are not built: no local dose reminder and no Snooze | apps/mobile/lib/features/recovery/recovery_widgets.dart:637-787 (`DosesCard`: Taken / Not taken only); recovery_models.dart:301; recovery_reminders.dart | qa_recovery_flow_test.dart "UX-07 a due dose offers Taken, Skipped and Snooze", "UX-07 today's due dose gets a neutral local reminder" (ar, fr) | PRD §5.3 states "reminders are scheduled locally" and "Taken / Skipped / Snooze" word for word. The bug run finds 2 buttons where 3 are expected, and nothing scheduled. A patient on medication is never reminded. Related: question API-17. |
| **SEC-06** | high | A doctor reading a patient's clinical data writes no audit row | backend/app/routers/staff_recovery.py:57, addiction_checks.py:254, habits.py:232, medications.py:155 | test_qa_recovery_isolation.py::test_a_doctor_reading_clinical_data_is_audited | PRD §8.3: "Audit log of who viewed or changed patient data". `--runxfail` gives `assert (2 - 2) >= 5`. The platform already audits identity views (`identity.viewed`, `selfie.viewed` in staff_identity.py), so recovery reads are the gap. Kept at high: it fails on every clinical read, not in an edge case, and with SEC-02 open a second doctor's reads leave no trace. |
| **API-01** (+API-03) | medium | Checks, habits and v1 ticks use the UTC date, not the Algiers day: the edit lock, the week strip, the doctor's chart and the habit summary all lose the hour from 00:00 to 01:00 in Algiers | addiction_checks.py:108-109, :158 (lock), :196 (week strip), :267/:275 (chart); habits.py:241-248; checkins.py:31-32 | test_qa_recovery_rules.py::test_a_check_saved_after_midnight_in_algiers_stays_editable_that_day (409 check_locked), ::test_adding_an_addiction_after_midnight_in_algiers_keeps_yesterday_done (`[] == ['2026-10-17']`), ::test_the_doctor_sees_the_patients_day_right_after_midnight_in_algiers (`[] == ['2026-10-18']`) | PRD §5.6 says "editable the same day", and §4.3 displays every time in Africa/Algiers. The code is also inconsistent with itself: the check `day` is the phone's (Algiers) day, but it is compared with UTC dates, while doses, the quote and the alert jobs use `clinic_today`. Merged because one fix (clinic day) covers both. Medium: one hour a day. |
| API-09 | medium | The doctor cannot record triggers or a severity level per addiction | backend/app/models.py:393-426; staff_recovery.py (confirm/reject only) | test_qa_recovery_rules.py::test_the_doctor_records_triggers_and_severity | PRD §3: "triggers noted by the doctor, severity level", and "adds triggers and severity". §9 Addiction lists both fields. Not built. |
| API-10 | medium | The doctor cannot see medication adherence | medications.py:155-167; no staff route reads `DoseLog` | test_qa_recovery_rules.py::test_the_doctor_reads_medication_adherence | PRD §7, Patient file: "medication adherence". Probing every staff GET under the patient finds no "taken". |
| API-13 | medium | Nobody can manage the quote library | backend/app/main.py:44-62 (no quote router); quotes come from quotes_seed.py only | test_qa_recovery_rules.py::test_the_quote_library_is_managed_from_the_dashboard | PRD §5.2: "Library managed by the super admin; doctors can add their own". Also §3 and §7. |
| API-14 | medium | The doctor can correct only the profile, not the clean-since date, the substance or a generic type | addiction_checks.py:231-251; staff_recovery.py:93-112 | test_qa_recovery_rules.py::test_the_doctor_corrects_the_patients_entry | PRD §3: the patient enters "substance profile or type, substance, clean since date", and "The doctor can correct it". `--runxfail` shows only PUT /profile exists, and nothing changes. A mistyped start date can never be fixed. Which fields exactly is still G-09. |
| ALERT-01 | medium | A high-craving day saved after its nightly run never completes a `craving_high` run | backend/app/alerts_job.py:79-84, :112-127; addiction_checks.py:143 | test_qa_recovery_alerts.py::test_a_check_saved_after_the_nightly_run_still_completes_three_high_days | PRD §5.6: "craving 4 or more on 3 days in a row". 10-18, 10-19 and 10-20 qualify, but each run reads only its three days (`0 == 1`). Edge case: a late save, for example a screen opened before midnight (recovery_screen.dart:245). |
| ALERT-02 | medium | Deleting the account does not notify the doctor | backend/app/routers/me.py:65 (TODO) | test_qa_recovery_alerts.py::test_the_doctor_is_told_when_a_patient_deletes_their_account | PRD §12.5 step 2, word for word. By the guide this would be high ("alert never raised"). Kept at medium because §12.5 is outside this run's sections. Not reported by the booking QA. |
| SEC-08 | medium | Screenshots are not blocked on any screen | apps/mobile/android/app/src/main/kotlin/dz/benmahdia/benmahdia_mobile/MainActivity.kt:5 | static: my own grep for FLAG_SECURE, ScreenProtector, screenshot and secure_screen in mobile lib, android, ios and pubspec finds nothing | PRD §8.3: "screenshot blocking on sensitive screens". Accepted without a test because nothing exists to call (booking precedent: API-07, UX-11). |
| UX-01 | medium | Every server refusal on a recovery save reads "check your connection", and a lock on a dose answer or a relapse shows nothing | apps/mobile/lib/features/recovery/api_recovery_repository.dart:56-61; recovery_screen.dart:187-196, :212-222 | qa_recovery_flow_test.dart group "every refusal from the recovery API is explained" (36 tests) | A missing error state is medium per the guide. Same pattern as booking UX-04. Bug run: 32 tests find the connection message; 4 find no locked state. Reachable in the app: an addiction added today, then a relapse "yesterday", gives `relapse_before_start`. The wording is Q-UX-2. |
| UX-03 | medium | Dashboard: a failed confirm/reject, "mark read" or medicine "stop" gives the doctor no message | apps/dashboard/src/pages/PatientDetail.tsx:79-88, :244-254; Alerts.tsx:26-37 (`catch { reload(); }`) | qa-recovery.test.tsx "feedback when the server refuses a change (UX-03)" ×3 | A missing error state; the profile change and the prescription already show `role="alert"`. Bug run: `Unable to find role="alert"` ×3. |
| UX-05 | medium | The counter shows days only, not "days (and hours)" | recovery_widgets.dart:91-96; widgets/sobriety_ring.dart | qa_recovery_flow_test.dart "UX-05 the counter shows days and hours" (ar, fr) | PRD §5.1, word for word. The API keeps the hour (API test passes); the app drops it. Medium: the PRD puts hours in brackets. |
| UX-06 | medium | Reaching the 4-week small goal is not celebrated | recovery_screen.dart:114-140 (milestones only) | qa_recovery_flow_test.dart "UX-06 reaching the 4-week goal is celebrated" (ar, fr) | PRD §5.6: "Goal reached → celebration". Steps 1, 3, 7 and 14 coincide with milestones; 28 does not, because the next milestone is 30. |
| UX-08 | medium | A screen reader cannot activate the 1–5 ratings, the habit tick, the clean-since date, the relapse time or the habit reminder | tracking_widgets.dart:120-125, :471-481; addiction_form_screen.dart:156-160; recovery_widgets.dart:330-334 (`Semantics(button: true, excludeSemantics: true)` with no `onTap`) | qa_recovery_flow_test.dart group "screen readers and tap targets" › UX-08 ×5 | A control that announces itself as a button but exposes no tap action is a defect in what was built. PRD §8.6 covers accessibility. Bug run: "missing actions: [tap]". Checked in widget semantics only, not on a device; iOS VoiceOver may fall back to a simulated touch. |
| UX-11 | medium | The milestone celebration does not scroll, so Continue falls off a small screen at two years of badges | apps/mobile/lib/features/recovery/milestone_screen.dart:53-118 | qa_recovery_flow_test.dart "UX-11 two years of badges" (320×568 ar/fr, 360×640 fr) | Overflows by 98, 124 and 52 px. Edge case (a streak of 2+ years), so medium. |
| UX-16 | medium | The PRD §7 doctor views are not built: streak history chart, patient-list filters, mobile doctor view | PatientDetail.tsx; Patients.tsx:18; backend/app/routers/staff.py:67-72 | static (nothing to call) | PRD §7, word for word. Not built. |
| API-06 | low | The HH:MM check accepts a trailing newline and non-ASCII digits | checkins.py:28; medications.py:39; habits.py imports the same pattern | test_qa_recovery_rules.py::test_reminder_times_are_plain_ascii_hh_mm["21:30\n" \| "1١:3٠"] | 200 on SQLite. On my PostgreSQL run, `"21:30\n"` is a 500 (`StringDataRightTruncation`, varchar(5)). The app always sends ASCII, so low. |
| API-11 | low | The doctor can prescribe and stop a medicine, but not edit its schedule | medications.py:127, :170 (no PUT/PATCH) | test_qa_recovery_rules.py::test_the_doctor_can_edit_a_schedule | PRD §7: "create and edit schedules". Workaround: stop and re-prescribe (see API-19). |
| API-12 | low | The quote of the day ignores the recovery stage | models.py:569-580; medications.py:301-323 | test_qa_recovery_rules.py::test_the_quote_is_chosen_by_recovery_stage | PRD §5.2: "chosen by addiction type and recovery stage"; §9 lists Quote.stage. What a "stage" is remains G-13. |
| ALERT-03 | low | `no_checkin` ignores checks on an addiction added in the last 3 days | alerts_job.py:134-143 | test_qa_recovery_alerts.py::test_checks_on_a_newly_added_addiction_count_as_daily_checks | The patient did a daily check on 2 of the 3 days, yet the alert fires (`1 == 0`). This contradicts the job's own rule: a check on any older addiction counts (passing test). Only reachable through the API, because the app saves every addiction together. The definition is question Q-05. |
| UX-02 | low | The relapse note and the exact substance have no length limit, though the server caps them at 500/100 | recovery_widgets.dart:351-356; addiction_form_screen.dart:145-152 | qa_recovery_flow_test.dart "UX-02 …" ×4 | The client and the server disagree. The 422 then shows as a connection error (UX-01). The limits themselves are G-14. |
| UX-04 | low | A double tap sends two requests on Taken, the day tick, the habit tick, habit remove and stop reminder | recovery_screen.dart:198-204, :232-240, :324-336, :350-363, :396-404 | qa_recovery_flow_test.dart group "a double tap sends one request" ×5 | `Expected <1>, Actual <2>`. A second remove gets a 404, which shows as "check your connection". The two requests can also hit SEC-07's race on the tick and the dose. |
| UX-09 | low | The 1–5 rating circles are below 48×48 | tracking_widgets.dart:125-141 (`height: 44`) | qa_recovery_flow_test.dart "UX-09 daily check: each 1-5 rating is at least 48×48" | PRD §8.6: "Large tap targets". 41.6×44 at 320 px; the height is 44 at any width. |
| UX-10 | low | The "pills" type is "hallucinogenic pills" in Arabic, and its name differs between the app and the dashboard | apps/mobile/lib/l10n/app_ar.arb:503; app_fr.arb:333; apps/dashboard/src/i18n.tsx:106, :286 | qa_recovery_flow_test.dart "UX-10 …" | PRD §3: "psychotropic pills". Strings confirmed. |
| UX-12 | low | The next-visit date tile clips the French month at 1.3× text | recovery_widgets.dart:574-597 (fixed 52×56) | qa_recovery_flow_test.dart "UX-12 1.3× text, 360 wide: nothing overflows" (fr) | Overflows by 16 px. |
| UX-13 | low | Cairo and Inter are not bundled, so the app falls back to system fonts | apps/mobile/pubspec.yaml (`flutter:` has no `fonts:` and no assets; no google_fonts) | static | DESIGN §2 names Cairo and Inter. App-wide. |
| UX-14 | low | Dashboard Arabic day counts are not pluralised ("9 يوم") | apps/dashboard/src/i18n.tsx:135 | qa-recovery.test.tsx "UX-14 …" | `expected '9 يوم' to be '9 أيام'`. |
| UX-15 | low | Off-token values in the recovery screens | recovery_widgets.dart:213 (`AppSpace.xs + 2`), :336/:694 (`Size(0, 44)` vs DESIGN §7 height 52), :589, :853; tracking_widgets.dart:134; Tracking.tsx:133-200; Alerts.tsx:54 | static grep (my re-run matches) | CLAUDE.md requires tokens only. Same class as booking UX-12. |
| UX-17 | low | Quote favourites and "share as an image" are not built | recovery_widgets.dart:790-830 (`QuoteCard`) | static | PRD §5.2, word for word. |

## Carried (known, not new)

| ID | What this run adds | Tests (xfail, each fails as stated) |
|---|---|---|
| SEC-02 (known open question; G-01) | Any doctor with a non-hold booking reads all 5 clinical read routes, including a **cancelled-only** booking (R-85) and a **future confirmed** one. That doctor can also stop the prescriber's medicine. Relapse, craving_high and milestone alerts go to the latest-starting booking's doctor, while missed_doses goes to the prescriber (R-100). API-07's "doctor keeps the file" and ALERT's two SEC-02 tests fold in here. | test_qa_recovery_isolation.py::test_sec02_two_paid_doctors_do_not_both_read_recovery_data, ::test_sec02_second_doctor_cannot_stop_another_doctors_prescription, ::test_sec02_a_cancelled_booking_opens_no_clinical_data, ::test_sec02_a_relapse_alert_stays_with_the_patients_doctor[cancelled\|confirmed]; test_qa_recovery_alerts.py::test_a_doctor_the_patient_cancelled_with_gets_no_alerts, ::test_one_patients_alerts_reach_one_doctor |
| SEC-04 (booking QA) | There is no clinic-staff role. "Staff never see clinical data" holds only by absence. A super admin without a DoctorProfile gets 403 on every staff recovery route (passing test). | test_qa_booking_isolation.py::test_a_clinic_staff_role_exists |

## Questions (PRD silent; not bugs until you decide)

| ID(s) | Question | Pinned by (passing test unless noted) |
|---|---|---|
| API-02 (was a medium bug) | At 19:00 in Algiers the API accepts an answer about **tomorrow**: the +1 day exists for the UTC offset. That answer is then locked on its own day. Should a check about tomorrow be accepted at all? Does "editable the same day" mean the day answered or the day given? The app sends the phone's today, so only a wrong phone clock or another client reaches this. | test_qa_recovery_rules.py::test_a_check_given_ahead_can_still_be_corrected_on_its_day (xfail; keep it or drop it once decided) |
| API-07, ALERT Q-03, R-08 (booking API-Q7) | A paid visit cancelled later locks recovery again. The doctor keeps the file, can still prescribe, and missed_doses alerts keep firing for doses the patient cannot answer. Should a once-paid patient keep tracking? (G-02) | test_question_a_paid_visit_cancelled_later_locks_recovery_again; test_question_a_patient_locked_again_still_raises_missed_doses |
| API-08, ALERT Q-04 | A rejected addiction still takes relapses (with a high alert), goals and milestone-seen, uses a slot of the 10, and still picks the quote's type. Pending addictions raise craving_high and milestone before review. (G-07) | test_question_a_rejected_addiction_still_takes_relapses_goals_and_a_slot, test_question_a_rejected_addiction_still_picks_the_quote, test_question_a_relapse_on_a_rejected_addiction_still_alerts, test_question_a_pending_addiction_raises_alerts_before_review |
| API-15 | Two "I relapsed" seconds apart are two relapses and two high alerts (8 parallel gave 8 and 8 on PostgreSQL). One event or two? The app's button sends one request. | test_question_a_double_tap_on_i_relapsed_logs_two_relapses |
| API-16 | After day 28 no other goal step can be chosen (60/90/180/365 are refused). Does "choose a different step" include the milestone ladder steps? (G-10) | test_question_after_four_weeks_no_other_step_can_be_chosen |
| API-17 | Is Snooze local only (how long; is it synced)? The server keeps taken/skipped only, matching §9 DoseLog. (G-11; the missing button is UX-07) | test_question_snooze_is_not_an_answer_the_server_keeps |
| API-18 | A dose can be answered "taken" for tomorrow, which counts against missed_doses. (G-04) | test_question_a_dose_can_be_answered_for_tomorrow |
| API-19 | A stopped medicine disappears from the patient's past days, though the answers stay stored. (R-73) | test_question_a_stopped_medicine_leaves_the_patients_past_days |
| API-20 | Is "a note or trigger" one free-text field? A `trigger` field is dropped silently. (G-08) | test_question_a_relapse_has_no_trigger_apart_from_its_note |
| ALERT Q-01, Q-02 | What does "missed doses on 2+ days" mean: is "skipped" a miss; does one dose of two taken clear the day; do days before the course was entered count? (G-04) | test_question_skipped_doses_count_as_missed, test_question_one_dose_of_two_taken_clears_the_day, test_question_days_before_the_course_was_entered_count_as_missed |
| ALERT Q-05 | With several addictions, is a "daily check" for `no_checkin` any addiction checked (as the job does) or every one (as the week strip does)? This decides the ALERT-03 fix. | test_a_check_on_one_of_two_addictions_counts_as_the_days_check |
| ALERT Q-06 (G-12) | Should nightly alerts stop for an account in its deletion grace period? They continue today, while its file is 404. | test_question_nightly_alerts_continue_for_a_deleted_account |
| ALERT Q-07 (G-06) | Should a patient with no addiction (v1 ticks only) ever get `no_checkin`? Today never. | test_question_a_patient_with_no_addiction_never_gets_no_checkin |
| ALERT Q-08 (G-18) | Is newest-first acceptable in the inbox until AI crisis flags exist (PRD: "crisis flags, highest priority")? | test_question_inbox_lists_newest_first_not_by_priority |
| ALERT Q-09 (G-05) | Repeats: missed_doses repeats daily, and craving_high/no_checkin every 3 days. Is that the wanted cadence? | test_every_job_twice_the_same_night_then_the_next_night and others |
| Q-UX-1 (G-03) | Recovery shows dates in the phone's zone, while reminders and booking use Africa/Algiers. Which one? | not testable here (machine zone = UTC+1) |
| Q-UX-2 | Exact wording for each refusal code (needed for the UX-01 fix). | — |
| Q-UX-3 | The dashboard's 30-day chart is forced left-to-right in Arabic, while DESIGN §9 says "mirror layout". Is that intended? | — |
| Q-UX-4 | After answering "No" (used), may the patient cancel the relapse sheet? Today the check stays "used" and no relapse is logged. | — |

## Test runs (verifier, 2026-10-30)

| Suite | Command | Result |
|---|---|---|
| New backend set, SQLite | `cd backend && .venv/Scripts/python.exe -m pytest tests/test_qa_recovery_rules.py tests/test_qa_recovery_isolation.py tests/test_qa_recovery_alerts.py -q` (run with `-o addopts=""` so the summary line prints) | **138 passed, 3 skipped, 30 xfailed** in 111.6 s. The 3 skips are the PostgreSQL-only tests. Per file: rules 73 passed, 2 skipped, 17 xfailed; isolation 26 passed, 1 skipped, 7 xfailed; alerts 39 passed, 6 xfailed. |
| xfail reasons | same files, `--runxfail` | All 30 fail on their own assert: rules 17, isolation 7 (plus the PostgreSQL one), alerts 6. |
| PostgreSQL-only tests | throwaway `postgres:16-alpine` on 127.0.0.1:55433 (container `qa-recovery-verify-pg`, removed after use; the shared `benmahdia-db-1` was not touched). `-k "plain_ascii or parallel or double_tap or failed_check_save or simultaneous"` | **2 passed, 10 xfailed.** Save codes `{204: 135, 500: 86, 200: 19}` and `{204: 149, 500: 77, 200: 14}`, with one row per key. `--runxfail`: `StringDataRightTruncation` for `"21:30\n"`, and `UniqueViolation` whose parameters include craving and signals. |
| SEC-07 live log probe | scratch script: the real app under `uvicorn.Server`, with the race injected | `500`. uvicorn's stderr shows "Exception in ASGI application" and the line `[parameters: (…, 1, 5, '{"irritability": 4, "restlessness": 5}', …)]`. |
| Mobile | `cd apps/mobile && flutter test test/qa_recovery_flow_test.dart test/qa_recovery_privacy_test.dart --no-pub` | **87 passed, 64 skipped, exit 0.** Passed: 77 flow and 10 privacy. Skipped: the QA UX-NN bug groups. |
| Mobile bug run | `flutter test test/qa_recovery_flow_test.dart --no-pub --dart-define=QA_RUN_BUGS=true` | **77 passed, 64 failed.** All 64 failures are the bug tests, each for its stated reason: UX-01 ×36, UX-08 ×5, UX-04 ×5, UX-07 ×4, UX-02 ×4, UX-11 ×3, UX-05 ×2, UX-06 ×2, UX-09, UX-10, UX-12. |
| Dashboard | `cd apps/dashboard && npx vitest run src/test/qa-recovery` | **24 passed (24)**, including 4 `it.fails`. With `QA_RUN_BUGS=true`: 4 failed (`Unable to find role="alert"` ×3, `'9 يوم'` vs `'9 أيام'`) and 20 passed. Whole dashboard suite: 7 files, 114 passed. |
| Full backend, SQLite | `cd backend && .venv/Scripts/python.exe -m pytest -q -p no:randomly` (with `-rfX --junitxml` for the counts) | **1 failed, 617 passed, 50 skipped, 38 xfailed** in 437 s, no XPASS. The only failure is the pre-existing `tests/test_identity.py::test_nothing_readable_is_stored`. Baseline was 1 failed, 479 passed, 47 skipped, 8 xfailed. The difference is exactly the three QA files (+138 passed, +3 skipped, +30 xfailed), so the team broke nothing. |

## Rule coverage

rules.md has 130 rules (R-01 to R-130). Before the run, 92 had at least one test and 38 had none.

**124 of 130 now have at least one test** (pass, xfail, or a Flutter/vitest bug test). 32 of the 38 uncovered rules gained a test.

Still without a test:
- **R-80:** favourites and share, not built; static only.
- **R-97:** screenshot blocking; grep only (SEC-08).
- **R-120:** streak history chart, not built.
- **R-122:** mobile doctor view, not built.
- **R-123:** transfer or share a patient, not built; SEC-02 family.
- **R-129:** design tokens; static grep only (UX-13, UX-15).

## PRD gaps that need you

1. **Primary doctor, sharing and transfer (SEC-02, G-01).** Which doctor owns clinical access and which receives each alert kind? Can a doctor stop another doctor's prescription?
2. **Cancel after a paid visit (G-02).** Should recovery lock again? Should the doctor keep access, and should alerts continue?
3. **Whose "day" (G-03).** Confirm that checks, habits, ticks, the edit lock and the 30-day views follow the Algiers day; this sets the API-01 fix. Should an answer about tomorrow be accepted (API-02, API-18)? Should the app show Algiers time or the phone's (Q-UX-1)?
4. **"Missed doses for 2+ days" (G-04).** Does skipped count? Does a partial day count? Do days before the course was entered count?
5. **Alert repeats (G-05)** and the inbox order before crisis flags exist (G-18).
6. **A "daily check" with several addictions,** for `no_checkin` (Q-05). Also: `no_checkin` for patients with no addiction (G-06).
7. **Pending and rejected addictions (G-07).** Alerts before review? Relapses, goals and the quote on a rejected one?
8. **Relapse "note or trigger" (G-08),** and which fields the doctor may correct (G-09).
9. **Small-goal choices after day 28 (G-10).**
10. **Medications (G-11):** Snooze behaviour; editing a schedule versus stop-and-recreate; whether a stopped course stays in the patient's history (API-19).
11. **Alerts for deleted or locked-again accounts (G-12).**
12. **Quotes (G-13):** what a "recovery stage" is; who adds, edits and deactivates quotes.
13. **Limits the PRD does not state (G-14):** 10 addictions, a 500-character note, 60-character habit words, 6 dose times, 90 chart days.
14. **Error wording per refusal code (Q-UX-2),** the dashboard chart direction in Arabic (Q-UX-3), and cancelling the relapse sheet after "No" (Q-UX-4).
15. **Smaller confirmations:** the doctor sees a custom habit's own words (G-19); where to say that buprenorphine or pregabalin taken as prescribed is not use (G-17); a double "I relapsed" (API-15).

## Not run

- **Full Flutter suite:** only the two QA files ran. The whole dashboard suite did run (114 passed).
- **Real devices:**
  - No TalkBack or VoiceOver run. UX-08 was checked through widget semantics only.
  - No real Android notifications. The reminder texts were checked through a fake service.
  - No FLAG_SECURE check on a device. SEC-08 was checked by grep only.
- **Mobile time-zone behaviour (Q-UX-1):** not exercised. The machine zone equals Algiers.
- **Alerts tests on PostgreSQL:** not run. They are plain selects and inserts; the races are covered by SEC-07's PostgreSQL runs.
- **SEC-07 log probe:** used the in-memory SQLite engine. The PostgreSQL error text with the answers was seen in pytest, not through uvicorn.
