# Recovery rules checklist — 2026-10-26

Written by the rules-extractor. No tests written here. Sources: `docs/PRD.md` §3 (roles, multi-doctor rules, addiction and substance profiles), §5 intro (unlock), §5.1, §5.2, §5.3, §5.4, §5.6, §7, §8.3, §8.6, §12.3, and `docs/DESIGN.md`.

**Code read at:** `c772566` (start and end of extraction). Working tree: the preflight (`preflight-git-status.txt`) showed `M apps/dashboard/src/i18n.tsx`, `M apps/dashboard/src/pages/Alerts.tsx` and `M apps/dashboard/src/test/booking-alerts.test.tsx` from another session. When I re-checked, those files were clean and HEAD had not moved. The dashboard alert labels quoted below match HEAD.

**Out of scope** (do not test): booking/payments (QA 2026-10-25), articles (§5.5), the AI companion (§6, not built: no "supportive check-in" after a relapse, no AI flags).

**Known open question (carry it, do not re-report):** **SEC-02**. No primary-doctor field exists. `_own_patient` (`backend/app/routers/medications.py:110-124`) counts any non-`awaiting_payment` appointment with a doctor (including **cancelled**, **future** and **completed** ones) as "own patient". `_doctor_of` (`backend/app/routers/recovery.py:270-282`) picks the doctor with the **latest-starting** non-hold appointment as the alert recipient. Existing xfail: `backend/tests/test_qa_booking_isolation.py::test_one_booking_with_another_doctor_does_not_open_clinical_data`. Also carried: **SEC-04**, no clinic-staff role (`test_a_clinic_staff_role_exists`, xfail).

## How to read the columns

- **Enforced at**: file:line of the code that enforces the rule. `not found` means no code enforces it. `partial` means the note says what is missing. `by absence` means the rule holds because no route exists that could break it.
- **Covered by**: an existing test. `uncovered` means no test checks it. `partial` means a test exists but misses the edge named in the note.
- **Area**: api, security, alerts or ux.
- **Code shorthands**:
  - `rec` = `backend/app/routers/recovery.py`
  - `chk` = `backend/app/routers/addiction_checks.py`
  - `med` = `backend/app/routers/medications.py`
  - `hab` = `backend/app/routers/habits.py`
  - `srec` = `backend/app/routers/staff_recovery.py`
  - `staff` = `backend/app/routers/staff.py`
  - `cin` = `backend/app/routers/checkins.py`
  - `deps` = `backend/app/deps.py`
  - `sub` = `backend/app/substances.py`
  - `aj` = `backend/app/alerts_job.py`
  - `jobs` = `backend/app/jobs.py`
  - `models` = `backend/app/models.py`
  - `m/` = `apps/mobile/lib/`
  - `d/` = `apps/dashboard/src/`
- **Backend test shorthands** (all in `backend/tests/`):
  - `t_rec` = `test_recovery.py`
  - `t_srec` = `test_staff_recovery.py`
  - `t_med` = `test_medications.py`
  - `t_sub` = `test_substance_tracking.py`
  - `t_gh` = `test_goals_habits.py`
  - `t_jobs` = `test_jobs.py`
  - `t_ms` = `test_milestones.py`
  - `t_cin` = `test_checkins.py`
  - `t_staff` = `test_staff.py`
  - `t_iso` = `test_qa_booking_isolation.py`
- **Mobile test shorthands** (all in `apps/mobile/test/`):
  - `m_rem` = `recovery_reminders_test.dart`
  - `m_ring` = `sobriety_ring_test.dart`
  - `m_sub` = `substance_tracking_test.dart`
  - `m_rapi` = `api_recovery_repository_test.dart`
  - `m_tapi` = `api_tracking_repository_test.dart`
  - `m_home` = `home_test.dart`
  - `m_ln` = `local_notifications_test.dart`
  - `m_ms` = `milestone_test.dart`
- **Dashboard test shorthands** (all in `apps/dashboard/src/test/`):
  - `d_rec` = `recovery.test.tsx`
  - `d_trk` = `tracking.test.tsx`
  - `d_ba` = `booking-alerts.test.tsx`
  - `d_dash` = `dashboard.test.tsx`
- **Test fixtures:**
  - The clock is frozen at **2026-10-17 18:00 UTC**, which is 19:00 in Algiers (`backend/tests/conftest.py:28`).
  - Helpers to reuse:
    - `booking_helpers.make_doctor`, `add_appointment` and `verified_patient`
    - `test_recovery.unlocked`
    - `test_medications.linked_patient`, `staff_session` and `prescribe`
    - `test_substance_tracking.setup`, `add`, `check` and `later` (`later` advances the clock and refreshes tokens)
    - `test_staff.other_doctor` and `login`
    - `conftest.advance`

---

## 1. Unlock (PRD §5 intro, §2 non-goals, §12.1 step 6)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-01 | Every patient recovery route answers `403 recovery_locked` until the patient has an unlocking appointment. This covers addictions, relapses, goal, milestone-seen, profiles, per-addiction checks, v1 ticks, reminder, habits, doses and quote. | §5 Unlock | `deps:48-61` (`recovery_patient`). Every `/v1/me` recovery router depends on it (`rec:42` alias `patient`). | partial. Covered: t_sub::test_every_patient_recovery_route_is_locked_before_a_paid_visit (doses GET/PUT, quote, checkins GET/PUT, reminder GET/PUT, addiction-checks, check PUT), t_rec::test_locked_until_the_first_confirmed_appointment, t_rec::test_relapse_is_locked_before_the_first_confirmed_appointment, t_gh::test_goal_is_own_and_locked, t_gh::test_habits_are_locked_and_patient_only (list, catalog, POST), t_sub::test_profiles_need_an_unlocked_patient. **Uncovered:** POST `…/milestone/seen`, PUT `habits/{id}/reminder`, PUT/DELETE `habits/{id}/days/{day}`, DELETE `habits/{id}`. | api |
| R-02 | An unpaid hold (`awaiting_payment`) or a cancelled appointment does not unlock. | §5 Unlock | `deps:45` (`_UNLOCKING`) | t_rec::test_locked_until_the_first_confirmed_appointment | api |
| R-03 | `completed` and `no_show` appointments keep recovery unlocked ("a paid visit stays paid"). | §5 (implied) | `deps:45` | uncovered (every test unlocks with `confirmed`) | api |
| R-04 | Unlock needs a confirmed appointment, not the clinic's ID approval. | §5, §12.1 | `deps:48-61` (no `User.status` check) | t_rec::test_unverified_patient_can_track | api |
| R-05 | A paid appointment that is later cancelled re-locks every recovery route. The data stays but the patient cannot reach it. | none (question): PRD says "unlock after the first appointment is confirmed" and is silent on a later cancel or refund | `deps:45` (cancelled is not in `_UNLOCKING`) | uncovered | api |
| R-06 | A doctor or super-admin token on a patient recovery route gets `403 forbidden`, not `recovery_locked` and not data. | §8.3 | `deps:52-53` | t_rec::test_staff_cannot_use_patient_routes, t_sub::test_staff_cannot_use_patient_routes, t_cin::test_staff_cannot_use_patient_routes, t_med::test_patient_role_check, t_gh::test_habits_are_locked_and_patient_only | security |
| R-07 | The app maps `403 recovery_locked` to a locked Recovery tab with a Book button. Any other 403 is "unavailable". | §5 Unlock | `m/features/recovery/api_recovery_repository.dart:56-58`, `m/features/recovery/recovery_screen.dart:455-458` (`RecoveryLockedView`) | m_sub "locked until the first paid visit, with a way to book"; m_tapi group `lock` (both tests) | ux |
| R-08 | Lock state and doctor access disagree. A doctor can still prescribe to a patient whose recovery is locked again (for example, only a cancelled appointment). The patient then cannot answer doses, so `missed_doses` alerts are certain. | none (question) | `med:110-124` (cancelled counts, see SEC-02) vs `deps:45` | uncovered | alerts |

