# api-rules — booking rules through the HTTP API (2026-10-25)

Test file: `backend/tests/test_qa_booking_rules.py` (new). In-memory SQLite, frozen clock (Sat 2026-10-17 18:00 UTC = 19:00 Algiers), seeded doctor. No real patient data.

Command (run from `backend/`):

```
.venv/Scripts/python.exe -m pytest tests/test_qa_booking_rules.py -p no:warnings -rN
```

Result: **32 passed, 8 xfailed** (strict) in 28 s. Each xfail was also run with `--runxfail` to check it fails on its own assertion (the expected PRD behaviour), not on setup.

## Rules covered

| R-id | Tests added (edges) | Result |
|------|---------------------|--------|
| R-01 | patient rejected after booking cannot cancel; approval without a declaration | pass; xfail API-01 |
| R-02 | `none`, `declared`, `rejected` (declaration), `rejected` (account), `duplicate` attempt refused on hold, list, follow-up, doctors, calendar | pass |
| R-05 | clean declaration should auto-approve | xfail API-02 |
| R-06 | addictions, daily check, doses before / after first confirmed appointment | 3 xfail API-03; "after" passes |
| R-09 | 5-min slot grid (08:05 ok, 08:07 refused, end = +5 min) | pass |
| R-10 | first slot, slot before opening, last slot, slot overrunning a window end, break; calendar agrees | pass |
| R-13 | exactly at notice ok, 1 min inside refused; per-doctor notice | pass |
| R-14 | day +59 ok, +61 refused, calendar ends at +59; hold and calendar agree on +60 | pass (see Q1) |
| R-15 | start sent as `+01:00` is the same slot and blocks it; off-grid `+02:00` refused | pass |
| R-16 | at 23:30Z (00:30 Algiers) calendar starts on the Algiers day, horizon uses it | pass |
| R-18 | completed, no-show, cancelled do not block a slot | pass |
| R-25 | a replaced hold cannot be confirmed | pass |
| R-27 | confirming a released hold → 404 | pass |
| R-32 | cancel exactly at notice ok, cancel twice refused, 1 min inside refused, completed / no-show / hold not cancellable | pass |
| R-33 | cancel then another patient holds; cancelled cannot be confirmed back | pass |
| R-34 | first-booked doctor is primary (relapse alert routing) | xfail API-04 |
| R-35 | cancelled / no-show do not trigger a follow-up | pass (see Q3) |
| R-36 | follow-up hold priced at the doctor's current price | pass |
| R-37 | doctor can book for a patient | xfail API-05 |
| R-38 | doctor can set availability | xfail API-06 |
| R-39 | cancelled / unpaid visit cannot be marked completed or no-show | pass |
| R-40 | held / confirmed / cancelled audited with appointment id only, no check-in code | pass |
| R-54 | notifications and reminders | no test possible (nothing to call); finding API-07 |

Not re-tested (already covered by existing tests, rows say so): R-03, R-04, R-11, R-12, R-19, R-20, R-21, R-22, R-26, R-29, R-30. R-23 / R-24 belong to the concurrency agent (need PostgreSQL).

## Findings

### API-01: Clinic can approve a sign-up that never declared an ID, and booking unlocks
- Severity: high
- Rule: R-01, R-02 (PRD §4.2 Status values, Gating, AC "id_status other than approved cannot book")
- Where: backend/app/routers/staff.py:345-369 (`_signup` / `approve` do not require a declaration); backend/app/tokens.py:17 and backend/app/routers/identity.py:55 report `approved` for a verified account with no declaration
- Repro: tests/test_qa_booking_rules.py::test_r01_approval_without_a_declaration_does_not_unlock_booking (the sign-ups list shows `id_status: none`, the approve call succeeds, the hold returns 201)
- Expected (PRD): status goes `none → declared → approved/rejected`; the profile step is mandatory; booking unlocks only when `id_status = approved`, i.e. after a declaration was approved.
- Actual: a patient with no declared ID (`none`) can be approved and then books; the API then calls them `approved`. The existing test `tests/test_staff.py::test_approved_patient_can_then_book` relies on this path. If the clinic wants a "checked at the desk, no app declaration" path, the PRD needs to say so.

### API-02: No automatic ID approval
- Severity: medium
- Rule: R-05 (PRD §4.2 Approval, §12.1 step 4)
- Where: backend/app/routers/identity.py:101-180 (always stores `declared`); backend/app/routers/identity.py:33-41 (`IdentityIn` has no field for the "read by scanner / not edited / one face" signals)
- Repro: tests/test_qa_booking_rules.py::test_r05_clean_declaration_is_approved_automatically (the extra signal field names are a guess, see Q6)
- Expected (PRD): when every check passes (scanner-read, unedited, check digits valid, HMAC unused, one face) the app approves automatically, recorded as `auto`.
- Actual: every declaration stays `declared` until staff act; the API cannot even receive the signals.

