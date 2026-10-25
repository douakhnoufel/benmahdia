# Verified findings — booking QA 2026-10-25

Verifier: independent (wrote none of the tests). Each finding below was checked three ways: is it in the PRD in those words (docs/PRD.md, §3 as updated today), does the code at "Where" match, and does the repro test fail on its own assertion. For that last check I re-ran every xfail with `--runxfail` and every Flutter bug group with `--dart-define=QA_RUN_BUGS=true`. Severity was re-checked against the SKILL.md guide: critical = double booking, another patient's data, confirmed without payment; high = PRD acceptance criterion broken; medium = PRD rule outside the AC, or missing error state; low = wording, token, polish.

No tester test needed a setup fix. No app code was changed by the team (git status: only test files and qa/ are new). One existing test was edited: `backend/tests/test_medications.py`. The edit gives each linked patient their own slot so the test also runs on PostgreSQL. It is test-only and hides nothing.

## Totals

| Verdict | Count | Notes |
|---|---|---|
| CONFIRMED | 24 distinct (28 reported findings) | 4 duplicates merged: API-04 into SEC-02, SEC-05 into SEC-04, RACE-03 and RACE-06 into RACE-02 |
| QUESTION | 2 | PAY-01, UX-07 |
| REJECTED | 3 | RACE-05, RACE-07, RACE-08: by reading only, no repro test; reopen when a test shows them |

By severity (confirmed): critical 0 · high 7 · medium 14 · low 3.

## Confirmed