## 2. Addictions, review, relapse (PRD §3, §5.1, §12.3)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-09 | The patient enters an addiction by substance profile or by type. A profile implies its type. A contradicting type, or neither field, returns 422. An unknown profile returns 422. | §3 | `rec:52-82` (`AddictionIn`, `type_for`) | t_sub::test_profile_sets_the_type, test_profile_and_type_must_agree, test_generic_addiction_has_no_profile | api |
| R-10 | Profile-to-type mapping: nicotine→tobacco, thc→cannabis, pregabalin→pills, buprenorphine→opioids, cocaine→stimulants, amphetamines→stimulants. | §3 | `sub:70-87` | partial: t_sub::test_profiles_catalog (cocaine, amphetamines, buprenorphine), test_profile_sets_the_type (pregabalin). nicotine→tobacco and thc→cannabis are uncovered. | api |
| R-11 | The exact substance in the patient's words is optional, trimmed and at most 100 characters. | §3 | `rec:57-64` | t_rec::test_substance_is_optional_and_trimmed, test_rejects_bad_input | api |
| R-12 | "Clean since" cannot be in the future (5 min clock slack). | §3 | `rec:171-173` | t_rec::test_rejects_bad_input | api |
| R-13 | At most 10 active addictions per patient (`409 too_many_addictions`). | none (question): code limit, PRD silent | `rec:35`, `rec:174-180` | t_rec::test_limit_of_addictions | api |
| R-14 | A new addiction is `pending` ("waiting for the doctor's review") and the app shows that state. | §3 | `models:420-422` default; `rec:181-187` | t_rec::test_add_and_list; m_home "the patient adds an addiction, pending review"; m_rapi "lists the addictions with their counters and review state" | api |
| R-15 | The doctor confirms or rejects an addiction. The decision records `reviewed_at`/`reviewed_by` and is audited with the row id only. The doctor can change their mind. | §3 | `srec:72-112` (audit `srec:87`) | t_srec::test_doctor_reads_and_confirms_addictions, test_rejected_addiction_leaves_the_patients_list; the audit row content is uncovered | api |
| R-16 | A rejected addiction leaves the patient's list, the daily check, the week strip and the alerts job. The doctor still sees it. | §3 (implied) | `rec:155`, `chk:118`, `chk:141-142`, `aj:106-109` | partial: t_srec::test_rejected_addiction_leaves_the_patients_list, t_sub::test_rejected_addiction_cannot_be_checked. **Gap:** `rec:139-143` (`_own`) ignores `review_status`, so relapse (which raises an alert), goal and milestone-seen still work on a rejected addiction. The quote also uses rejected types (`med:307-311`). Uncovered. | api |
| R-17 | The doctor can correct the patient's entry (type, substance, clean-since date). | §3 ("The doctor can correct it") | partial: only the profile can be corrected (`chk:231-251`). No route corrects the type without a profile, the substance or clean_since. | partial: t_sub::test_doctor_corrects_the_profile (profile only) | api |
| R-18 | The doctor adds triggers and a severity level per addiction. | §3, §9 Addiction | not found: no `triggers`/`severity` column (`models:393-426`), no route | uncovered | api |
| R-19 | After review, only a relapse moves the counter. No route lets the patient or a doctor edit `clean_since`. | §3 | by absence: no PUT/PATCH on `/v1/me/addictions/{id}` or on the staff addiction (besides `/profile`) | uncovered (no test that PUT/PATCH `/v1/me/addictions/{id}` is 405/404) | security |
| R-20 | The patient cannot delete relapse history or an addiction. There is no DELETE under `/v1/me/addictions/*`, and a relapse is an append-only row. | §3 "Cannot do" | by absence (`rec` has no delete); `Relapse` rows are never deleted by app code | uncovered (no negative DELETE test) | security |
| R-21 | Relapse body: `at` is optional (defaults to now); `note` is optional, trimmed and at most 500 characters. `at` in the future returns `422 relapse_in_future`; `at` before the current start returns `422 relapse_before_start`. | §5.1, §3 | `rec:85-95`, `rec:207-213` | t_rec::test_relapse_defaults_to_now, test_relapse_time_checks | api |
| R-22 | A relapse restarts the counter at `at` and keeps the longest streak and the total sober days (`past_days += streak`; `longest = max`). | §5.1, §12.3 | `rec:214-217` | t_rec::test_relapse_restarts_counter_and_keeps_history; m_home "a relapse keeps the longest streak and the total" and "a relapse restarts the counter but keeps the past" | api |
| R-23 | The patient can add "a note or trigger" when logging a relapse. | §5.1 | partial: only `note` (`rec:88`), no trigger field | uncovered (see PRD gap G-08) | api |
| R-24 | A relapse puts the small goal back to automatic (1 day) and starts a new milestone ladder (`milestone_seen` and `milestone_alerted` go back to 0). | §5.6, §5.1 | `rec:218-219` | t_gh::test_relapse_resets_the_goal_to_one_day, t_ms::test_a_relapse_starts_a_new_ladder, t_ms::test_the_doctor_is_told_once_per_milestone | api |
| R-25 | In the daily check, `used = true` does not restart the counter by itself. The app opens relapse logging instead. | §5.6 step 1 | `chk:137-139` (no counter change) | t_sub::test_used_does_not_restart_the_counter_by_itself; m_sub '"used" in the daily check opens relapse logging' | api |
| R-26 | Relapse wording is supportive and never judgmental, in AR and FR. | §5.1 | `m/l10n/app_ar.arb`, `m/l10n/app_fr.arb` | partial: m_home relapse widget test (AR strings only). FR is uncovered. | ux |
| R-27 | The counter shows days **and hours** since the sobriety start. | §5.1 | partial: the ring shows days only (`m/widgets/sobriety_ring.dart:21`, `m/features/recovery/recovery_widgets.dart:91-96`). Hours were not found. | m_ring (days only) | ux |
| R-28 | The app shows the longest streak (counting the current one) and the total sober days (past plus current). | §5.1 | `m/features/recovery/recovery_models.dart:227-232` | m_home group "milestones", "a relapse keeps the longest streak and the total" | ux |