### API-03: Recovery tracking and medications open before the first confirmed appointment
- Severity: high
- Rule: R-06 (PRD §4.2 AC "without a confirmed (paid) appointment cannot use recovery tracking … enforced in the API", §5 Unlock, §12.1 step 5-6)
- Where: backend/app/routers/recovery.py:38-41 (`patient` checks role only; used by addictions, relapses and backend/app/routers/checkins.py); backend/app/routers/medications.py:236-262 (doses)
- Repro: tests/test_qa_booking_rules.py::test_r06_addictions_locked_until_first_confirmed_appointment, ::test_r06_daily_check_locked_until_first_confirmed_appointment, ::test_r06_doses_locked_until_first_confirmed_appointment (the last one with a patient not even ID-approved)
- Expected (PRD): 403 until the patient has a confirmed appointment.
- Actual: 201 / 204 / 200. The module docstring in recovery.py and `tests/test_recovery.py::test_unverified_patient_can_track` state the old rule ("tracking does not need ID approval") — the opposite of the current PRD. The AI companion has no API yet, so nothing to gate there. Open point for the fix: does a later cancelled first appointment re-lock? (Q7)

### API-04: No primary doctor; recovery alerts go to the doctor booked last
- Severity: medium
- Rule: R-34 (PRD §4.3 Booking "the first doctor they book becomes their primary doctor", §3 multi-doctor rules)
- Where: backend/app/models.py (no primary-doctor field); backend/app/routers/recovery.py:182-190 (`_doctor_of` = latest `start_utc`, any status)
- Repro: tests/test_qa_booking_rules.py::test_r34_first_booked_doctor_is_the_primary_doctor (books doctor A, then doctor B on a later day; the relapse alert goes to B)
- Expected (PRD): the first doctor booked is stored as primary and stays so (until a transfer); clinical routing follows the primary doctor.
- Actual: no primary doctor is stored; whichever doctor has the latest appointment (even a cancelled one) gets the alert.

### API-05: A doctor cannot book for a patient
- Severity: medium
- Rule: R-37 (PRD §4.3 Booking "or the doctor books for the patient")
- Where: backend/app/routers/staff.py (no create-appointment route)
- Repro: tests/test_qa_booking_rules.py::test_r37_doctor_can_book_for_a_patient (checks the OpenAPI paths)
- Expected (PRD): a staff route that books a slot for a patient.
- Actual: none. Rules for such bookings are unspecified (Q5).

### API-06: A doctor cannot set availability, holidays or slot length
- Severity: medium
- Rule: R-38 (PRD §4.3 Doctor availability, §3 "set availability", §7)
- Where: backend/app/seed.py:50 is the only writer of `Availability`; no staff route
- Repro: tests/test_qa_booking_rules.py::test_r38_doctor_can_set_availability (checks the OpenAPI paths)
- Expected (PRD): doctor edits weekly schedule, breaks, holidays / blocked days, slot length.
- Actual: only by seed script or direct database edit.

### API-07: No confirmation notification and no 24 h / 1 h reminders
- Severity: high
- Rule: R-54 (PRD §4.3 Reminders + AC "Reminder arrives within 1 minute", §4.4 Flow "both sides are notified", §12.2.3)
- Where: backend/app/routers/appointments.py:200-226 and backend/app/routers/payments.py:105-116 (confirm paths send nothing); backend/app/jobs.py (no reminder job)
- Repro: code read — there is no notification or push code to call, so no test was written.
- Expected (PRD): on confirmation patient and doctor are notified; push reminders 24 h and 1 h before, generic text, no medical content.
- Actual: nothing is sent.

## Questions (PRD silent or ambiguous — not bugs)

- **API-Q1 — Day 60.** "Up to 60 days ahead": is today+60 bookable? Code allows clinic days today … today+59 and the calendar shows exactly those 60 days (hold and calendar agree).
- **API-Q2 — Notice boundary.** A slot exactly 24 h away is bookable and cancellable in code (tested). Is that intended?
- **API-Q3 — Follow-up trigger.** Code suggests a follow-up 30 days after the latest *completed or confirmed* appointment, so a future booked visit also triggers it (appointments.py:248-271). PRD says "after a visit".
- **API-Q4 — Re-marking visits.** A doctor can switch completed ↔ no-show at any time after the start (staff.py:241-246). Allowed, or should the first mark be final?
- **API-Q5 — Doctor-made bookings.** Payment path, notice and horizon for a booking made by the doctor (needed before API-05 is built).
- **API-Q6 — Auto-approval signals.** How should the app send "read by scanner, not edited, one face" (field names, per-field or global)? The API-02 test uses a guessed shape.
- **API-Q7 — Recovery re-lock.** If the first confirmed appointment is later cancelled or is a no-show, does recovery tracking lock again?
- **API-Q8 — Hold timeout.** §4.3 says "e.g. 15 min, to confirm", §12.2 says 15 min; code uses a per-doctor `hold_minutes` (default 15). Which is binding?