| ID | Sev | Title | Root cause (one line) | Where | Verdict note |
|---|---|---|---|---|---|
| API-03 | high | Recovery tracking and medications open before the first confirmed appointment | `patient` dependency checks role only; no "has a confirmed appointment" gate | backend/app/routers/recovery.py:38-41 (also used by checkins.py); medications.py `/v1/me/doses` | PRD §4.2 AC, word for word. 3 xfails fail with 201/204/200 instead of 403 |
| API-07 | high | No confirmation notification and no 24 h / 1 h reminders | No notification or push code exists; jobs.py runs only purge and missed-dose alerts | backend/app/routers/appointments.py:200-226, payments.py:107-116, backend/app/jobs.py | PRD §4.3 AC "Reminder arrives within 1 min", §4.4 Flow. No test is possible (nothing to call); confirmed by grep: no push/notify code under backend/app. The app's done screen promises reminders |
| API-01 | high | Clinic can approve a sign-up that never declared an ID, and booking unlocks | `approve` accepts a `pending_verification` user with no declaration; `id_status()` then reports `approved` | backend/app/routers/staff.py:345-369; backend/app/tokens.py:17; identity.py:55 | PRD §4.2: none → declared → approved; booking needs approved. The xfail fails because the hold returns 201. `test_staff.py::test_approved_patient_can_then_book` relies on this path |
| SEC-02 (+API-04) | high | Clinical data and alerts follow bookings, not a primary doctor | No primary, shared or transfer field exists. `_own_patient` = "any non-hold appointment with this doctor"; `_doctor_of` = doctor of the latest appointment | backend/app/routers/medications.py:110-124 (also staff_recovery.py:21,65); recovery.py:182-190; models.py (no field) | PRD §3: clinical data isolated per doctor by default; §4.3: the first doctor booked becomes primary. Xfails: two doctors both read the medications (2 ≤ 1 fails); the relapse alert goes to the second doctor. Severity high because CLAUDE.md requires this isolation to be enforced in the API. Open part: how sharing is recorded (Q list) |
| RACE-02 (+RACE-03, RACE-06) | high | Releasing a hold is not atomic with confirm or the paid webhook | `release_hold` reads the status in memory, then deletes by primary key with no row lock and no status condition; confirm and webhook also update without a lock | backend/app/routers/appointments.py:185-197 (release), 200-226 (confirm); payments.py:106-125 | PostgreSQL --runxfail: "payment paid, appointment gone, no refund flag"; "confirm said 200 with code, release said 204, row gone"; natural timing gives `StaleDataError` (HTTP 500). The gap tests use an injected 0.6 s delay, which is a fair way to widen a real window. Money can be lost with no flag, so high |
| UX-01 | high | "Complete your profile" still offers Skip | A Skip button and `onSkip: finish` are still wired | apps/mobile/lib/features/profile/profile_prompt_screen.dart:55; profile_flow.dart:30 | PRD §4.2 AC "cannot be skipped". The bug test finds `profile-skip`. `profile_test.dart` asserts the old behaviour |
| UX-02 | high (raised from medium) | The "ID declared" label never appears | No string exists; the card shows "En attente de la clinique" for declared, and for approved too | apps/mobile/lib/features/profile/profile_card.dart:32-38; l10n .arb files | PRD §4.2 AC names the label "ID declared" / "Identité déclarée" / "هوية مصرّح بها". Raised because an AC is broken |
| SEC-01 | medium (lowered from high) | Doctor agenda shows only the caller's appointments | `Appointment.doctor_id == doctor.user_id` filter | backend/app/routers/staff.py:166 | PRD §3 (updated). The xfail shows the other doctor's row missing. Lowered because it is in §3, not an AC. `test_staff.py:80` must change with the fix |
| SEC-03 | medium (lowered from high) | Super admin is refused on every doctor route | `current_doctor` accepts only `Role.doctor` | backend/app/routers/staff.py:88-94 | PRD §3 "also holds the Doctor role". The xfail gets 403 even though the admin has a doctor profile. Not an AC |
| SEC-04 (+SEC-05) | medium (lowered from high) | No clinic-staff role; doctors approve IDs and run the desk alone | `Role` has no staff value; approve, reject and check-in use `current_doctor` | backend/app/models.py:32-35; staff.py:88-94, 352-398 | PRD §3 and §4.2 "the doctor does not approve IDs"; §4.3 secretary at the desk. Xfails: no role; a plain doctor gets 200 on approve. Not an AC. The role-name test guesses names (staff, secretary, …); adjust it if a different name is chosen |
| API-02 | medium | No automatic ID approval | `declare` always stores `declared`; `IdentityIn` has no fields for the signals | backend/app/routers/identity.py:33-41, 101-180 | PRD §4.2 Approval. The xfail gets `declared`. The signal field names in the test are a guess (API-Q6) |
| API-05 | medium | A doctor cannot book for a patient | No staff route creates an appointment | backend/app/routers/staff.py | PRD §4.3 "or the doctor books for the patient". OpenAPI check fails |
| API-06 | medium | A doctor cannot set availability, holidays or slot length | Only seed.py writes `Availability` | backend/app/seed.py:50; no staff route | PRD §4.3, §3, §7. OpenAPI check fails |
| RACE-01 | medium | PostgreSQL race tests cannot run as documented | conftest unconditionally sets `DATABASE_URL=sqlite://` | backend/tests/conftest.py:4 | Test infrastructure, not app code. Confirmed: the races run only with the scratch `-p qa_pg_plugin`. The only proof of AC "exactly one succeeds" never runs in CI |
| RACE-04 | medium | One open hold per patient breaks with parallel holds on two doctors | The lock is per doctor row; no partial unique index on patient + awaiting_payment | backend/app/routers/appointments.py:133-151 | PRD §12.2.1. PG --runxfail: "patient has 2 open holds" |
| UX-03 | medium | French done screen overflows on the reminder line | `Row(icon, Text)` with no `Flexible`/`Expanded` | apps/mobile/lib/features/booking/book_done_screen.dart:294 | Bug run: overflow by 116/186/268 px in all 6 French cases; Arabic is fine |
| UX-04 | medium | Server refusals read as "check your connection" | `_failure` maps every unknown code to `BookingUnavailable`, shown as `bookLoadError` | apps/mobile/lib/features/booking/api_booking_repository.dart:132-141 | Missing error state (guide: medium). Also against §4.2: a not-approved patient should read "being reviewed". 4 bug tests find the connection text. Exact wording is a question (UX-Q1) |
| UX-05 | medium (raised from low) | Cancel answered with `appointment_not_found` throws, nothing shown | The screen catches only `TooLateToCancel`/`BookingUnavailable`, but 404 maps to `SlotUnavailable` | apps/mobile/lib/features/booking/my_appointments_screen.dart:72-81 | Missing error state (guide: medium). The bug test finds no SnackBar |
| UX-06 | medium | The booking code is never shown to the patient | `Appointment` model has no code field; the parser ignores `checkin_code` | apps/mobile/lib/features/booking/booking_models.dart; api_booking_repository.dart `_appointmentFrom` | PRD §4.3 "shown to the patient as text". The API sends the code (appointments.py:73). Front-desk check-in can't be used without it |
| UX-09 | medium | An unpaid hold in "my appointments" offers "Cancel appointment" | `canCancel` checks only the notice, not the status | apps/mobile/lib/features/booking/my_appointments_screen.dart:178 | The API refuses (cancel only `confirmed`, appointments.py:282). The bug test finds "إلغاء الموعد" |
| UX-11 | medium | No receipt in the app | Not built | apps/mobile/lib/features/booking/* | PRD §4.4 "the patient sees a receipt in the app". Static grep: no receipt screen or string. Contents are a question |
| UX-08 | low | Hold countdown counts timer ticks instead of following the clock | `_left -= _tick`, never recomputed from `expiresAt - now()` | apps/mobile/lib/features/booking/book_confirm_screen.dart:44, 65-71 | Bug run: after a 10-minute jump the screen shows 14:58 instead of 04:5x. The server stays the authority, so low |
| UX-10 | low | Notice and horizon hard-coded as "24 h" / "two months" in copy | Strings are fixed while the repo reads `notice_hours`/`horizon_days` per doctor | apps/mobile/lib/l10n/app_fr.arb:88-154 (bookNotice, bookTooSoon, bookCancelRule, bookChangeHint, apptLocked, bookNoFree), same keys in ar | PRD §4.3 notice is configurable per doctor. Static |
| UX-12 | low | Off-token sizes in booking screens | `fontSize: 12` (smallest token `AppType.caption` = 13), `AppSpace.x + 2`, raw 2/6 px, `AppRadius.card - 4` | apps/mobile/lib/features/booking/book_slot_screen.dart:577, my_appointments_screen.dart:382, 580 (others in the finding) | CLAUDE.md "only from design tokens". Checked by grep; caption = 13 at app_tokens.dart:154 |

## Questions (not bugs until the PRD decides)

| ID | Question | Why not confirmed |
|---|---|---|
| PAY-01 | What should a `checkout.paid` webhook do when it arrives for a hold that has already expired but has not been purged yet: confirm if the slot is still free, or refund? | The PRD says only "unpaid hold released after timeout" (rules gap 5). The code really is inconsistent (payments.py:110 ignores `hold_expires_at`, and the result depends on unrelated holds), and the xfail fails as stated. But the test assumes "refund", which the PRD does not say. Keep the xfail; rewrite it if the clinic picks "confirm if free" |
| UX-07 | Should the doctor screen show a message when no doctor can be booked? | The PRD and DESIGN say nothing about this empty state. The bug test fails as stated (only the title and a disabled button) |

Tester questions carried forward, deduplicated (PRD is silent on each):
- Day 60 bookable? (API-Q1, rules gap 2)
- Is a slot exactly 24 h away bookable and cancellable? (API-Q2)
- Should a follow-up be suggested from a future confirmed visit? (API-Q3)
- Can completed ↔ no-show be re-marked? (API-Q4)
- Payment, notice and horizon rules for doctor-made bookings? (API-Q5)
- Field shape for the auto-approval signals? (API-Q6)
- Does cancelling the first visit re-lock recovery? (API-Q7)
- Is the hold timeout fixed at 15 min or set per doctor? (API-Q8)
- May doctor A act on doctor B's appointment: mark status or paid, or check in? (SEC-Q1, PAY-Q6, rules gap 9)
- How are primary doctor, sharing and transfer recorded? (SEC-Q2)
- Which doctors does a secretary serve? (SEC-Q3)
- Should doctors keep seeing ID data once clinic staff exist? (SEC-Q4)
- Should the clinic-wide agenda show patient phones? (SEC-Q5)
- Should the webhook check amount and currency? (PAY-Q1)
- Several checkouts for one hold: allowed? (PAY-Q2)
- Should a failed first checkout drop a hold whose retry is still open? (PAY-Q3)
- Should pay-at-clinic stay open once Chargily is live? (PAY-Q4)
- Should cancelling a card-paid visit raise a refund flag? (PAY-Q5)
- Should opening checkout extend the hold? (PAY-Q7)
- Error wording per refusal code? (UX-Q1)
- Repeat check-in: say "already arrived"? (UX-Q2)
- What goes in the receipt? (UX-Q3)
- Show the exact lockout wait? (UX-Q4)
- Payment control: toggle (DESIGN §7) or three cards? (UX-Q5)
- Should the dashboard check the code format before sending? (UX-Q6)
- Keep the "first doctor becomes primary" sentence while R-34 is unbuilt? (UX-Q7)

## Rejected

| ID | Reason |
|---|---|
| RACE-05 | Card webhook and pay-at-clinic confirm both winning. By reading only, and the tester wrote no test. The logic is plausible: neither path locks the row. Reopen with a race test before counting it |
| RACE-07 | Webhook does sync DB work in `async def`. The tester calls it latent, not confirmed; the parallel test passed 25/25. Nothing is broken today |
| RACE-08 | Global expired-hold purge could deadlock across doctors. By reading only, never seen in any run |

Also not counted on its own: the webhook half of RACE-06 (by reading). It sits under RACE-02, whose fix covers it.

## Test runs (verifier, 2026-10-25)

| Suite | Command | Result |
|---|---|---|
| Backend QA, SQLite | `pytest tests/test_qa_booking_rules.py tests/test_qa_booking_isolation.py tests/test_qa_booking_payments.py` | **169 passed, 14 xfailed** (rules 32+8, isolation 88+5, payments 49+1). `--runxfail`: all 14 fail on their own assertion |
| Races, PostgreSQL (benmahdia-db-1, scratch `-p qa_pg_plugin`) | `pytest -p qa_pg_plugin tests/test_qa_booking_races.py tests/test_concurrent_holds.py` | **43 passed, 4 xfailed**, exit 0. `--runxfail`: RACE-04, RACE-03 (StaleDataError), RACE-02 and RACE-03-gap fail as stated |
| Full backend, SQLite | `pytest` | **447 tests: 385 passed, 1 failed, 14 xfailed, 47 skipped** (46 race cases plus test_concurrent_holds, which need Postgres). The failure is the known `test_identity::test_nothing_readable_is_stored` (assert 438 == 384). The baseline 216 passed are still 216 passed (385 − 169) |
| Mobile | `flutter test test/qa_booking_api_errors_test.dart test/qa_booking_flow_test.dart` | **101 passed, 18 skipped** (QA UX-01..09). With `QA_RUN_BUGS=true`: 101 passed, 18 failed, exactly the UX bug tests, each for its stated reason |
| Dashboard | `npx vitest run src/components/qa-booking` | **27 passed** |

## Rule coverage

73 rules in rules.md. **71 now have at least one test** (pass or xfail). The 16 that were uncovered and the 3 whose tests asserted the opposite (R-08, R-65, R-69) are now tested against the PRD. Still without a test: **R-54** (notifications and reminders: no code to call) and **R-55** (receipt: not built, static check only).