## 3. Milestones (PRD §5.1, §5.6)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-29 | Milestone ladder: 1, 3, 7, 14, 30, 60, 90, 180, 365 days, then every year. | §5.1 | `sub:102-109`; `m/features/recovery/recovery_models.dart` | t_ms::test_ladder_then_every_year; m_home "the next milestone follows PRD 5.1, then every year"; m_ms "reached milestones, then every year" | api |
| R-30 | A milestone reached shows a celebration screen and badge **once**. "Seen" is stored server-side so another phone does not show it again. Only the patient can mark it. | §5.1 | `rec:255-267`, `rec:113-114` | t_ms::test_counter_says_which_milestone_to_celebrate, test_only_the_patient_marks_their_milestone_seen; m_ms "shows once, in Arabic, and is remembered", "French wording and the streak's badges", "nothing to celebrate, nothing shown", "the API records the celebration and reads it back" | ux |
| R-31 | `milestone_seen` never goes above the milestone reached now (no pre-marking a future milestone). | §5.1 (implied) | `rec:264` (`max(seen, reached)`) | partial (t_ms happy path only) | api |
| R-32 | Milestone reached → doctor alert `milestone`. One alert per milestone, raised by the nightly job even if the app is never opened. A long-ago start gives one alert for the highest milestone. The alert names no addiction. | §5.1 | `aj:156-173` | t_ms::test_the_doctor_is_told_once_per_milestone, test_the_alert_names_no_addiction | alerts |

## 4. Small goals (PRD §5.6)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-33 | Goal steps: 1 → 3 → 7 → 14 → 28 days, then 60, 90, 180, 365, then every year. The app picks the next step by default. | §5.6 | `sub:97-124` | t_gh::test_goal_ladder, test_automatic_goal_is_the_next_step | api |
| R-34 | The patient can choose a different step, higher or lower, that the current streak has not reached yet. A bad value returns `422 goal_invalid`; `null` means automatic. | §5.6 | `rec:235-252` (only `GOAL_STEPS` 1..28 accepted, `rec:247`) | t_gh::test_patient_picks_a_higher_or_lower_goal, test_goal_must_be_a_step_not_reached_yet | api |
| R-35 | When the chosen goal is reached, the next step is suggested automatically. | §5.6 | `sub:120-124` | t_gh::test_reached_goal_moves_to_the_next_step | api |
| R-36 | Goal reached → celebration. | §5.6 | partial: only milestones are celebrated (`m/features/recovery/milestone_screen.dart`). Reaching the 28-day goal has no matching milestone (30), so no celebration was found. | uncovered | ux |
| R-37 | The circle fills toward the current goal. | §5.6 | `rec:133`; `m/features/recovery/recovery_widgets.dart:91-96` | m_sub "the counter shows the profile, its goal and early note", "the patient picks a higher small goal"; m_tapi "sets and clears the small goal" | ux |
| R-38 | The doctor sees the current small goal per addiction (own patients only). | §5.6 | `srec:47-54` (inherits `goal_days`/`goal`) | t_gh::test_doctor_sees_the_current_goal | api |

## 5. Daily check and reminders (PRD §5.4, §5.6)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-39 | v1 tick "today without use": once a day, idempotent, for a day from today−2 to today+1 (UTC today). | §5.4 | `cin:51-66` | t_cin::test_tick_today_and_list, test_tick_twice_is_fine, test_tick_day_must_be_recent_and_not_in_the_future, test_list_only_returns_the_recent_window | api |
| R-40 | Daily reminder time: `HH:MM` (24 h) or `null`, stored server-side and scheduled by the phone. | §5.4 | `cin:68-95` | t_cin::test_reminder_set_read_and_clear, test_reminder_rejects_bad_times; m_rapi "reads, sets and clears the reminder time"; m_home "the daily reminder can be stopped" | api |
| R-41 | The reminder time picker is 24-hour. | §5.4, §5.6 | `m/features/recovery/recovery_widgets.dart:237-248` (`alwaysUse24HourFormat: true`) | uncovered | ux |
| R-42 | Daily-check reminder text is neutral and names no substance. It is scheduled locally for the next 7 days, only our ids are touched, and turning it off cancels it. | §5.4, §8.3 | `m/features/recovery/recovery_reminders.dart` | partial: m_rem "the daily check for the next seven days, from tomorrow if past", "today still counts when the time is ahead", "turning reminders off cancels ours only", "ids stay clear of the appointment reminders" (FR text only; AR text uncovered) | security |
| R-43 | Per-addiction check: `used` (bool), `craving` 1–5, and **exactly** the profile's two signals rated 1–5 (generic: none). Anything else returns `422 signals_mismatch` (or 422 from validation). | §5.6 | `chk:81-84`, `chk:146-148` | t_sub::test_signals_must_match_the_profile, test_generic_check_rates_craving_only | api |
| R-44 | Signal table per profile: nicotine = irritability, restlessness; THC = sleep, irritability; pregabalin = anxiety, sleep; buprenorphine = discomfort, sleep; cocaine = low_mood, low_energy; amphetamines = sleep, low_appetite. | §5.6 table | `sub:36-87` | partial: t_sub::test_profiles_catalog (exact keys asserted for nicotine only; the five others uncovered); t_sub::test_doctor_corrects_the_profile (cocaine keys) | api |
| R-45 | One answer per addiction per day (unique constraint), editable on the same day it was first saved. The next day it returns `409 check_locked`. | §5.6 | `chk:149-159`; `models:466` | t_sub::test_editable_the_same_day_only | api |
| R-46 | "The same day" means the clinic's (Algiers) day. | §5.6 + §8.6 (question on whose day) | partial: `chk:158` compares the **UTC** date of `created_at` with the UTC date now. A check first saved at 00:30 Algiers (23:30 UTC) locks at 01:00 Algiers. One saved at 23:30 Algiers stays editable until 01:00 the next day. | uncovered | api |
| R-47 | One "today" for all of recovery. | none (question) | not found. The check, habit and tick day windows use UTC today (`chk:108-109`, `hab:87-88`, `cin:31-32`). Doses, quote and alert windows use the clinic day (`med:46-47`, `aj:52`, `aj:82`). | uncovered | api |
| R-48 | A check day must be from today−2 to today+1; otherwise `422 checkin_day_out_of_range`. | §5.6 (implied) | `chk:143-145` | t_sub::test_day_must_be_recent | api |
| R-49 | Week strip: a day is "done" when every active, non-rejected addiction that existed that day was checked. | §5.4 | `chk:191-198` | t_sub::test_day_is_done_when_every_addiction_was_checked, test_save_and_list_a_check; m_home "the daily check per substance fills the week"; m_tapi "reads the checks and the fully checked days" | api |
| R-50 | With at least one addiction, the app's daily check is per addiction: the substance question, craving, two signals, and good habits on the same screen. | §5.4, §5.6 | `m/features/recovery/daily_check_screen.dart` | m_home "the daily check per substance fills the week"; m_sub "the daily check ticks good habits too"; m_tapi "saves a check on its day" | ux |
| R-51 | Each profile has 2–3 "what to expect" notes on early days, in AR and FR, supportive, with no diagnosis. They are placeholders until the clinic approves them. | §5.6 Milestones | `sub:47-87` (3 shared placeholders per profile) | partial: t_sub::test_profiles_catalog asserts only that `notes` is non-empty. The 2–3 count, both languages per note and the wording are uncovered. m_sub "the counter shows the profile, its goal and early note". | ux |
| R-52 | The profile catalog is served to an unlocked patient and to doctors. A patient token on the staff catalog gets 403. | §5.6 | `chk:124-126`, `chk:226-228` | t_sub::test_profiles_catalog, test_doctor_reads_the_catalog_too, test_profiles_need_an_unlocked_patient; m_tapi "reads the profile catalog", "a malformed catalog is unavailable, not a crash" | api |
| R-53 | A doctor's profile change sets the type; `null` goes back to generic and keeps the type. The next check asks the new signals, past checks keep theirs, and the change is audited with the row id. | §3, §5.6 | `chk:231-251` | t_sub::test_doctor_corrects_the_profile | api |
| R-54 | Two simultaneous first saves of the same check must not return 500 or put answers in server logs. | §5.6 Privacy, §8.3 | not found. `chk:150-164` is select-then-insert with no catch for the unique violation. An `IntegrityError` traceback carries the SQL parameters (craving, signals JSON) into the server log. | uncovered (needs PostgreSQL; Docker is available) | security |

## 6. Good habits (PRD §5.6)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-55 | Clinic list of 6 habits (sport/walk, brushing teeth, water, reading, calling family, sleeping on time), each in AR and FR. | §5.6 | `backend/app/habits.py:8-15`, `hab:128-130` | t_gh::test_catalog; m_tapi "reads the catalog in both languages" | api |
| R-56 | A habit in the patient's own words: `text` is required for `custom` only, trimmed, at most 60 characters. | §5.6 | `hab:44-65` | t_gh::test_custom_habit_needs_own_words; m_sub "a habit in the patient's own words" | api |
| R-57 | Up to 5 active habits (`409 too_many_habits`). The same list habit twice returns `409 habit_exists`. | §5.6 | `hab:29`, `hab:145-149` | t_gh::test_habit_limits | api |
| R-58 | One "done" tick per habit per day; ticking twice is a no-op; untick is allowed. Day from today−2 to today+1 (UTC). | §5.6 | `hab:187-218`, `models:514` | t_gh::test_tick_untick_and_day_range; m_tapi "ticks, unticks, sets the reminder and removes" | api |
| R-59 | Habit ticks sit on the daily check screen. | §5.6 | `m/features/recovery/daily_check_screen.dart` | m_sub "the daily check ticks good habits too", "good habits: tick, add from the list, remove" | ux |
| R-60 | Optional daily reminder per habit, `HH:MM` 24 h, or `null` to turn it off. | §5.6 | `hab:159-169` | t_gh::test_reminder_set_clear_and_validate | api |
| R-61 | Habit reminder text names a list habit ("Time for: Sport"). A habit in the patient's own words shows only "Time for your habit". No medical content. | §5.6 | `m/features/recovery/recovery_reminders.dart` | partial: m_rem "a habit from the list is named; one in own words is not" (FR only; AR uncovered) | security |
| R-62 | Removing a habit stops it but keeps its done days (soft delete), audited with the row id. | §5.6 | `hab:172-184` | partial: t_gh::test_add_list_and_remove (audit and kept days uncovered) | api |
| R-63 | The doctor sees each active habit with the days done in the last 30 (`days` 1–90), own patients only. | §5.6 "Doctor also sees" | `hab:232-251` | t_gh::test_doctor_sees_days_done_out_of_30; d_trk "lists each habit with the days done out of 30", "says so when the patient kept none" | api |
| R-64 | Habits raise no alerts. | §5.6 | by absence (`aj` has no habit job) | uncovered | alerts |

## 7. Medications and doses (PRD §5.3, §12.3)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-65 | The doctor prescribes: name, dose (`amount`), 1–6 distinct `HH:MM` times, start/end (end ≥ start), and instructions of at most 300 characters. Blank name or amount returns 422. | §5.3 | `med:53-85`, `med:127-152` | t_med::test_prescription_validation, test_doctor_prescribes_and_patient_sees_sorted_doses; d_rec "prescribes with the times parsed into a list", "tells the doctor when the prescription is refused" | api |
| R-66 | The doctor can **edit** a schedule. | §5.3, §7 "create and edit schedules" | not found: only create (`med:127`) and stop (`med:170`) | uncovered | api |
| R-67 | The doctor can stop a medicine. It leaves the patient's list and past answers are kept. Prescribe and stop are audited with the row id only, never the drug name or dose. | §5.3, §8.3 | `med:149`, `med:170-186` | partial: t_med::test_doctor_lists_and_stops_a_medication, t_srec::test_no_alert_for_a_stopped_medicine; d_rec "stops a medicine". The audit target is uncovered. | api |
| R-68 | The patient cannot edit their medications: no patient write route, and a patient token on staff routes gets 403. | §3 "Cannot do" | by absence (`med` router has only doses and quote); `staff:89-96` | t_med::test_doctor_only_reaches_own_patients (patient token → 403); t_iso::test_patient_token_is_refused_on_staff_routes | security |
| R-69 | The patient sees the doses for a day (default: today, clinic time), earliest first. An unanswered past dose is `missed`. Ended, future and stopped courses are hidden. | §5.3, §12.3 | `med:232-259` | t_med::test_doctor_prescribes_and_patient_sees_sorted_doses, test_past_unlogged_doses_are_missed, test_ended_or_future_medication_is_not_listed; m_rapi "lists today's doses for the phone's day"; m_home "marking a dose as taken" | api |
| R-70 | Taken/Skipped answer: answering again replaces it. `due` is refused. Only prescribed times on running days are accepted (`422 dose_not_scheduled`). Day from clinic today−2 to today+1. Another patient's medicine returns 404. | §5.3 | `med:262-290` | t_med::test_mark_dose_taken_then_skipped, test_dose_checks, test_patient_sees_only_own_medications; m_rapi "answers a dose taken or skipped" | api |
| R-71 | **Snooze** on a dose. | §5.3 | not found: `DoseStatus` is only taken/skipped (`models:547-552`), and the phone has no snooze | uncovered | ux |
| R-72 | Medication reminders are scheduled locally on the phone with neutral text ("Time for your reminder") and no drug names, and work offline. | §5.3, §8.3 | not found: the phone schedules only appointment (`m/features/booking/appointment_reminders.dart`), daily-check and habit reminders (`m/features/recovery/recovery_reminders.dart`). There is no dose reminder. | uncovered | ux |
| R-73 | A stopped medicine also disappears from the patient's **past** days (its history is no longer listed to the patient). | none (question) | `med:232-233` (`_runs_on` requires `active`) | uncovered | api |
| R-74 | The doctor sees medication adherence (dose history) in the patient file. | §7 Patient file | not found: no staff route returns `DoseLog` rows | uncovered | api |

## 8. Quote of the day (PRD §5.2)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-75 | One quote per clinic day: the same all day, a new one tomorrow. | §5.2 | `med:301-323` | t_med::test_quote_of_the_day_is_stable_and_changes_daily | api |
| R-76 | The quote is chosen among the patient's addiction types plus general quotes. | §5.2 | `med:307-319` | t_med::test_quote_prefers_the_patients_addiction_types | api |
| R-77 | The quote is chosen by **recovery stage**. | §5.2 | not found: `Quote` has no stage (`models:569-580`) | uncovered | api |
| R-78 | Every quote exists in Arabic and French. The seed is safe to run twice and contains no medical content. | §5.2, §8.6 | `models:576-577`; `backend/app/quotes_seed.py` | t_med::test_seed_quotes_exist_once; m_rapi "reads the quote of the day without an author line" | api |
| R-79 | The quote library is managed by the super admin, and doctors can add their own. | §5.2, §7 | not found: no quote route | uncovered | api |
| R-80 | The patient can save favourite quotes and share one as an image. | §5.2 | not found | uncovered | ux |
| R-81 | No matching quote returns `404 no_quote`. The app treats that as "no quote", not as an error. | §5.2 (implied) | `med:320-321`; `m/features/recovery/api_recovery_repository.dart:489` (`nullOn404`) | t_med::test_no_quote_is_a_404; app side uncovered | api |

## 9. Access and privacy (PRD §3, §5.6 Privacy, §8.3)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-82 | A patient reaches only their own addictions, relapses, checks, ticks, habits, doses, goal and milestone. Another patient's id looks unknown (404) and lists come back empty. | §3, §5.6 Privacy | `rec:139-143`, `rec:150-157`; `chk:140`, `chk:176`; `hab:111-115`, `hab:118-125`; `med:245-248`, `med:270-272`; `cin:41-47` | t_rec::test_patient_sees_only_own_addictions; t_sub::test_patient_reaches_only_own_addictions; t_gh::test_patient_reaches_only_own_habits, test_goal_is_own_and_locked; t_med::test_patient_sees_only_own_medications; t_cin::test_each_patient_has_their_own_days; t_ms::test_only_the_patient_marks_their_milestone_seen | security |
| R-83 | A doctor reaches clinical data only for their own patients: addictions with relapse notes, review, profile change, the checks chart, habits and medications. Anyone else is 404. | §3, §5.6 "What the doctor sees" | `med:110-124` `_own_patient`, used by `srec:63`, `srec:80`; `chk:219`; `hab:240`; `med:135`, `med:161`, `med:179` | t_srec::test_doctor_only_reaches_own_patients; t_sub::test_other_doctor_reaches_neither_chart_nor_profile, test_another_patients_addiction_is_not_found; t_gh::test_other_doctor_cannot_see_habits, test_unknown_patient_habits_not_found; t_med::test_doctor_only_reaches_own_patients; t_iso::test_unrelated_doctor_cannot_reach_clinical_data (medications and addictions only) | security |
| R-84 | "Own patient" means the primary doctor, plus shared or transferred patients, not "any booking". | §3 multi-doctor rules | not found. **See SEC-02** (`med:110-124`). | t_iso::test_one_booking_with_another_doctor_does_not_open_clinical_data (xfail strict, SEC-02) | security |
| R-85 | A doctor whose only appointment with the patient was cancelled, or is still in the future, has clinical access and receives alerts. | §3 | `med:117` (`!= awaiting_payment`). This is part of **SEC-02**; do not report it as new. | uncovered (carry as "see SEC-02") | security |
| R-86 | An addiction id under the wrong patient id returns 404, so data cannot be mixed through the path. | §3 | `srec:82`, `chk:221` | t_srec::test_addiction_of_another_patient_is_not_found; t_sub::test_another_patients_addiction_is_not_found | security |
| R-87 | A doctor lists and marks read only their own alerts. Another doctor's alert id returns 404. | §3, §7 | `srec:135`, `srec:148` | t_srec::test_a_doctor_sees_only_their_own_alerts | security |
| R-88 | The super admin has doctor rights for their own patients and never sees other doctors' patients' clinical data, including checks, habits and profile changes. | §3 | `staff:89-96` → the same `_own_patient` | partial: t_iso::test_super_admin_cannot_read_another_doctors_patients_clinical_data (medications, addictions, alerts only). Checks chart, habits and the profile PUT are uncovered. | security |
| R-89 | Clinic staff never see clinical data. | §3 | not found: there is no clinic-staff role (`models:33-36`). See SEC-04. | t_iso::test_a_clinic_staff_role_exists (xfail, SEC-04) | security |
| R-90 | A patient token on any staff recovery route gets 403; no token gets 401. | §8.3 | `staff:89-96` | t_srec::test_requires_doctor; t_sub::test_doctor_routes_need_a_doctor, test_doctor_reads_the_catalog_too; t_gh::test_other_doctor_cannot_see_habits; t_iso::test_patient_token_is_refused_on_staff_routes (medications, addictions) | security |
| R-91 | A deleted account (grace period) is refused on patient recovery routes, and its doctor gets 404 on the file. | §12.5, §8.3 | `deps:28` (`user.active`), `med:122` | uncovered for recovery routes (`test_delete.py` covers login only) | security |
| R-92 | The doctor's patient list shows only patients who booked with that doctor, with no clinical fields (phone and visits). | §3, §7 | `staff:275-308` | t_staff::test_patients_are_only_those_who_booked_with_me; t_iso::test_unrelated_doctor_cannot_reach_clinical_data | security |
| R-93 | The audit log records **who viewed** patient clinical data. | §8.3 | not found: the GET routes `srec:57`, `chk:254`, `hab:232` and `med:155` write no audit row. Only changes are audited. | uncovered | security |
| R-94 | Recovery audit rows store row ids only, never the type, substance, drug name, dose, note or answers. | §5.6 Privacy, §8.3 | `backend/app/audit.py:8-20` + call sites `rec:191`, `rec:224`; `srec:87`; `chk:248`; `med:149`, `med:184`; `hab:153`, `hab:182` | partial: t_sub::test_answers_never_reach_the_audit_log (check answers), t_sub::test_doctor_corrects_the_profile (target == id). `addiction.added` (substance), `relapse.logged` (note), `medication.prescribed` (drug name) and `habit.added` (own words) are uncovered. | security |
| R-95 | Answers, relapse notes, drug names and habit words never reach logs. | §5.6 Privacy, §8.3 | no logging in the recovery routers; `jobs:49` uses `log.exception`; a 500 traceback carries SQL parameters (see R-54) | uncovered | security |
| R-96 | An alert carries only the kind and the patient. The API fields are exactly `{id, patient_id, patient_phone, type, priority, read, created_at}`. | §5.6 Alerts, §7 | `srec:37-45`, `srec:115-125`; `models:632-650` | t_sub::test_three_high_craving_days_alert_the_doctor_once (field set); t_rec::test_relapse_alerts_the_patients_doctor_without_medical_content; t_srec::test_relapse_alert_reaches_the_doctor_and_can_be_read ("note" absent); t_ms::test_the_alert_names_no_addiction; d_rec "lists unread alerts with no medical content and marks one read" | security |
| R-97 | Screenshots are blocked on sensitive screens (recovery, daily check, medications). | §8.3 | not found (no secure-screen or FLAG_SECURE code under `m/`) | uncovered | security |
| R-98 | No medical content goes through a push service: every recovery reminder is local. Sample mode schedules nothing. | §5.3, §8.3 | `m/core/notifications/local_notifications.dart` | m_ln "with sample data nothing reaches the phone" | security |

## 10. Alerts (PRD §5.1, §5.3, §5.6, §7, §12.3)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-99 | A relapse immediately raises a `relapse` alert with `priority=high` for the patient's doctor. An unpaid hold does not make a doctor the recipient. | §5.1, §12.3 | `rec:221-223` | t_rec::test_relapse_alerts_the_patients_doctor_without_medical_content, test_relapse_alert_skips_a_doctor_the_patient_only_holds_a_slot_with; t_srec::test_relapse_alert_reaches_the_doctor_and_can_be_read | alerts |
| R-100 | The alert recipient is the patient's primary doctor. | §3 | partial. `_doctor_of` (`rec:270-282`) is used for relapse, craving_high, no_checkin and milestone (`aj:88`, `aj:168`). It returns the doctor of the latest-starting non-hold appointment, including cancelled or future ones (see SEC-02). `missed_doses` goes to the **prescriber** instead (`aj:64`, `aj:72`), so two kinds of alert for one patient can reach different doctors. | uncovered beyond the SEC-02 hold case | alerts |
| R-101 | Missed doses on 2+ days in a row → a `missed_doses` alert to the prescriber. At most one per patient and doctor per clinic day. It repeats daily while the misses continue. Stopped medicines and courses newer than 2 days do not count. | §5.3 | `aj:50-77` | t_srec::test_two_missed_days_alert_the_prescriber_once_a_day, test_no_alert_when_a_dose_was_taken_or_the_course_is_new, test_no_alert_for_a_stopped_medicine; t_jobs::test_run_once_raises_alerts_for_real | alerts |
| R-102 | What "missed" means: the code counts a day as missed when **no** dose of that medicine was `taken`. One taken dose out of three clears the day, and `skipped` counts as missed. | §5.3 (ambiguous, see G-04) | `aj:37-46`, `aj:55` | partial: t_srec covers "all missed" and "one taken"; a partial day and skipped-only are uncovered | alerts |
| R-103 | Days before the medicine was entered in the app (`start_date` in the past) are not counted as missed. | none (question) | not found: `aj:55-60` uses `start_date`, not `Medication.created_at`. A course back-dated a week alerts at the first nightly run. | uncovered | alerts |
| R-104 | `craving_high`: craving 4 or more on each of the last 3 full clinic days **for one addiction**. At most one per patient every 3 days. | §5.6 Alerts | `aj:112-127`, `aj:79-85` | t_sub::test_three_high_craving_days_alert_the_doctor_once, test_a_lower_craving_day_breaks_the_run | alerts |
| R-105 | `craving_high` edges: high days on two different addictions do not combine; a day with no check breaks the run; craving exactly 4 counts. | §5.6 | `aj:115-124` (per addiction, `craving >= 4`) | partial: a value of 3 breaks the run (covered). Cross-addiction, a missing day and exactly 4 alone are uncovered (the test uses 4 on all three days). | alerts |
| R-106 | `no_checkin`: 3 full days in a row with no daily check, counting a per-addiction check or a v1 tick. At most one per patient every 3 days. | §5.6 Alerts | `aj:130-153` | t_sub::test_three_days_without_a_check_alert_the_doctor, test_no_missed_check_alert_for_a_new_addiction_or_a_checked_day | alerts |
| R-107 | `no_checkin` skips addictions created inside the 3-day window. A patient with no addiction (v1 ticks only) never gets `no_checkin`. | §5.6 (question G-06) | `aj:134-137` | partial: the new-addiction case is covered; the no-addiction patient is uncovered | alerts |
| R-108 | Alert thresholds are fixed in v1 (code constants, not settings). | §5.6 | `aj:31-34` | uncovered (trivial) | alerts |
| R-109 | Pending (unreviewed) addictions raise `craving_high`, `no_checkin` and `milestone` alerts; rejected ones raise none. | none (question G-07) | `aj:106-109` | uncovered (neither pending nor rejected is tested in the jobs) | alerts |
| R-110 | No alerts for deleted (grace period) patients or for patients whose recovery is locked again. | none (question G-12) | not found: `aj:50-57` and `aj:106-109` do not filter `User.deleted_at` or the unlock state | uncovered | alerts |
| R-111 | The nightly job runs at 00:10 Algiers. A failing job does not stop the others; running twice in a window gives no duplicates. | §5.3, §5.6 (implied) | `jobs:24-51`; dedupe in `aj:62-71`, `aj:87-103`, `aj:163-167` | t_jobs::test_waits_until_ten_past_midnight_in_algiers, test_run_once_runs_both_jobs_and_survives_a_failure; idempotency in t_srec, t_sub, t_ms (each runs twice) | alerts |
| R-112 | The doctor marks an alert read; the unread filter works. | §7 | `srec:128-152` | t_srec::test_relapse_alert_reaches_the_doctor_and_can_be_read; d_rec "lists unread alerts with no medical content and marks one read", "can show the read ones too" | alerts |
| R-113 | The alerts inbox orders by priority (crisis highest), then by date. | §7 | partial: newest first only (`srec:138`); priority is just a badge (`d/pages/Alerts.tsx:55`) | uncovered | alerts |
| R-114 | The inbox names every recovery kind in AR and FR with no medical content: relapse, missed_doses, craving_high, no_checkin, milestone, plus `alertOther` for an unknown kind. | §7, §8.6 | `d/pages/Alerts.tsx:8-16`; `d/i18n.tsx:83-87`, `d/i18n.tsx:158-160`, `d/i18n.tsx:263-267`, `d/i18n.tsx:338-340` | d_rec group "Alerts"; d_trk "names the craving and missed-check alerts without medical content"; d_ba (milestone and booking kinds, FR and AR) | ux |
| R-115 | The alerts tab shows the unread count, and "Open" goes to the patient's file. | §7 | `d/App.tsx`, `d/pages/Alerts.tsx:61-63` | d_rec "opens the patient behind an alert"; d_rec App "shows the unread count on the alerts tab and opens the patient from an alert" | ux |

## 11. Doctor dashboard (PRD §5.6 "What the doctor sees", §7)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-116 | The patient file shows, per addiction: profile, counter, longest streak, total sober days, and relapses with notes (own patients only). | §5.6, §7 | `srec:47-69`; `d/pages/PatientDetail.tsx:53-207` | t_srec::test_doctor_reads_and_confirms_addictions; t_sub::test_profile_list_includes_profile_for_doctor; d_rec "shows what the patient entered with the relapses"; d_trk "names the substance, its type and the counters" | ux |
| R-117 | A 30-day chart of craving and the two signals, plus check-in days out of 30 (`days` 1–90, 422 outside). It is offered as a table too, and a declared use is not called a relapse. | §5.6 | `chk:254-280`; `d/pages/Tracking.tsx:48-210` | t_sub::test_doctor_sees_the_chart; d_trk "charts craving and the profile signals, with the days filled", "offers the same numbers as a table", "marks a declared use without calling it a relapse", "a generic addiction rates craving only" | ux |
| R-118 | The chart window ends at the clinic's today. | §5.6 (implied) | partial: `chk:267` uses UTC today. Between 00:00 and 01:00 Algiers, the clinic's today is left out of the chart (`AddictionCheck.day <= today`, `chk:275`). Same issue for the habits summary (`hab:241-248`). | uncovered | api |
| R-119 | The patient list can be searched and filtered by addiction, streak, risk level and last activity. | §7 | partial: phone filter only (`d/pages/Patients.tsx:18`). The API returns no addiction, streak or activity fields (`staff:67-72`). | d_dash "filters by phone" | ux |
| R-120 | The patient file has a streak history chart. | §7 | not found | uncovered | ux |
| R-121 | The recovery parts of the patient file have empty and error states: no addictions, no checks, no habits, a failed change, a refused prescription, and a retry. | §7, §8.6 | `d/pages/PatientDetail.tsx`, `d/pages/Tracking.tsx` | d_rec "says so when there is nothing yet", "tells the doctor when the prescription is refused"; d_trk "says so when nothing was filled in", "says so when the patient kept none", "tells the doctor when the change fails"; retry on a failed load is uncovered | ux |
| R-122 | A lighter doctor view inside the mobile app (alerts, today's agenda). | §7 intro | not found | uncovered | ux |
| R-123 | A doctor can transfer a patient to another doctor, and patients can be shared. | §3 | not found (see SEC-02) | uncovered | security |

## 12. Localisation and design (PRD §8.6, DESIGN.md)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-124 | Every mobile recovery screen works in Arabic (RTL, the default) and French (LTR): home, daily check, addiction form, relapse sheet, habits, doses, milestone, locked view. | §8.6, DESIGN §9 | `m/l10n/app_ar.arb`, `m/l10n/app_fr.arb` | partial: m_sub "the daily check in French, left to right", "the daily check is right to left in Arabic"; m_home "opens on recovery with three tabs, in Arabic RTL", "French labels, left to right"; m_ms (AR and FR). The addiction form, relapse sheet and doses in FR, and the locked view in FR, are uncovered. | ux |
| R-125 | The dashboard recovery parts work in Arabic (RTL, the default) and French. | §8.6 | `d/i18n.tsx` | partial: d_trk "shows the tracking in Arabic"; d_rec "is available in Arabic" (medications); d_ba (alert labels in AR). The addiction review and the alerts page in AR are uncovered. | ux |
| R-126 | Texts served by the server (profile names, signals, notes, habit list, quotes) all have non-empty `ar` and `fr`. | §8.6 | `sub:36-87`, `backend/app/habits.py:8-15`, `models:576-577` | partial: t_sub::test_profiles_catalog (names and signals; note texts not checked); t_gh::test_catalog; t_med::test_seed_quotes_exist_once | ux |
| R-127 | Every refusal shows a specific, localised message: too_many_addictions, clean_since_in_future, relapse_in_future, relapse_before_start, check_locked, signals_mismatch, goal_invalid, too_many_habits, habit_exists, checkin_day_out_of_range, dose_not_scheduled. | §8.6, DESIGN §9 | not found: the mobile repository turns every non-lock error into `RecoveryUnavailable` (`m/features/recovery/api_recovery_repository.dart:59-61`) | m_rapi "is unavailable on a server error, bad JSON or no network" (only the generic path) | ux |
| R-128 | The mobile Recovery tab shows a retry when loading fails, and an empty state when the patient has no addiction. | §8.6, §12.3 | `m/features/recovery/recovery_screen.dart:454-462` (`LoadError`) | uncovered (no widget test drives `LoadError` or the empty state) | ux |
| R-129 | Colours, sizes and radii come only from design tokens. | DESIGN §1-5, CLAUDE.md | partial: arbitrary values in `d/pages/Tracking.tsx:134` (`gap-[2px]`), `d/pages/Tracking.tsx:188` (`h-[48px]`), `d/pages/Tracking.tsx:200` (`rounded-t-[4px]`) and `d/pages/Alerts.tsx:52` (`min-w-[12rem]`). No hex colour found in the recovery pages or the mobile recovery widgets (spot check). | uncovered | ux |
| R-130 | Sobriety ring: track `teal.100`, progress `teal.500`, centre `display` number plus `caption` label, milestone badge `sand.400`. It counts up over `motion.ringFill` and respects reduced motion. | DESIGN §6-7 | `m/widgets/sobriety_ring.dart` | partial: m_ring "counts up from 0 to the day total", "reads as one label for screen readers", "milestone badge pops in only once the goal is reached", "reduced motion shows the final number at once". Colour tokens are uncovered. | ux |

---

## Route inventory (recovery-related)

Every patient route depends on `recovery_patient` (`deps:48-61`): the caller must have the patient role and an unlocking appointment, otherwise 403 `forbidden` / `recovery_locked`. It sits on top of `current_user` (`deps:17-30`), which refuses missing, invalid and deleted accounts with 401. Every staff route depends on `current_doctor` (`staff:89-96`): role `doctor` or `super_admin` plus a `DoctorProfile`, otherwise 403. There is no clinic-staff role.

| Method | Path | Role | Access helper (ownership) | Defined at |
|--------|------|------|---------------------------|------------|
| GET | /v1/me/addictions | patient (unlocked) | query by `patient_id = me`, active, not rejected | rec:146 |
| POST | /v1/me/addictions | patient (unlocked) | own row created | rec:162 |
| POST | /v1/me/addictions/{addiction_id}/relapses | patient (unlocked) | `rec._own` rec:139 (does not check review status) | rec:197 |
| PUT | /v1/me/addictions/{addiction_id}/goal | patient (unlocked) | `rec._own` | rec:235 |
| POST | /v1/me/addictions/{addiction_id}/milestone/seen | patient (unlocked) | `rec._own` | rec:255 |
| GET | /v1/me/recovery/profiles | patient (unlocked) | none (catalog) | chk:124 |
| PUT | /v1/me/addictions/{addiction_id}/checks/{day} | patient (unlocked) | `rec._own` + rejected → 404 (chk:140-142) | chk:129 |
| GET | /v1/me/addiction-checks?since= | patient (unlocked) | `chk._tracked(me)` chk:112 | chk:168 |
| GET | /v1/me/checkins?since= | patient (unlocked) | query by `patient_id = me` | cin:35 |
| PUT | /v1/me/checkins/{day} | patient (unlocked) | own row | cin:51 |
| GET | /v1/me/reminder | patient (unlocked) | own user row | cin:80 |
| PUT | /v1/me/reminder | patient (unlocked) | own user row | cin:85 |
| GET | /v1/me/habits/catalog | patient (unlocked) | none (catalog) | hab:128 |
| GET | /v1/me/habits | patient (unlocked) | `hab._active(me)` hab:118 | hab:133 |
| POST | /v1/me/habits | patient (unlocked) | own row | hab:138 |
| PUT | /v1/me/habits/{habit_id}/reminder | patient (unlocked) | `hab._own` hab:111 | hab:159 |
| DELETE | /v1/me/habits/{habit_id} | patient (unlocked) | `hab._own` (soft delete) | hab:172 |
| PUT | /v1/me/habits/{habit_id}/days/{day} | patient (unlocked) | `hab._own` | hab:193 |
| DELETE | /v1/me/habits/{habit_id}/days/{day} | patient (unlocked) | `hab._own` (deletes the tick row) | hab:207 |
| GET | /v1/me/doses?day= | patient (unlocked) | query `Medication.patient_id = me` | med:236 |
| PUT | /v1/me/doses | patient (unlocked) | inline `m.patient_id == me and m.active` (med:270-272) | med:262 |
| GET | /v1/me/quote | patient (unlocked) | none (pool), types from own addictions | med:301 |
| GET | /v1/staff/patients | doctor / super_admin | appointments of this doctor, status ≠ awaiting_payment | staff:275 |
| GET | /v1/staff/patients/{patient_id}/addictions | doctor / super_admin | `_own_patient` med:110 (SEC-02) | srec:57 |
| POST | /v1/staff/patients/{patient_id}/addictions/{addiction_id}/confirm | doctor / super_admin | `_own_patient` + addiction belongs (srec:80-83) | srec:93 |
| POST | /v1/staff/patients/{patient_id}/addictions/{addiction_id}/reject | doctor / super_admin | same as confirm | srec:104 |
| PUT | /v1/staff/patients/{patient_id}/addictions/{addiction_id}/profile | doctor / super_admin | `chk._patient_addiction` chk:216 → `_own_patient` | chk:231 |
| GET | /v1/staff/patients/{patient_id}/addictions/{addiction_id}/checks?days= | doctor / super_admin | `chk._patient_addiction` | chk:254 |
| GET | /v1/staff/recovery/profiles | doctor / super_admin | none (catalog) | chk:226 |
| GET | /v1/staff/patients/{patient_id}/habits?days= | doctor / super_admin | `_own_patient` | hab:232 |
| POST | /v1/staff/patients/{patient_id}/medications | doctor / super_admin | `_own_patient` | med:127 |
| GET | /v1/staff/patients/{patient_id}/medications | doctor / super_admin | `_own_patient` | med:155 |
| DELETE | /v1/staff/patients/{patient_id}/medications/{medication_id} | doctor / super_admin | `_own_patient` + `m.patient_id` (any own-patient doctor can stop another doctor's prescription) | med:170 |
| GET | /v1/staff/alerts?unread= | doctor / super_admin | `Alert.doctor_id = me` | srec:128 |
| POST | /v1/staff/alerts/{alert_id}/read | doctor / super_admin | `Alert.doctor_id = me` | srec:141 |
| (job) | missed_dose_alerts | nightly, no HTTP | recipient = `Medication.prescribed_by` | aj:50 |
| (job) | craving_alerts / no_checkin_alerts | nightly, no HTTP | recipient = `_doctor_of` (rec:270) | aj:112 / aj:130 |
| (job) | milestone_alerts | nightly, no HTTP | recipient = `_doctor_of` | aj:156 |

**Not built** (no route exists for these):
- doctor edits a medication
- doctor corrects clean-since, substance or type
- triggers and severity
- dose history or adherence for the doctor
- daily v1 ticks for the doctor
- streak history
- quote management, doctor quotes, quote favourites and share
- transfer or share a patient
- snooze
- clinic-staff role
- doctor mobile view

Schema (migrations 0008–0012, 0014):
- **0008:** `addictions`, `relapses`, `alerts` (FK cascade).
- **0009:** `daily_checks` (unique patient+day), `users.reminder_time`.
- **0010:** `medications` (`prescribed_by` has no FK), `dose_logs` (unique medication+day+time; status taken/skipped), `quotes` (no stage, no author).
- **0011:** `substance_profile` enum, the `stimulants` type, `addiction_checks` (unique addiction+day, JSON signals).
- **0012:** `goal_days`, `habits`, `habit_logs` (unique habit+day).
- **0014:** `milestone_seen`/`milestone_alerted` (server_default 0). On upgrade, each existing streak gets one milestone alert at the first nightly run.

## Summary

| Area | Rules | Uncovered (no test at all) | Partial |
|------|-------|-----------------------------|---------|
| api | 58 | 12 | 8 |
| security | 25 | 9 | 4 |
| alerts | 18 | 8 | 3 |
| ux | 29 | 9 | 6 |
| **Total** | **130** | **38** | **21** |

"Enforced at: not found" (nothing in the code enforces it): 20 rules (R-18, R-47, R-54, R-66, R-71, R-72, R-74, R-77, R-79, R-80, R-84, R-89, R-93, R-97, R-103, R-110, R-120, R-122, R-123, R-127). Many more rules have notes marked `partial`.

Counted by script from the table rows: "Uncovered" means the Covered-by cell starts with `uncovered`; "Partial" means it starts with `partial`.

## PRD gaps (open questions for testers — report as QUESTION, not bug)

- **G-01, primary doctor and alert routing (SEC-02 family).** There is no primary, shared or transferred field. Relapse, craving_high, no_checkin and milestone alerts go to the doctor of the latest-starting non-hold appointment, including cancelled or future ones. Missed-dose alerts go to the prescriber. The PRD does not say which doctor gets which alert when a patient has seen several doctors, or what "shared" means.
- **G-02, unlock after a cancel or refund.** The PRD unlocks on "first appointment confirmed (paid)". The code re-locks every recovery route when the only paid appointment is later cancelled. Should a once-paid patient keep tracking? Doctors keep access and alerts keep firing either way (R-05, R-08).
- **G-03, whose "day".** "Editable the same day", "one answer per day" and the 30-day windows do not say which day: phone, clinic (Algiers) or UTC. The code mixes UTC (checks, habits, ticks, edit lock, doctor chart) and clinic time (doses, quote, alerts) (R-46, R-47, R-118).
- **G-04, definition of "missed doses for 2+ days in a row".** Is it every dose missed, any dose missed, or "skipped" too? Do days before the medicine was entered count? (R-102, R-103)
- **G-05, alert repetition.** The PRD defines the triggers but not repeats. The code re-alerts missed_doses daily and craving_high/no_checkin every 3 days while the condition lasts.
- **G-06, `no_checkin` for patients with no addiction** (v1 tick only). The PRD's rule sits in §5.6 (per substance). The code never alerts them (R-107).
- **G-07, pending and rejected addictions.** Should pending ones be tracked, counted for milestones and alerted before the doctor's review? Should a rejected one still accept relapses and goals (it does, and that raises an alert)? (R-16, R-109)
- **G-08, relapse "note or trigger".** Is it one free-text field or a separate trigger? How does it relate to the "triggers noted by the doctor" on the addiction (R-18, R-23)?
- **G-09, scope of the doctor's correction.** "The doctor can correct it": which fields (type, substance, clean-since date)? Only the profile is built. Triggers and severity are not built (R-17, R-18).
- **G-10, small goals after 4 weeks.** "Higher or lower" is only allowed among 1–28 days. After day 28, no choice is possible (60/90/… are refused) (R-34).
- **G-11, medications.** "Edit schedules" (§7) vs stop-and-recreate. Can a doctor stop another doctor's prescription for a shared patient? What does Snooze do (local only, how long, is it synced)? Local medication reminders are not built at all (R-66, R-71, R-72).
- **G-12, deleted or locked patients.** Should nightly alerts stop for an account in its deletion grace period, or for a patient locked again (R-110)?
- **G-13, quotes.** What is the "recovery stage" (days of streak?), and who can add, edit or deactivate quotes? Favourites and share are not built (R-77, R-79, R-80).
- **G-14, limits the PRD does not state.** A maximum of 10 addictions (R-13); relapse note at most 500 characters; habit text at most 60 characters; at most 6 dose times; doctor chart window at most 90 days.
- **G-15, counter precision.** "Days (and hours)": the counter shows days only (R-27). Days are counted as elapsed 24-hour periods from the UTC start instant, not calendar days.
- **G-16, audit of views.** §8.3 says "who viewed or changed patient data". Only changes are audited (R-93).
- **G-17, buprenorphine and pregabalin "taken as prescribed is tracked in Medications, not as use".** No app copy or rule tells the patient this; the PRD does not say where it is shown.
- **G-18, alerts inbox priority.** "Crisis flags (highest priority)": with the AI not built, is newest-first acceptable for now (R-113)? The §7 inbox also lists **no-shows**, which raise no alert today (booking-side, out of scope here).
- **G-19, the doctor sees a custom habit's own words.** The PRD says the doctor "sees each habit". The code shows the patient's text. Confirm this is intended.
- **Out of scope / not built (do not test):**
  - AI supportive check-in after a relapse (§5.1, §12.3)
  - the AI never turning answers into a diagnosis (§5.6 Privacy)
  - v1.1 mood rating (§5.4)
  - clinic-staff role (SEC-04)
