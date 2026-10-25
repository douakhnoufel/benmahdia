# Booking QA — 2026-10-25

## Summary
- Confirmed: 24 distinct (0 critical, 7 high, 14 medium, 3 low) — 17 bugs, 7 missing features
- Questions for you: 2 new (PAY-01, UX-07) + 26 PRD gaps in `verified.md`
- Rejected: 3 (RACE-05, RACE-07, RACE-08 — by reading only, not reproduced)
- Rules covered: 71/73 (R-54 reminders, R-55 receipt: features don't exist)
- No double booking: Postgres race tests 43 pass / 4 xfail, 5 runs, no flakes
- Not run: nothing (Docker started mid-run)

## Confirmed bugs (fixable now)
| ID | Sev | Title | Where |
|---|---|---|---|
| RACE-02 | high | Releasing a hold can delete a paid/just-confirmed booking or 500 (no row lock) | backend/app/routers/appointments.py:185-197 |
| API-03 | high | Recovery + doses open before first confirmed visit | backend/app/routers/recovery.py:38, medications.py `/v1/me/doses` |
| API-01 | high | Patient with no ID declared can be approved, then book | backend/app/routers/staff.py:345-369, app/tokens.py:17 |
| UX-01 | high | "Complete your profile" still has Skip | apps/mobile/lib/features/profile/profile_prompt_screen.dart:55 |
| UX-02 | high | "ID declared" label never shown | apps/mobile/lib/features/profile/profile_card.dart:32-38 |
| SEC-01 | medium | Agenda filtered to own visits (new rule: clinic-wide) | backend/app/routers/staff.py:166 |
| SEC-03 | medium | Super admin refused on doctor routes | backend/app/routers/staff.py:88-94 |
| RACE-04 | medium | Patient can hold with two doctors at once | backend/app/routers/appointments.py:133-151 |
| RACE-01 | medium | conftest forces SQLite, race tests never run | backend/tests/conftest.py:4 |
| UX-03 | medium | FR done screen overflows 116–268 px | apps/mobile/lib/features/booking/book_done_screen.dart:294 |
| UX-04 | medium | Server refusals shown as "check your connection" | apps/mobile/lib/features/booking/api_booking_repository.dart:132-141 |
| UX-05 | medium | Cancel → 404 shows nothing | apps/mobile/lib/features/booking/my_appointments_screen.dart:72-81 |
| UX-06 | medium | Booking code never shown to patient | booking_models.dart, api_booking_repository.dart |
| UX-09 | medium | Unpaid hold offers "Cancel appointment" (server refuses) | my_appointments_screen.dart:178 |
| UX-08 | low | Hold countdown drifts | book_confirm_screen.dart:65-71 |
| UX-10 | low | "24 h" / "two months" hard-coded | l10n app_fr.arb / app_ar.arb |
| UX-12 | low | Off-token font size / spacing | book_slot_screen.dart:577 and others |

## Needs your decision before fixing
- **SEC-02 (high):** no primary-doctor field; clinical data + relapse alerts follow "any booking". Need: how primary / shared / transferred is recorded.
- **PAY-01:** paid webhook on an expired-but-not-cleaned hold — confirm if slot still free, or refund?
- **UX-07:** message when no doctor is bookable?

## Missing features (not bugs — need their own plan)
API-07 confirmation + 24 h / 1 h reminders · API-02 automatic ID approval · SEC-04 clinic-staff role (doctors approve IDs today) · API-05 doctor books for patient · API-06 availability management API · UX-11 receipts

## Baseline
- Before: backend 216 pass, 1 fail (`test_identity::test_nothing_readable_is_stored`, pre-existing), 1 skip
- After: backend 385 pass, 1 fail (same), 14 xfail, 47 skip (races, need Postgres); mobile 101 pass, 18 skip (bugs); dashboard 27 pass

## Files added
- backend/tests/test_qa_booking_{rules,isolation,payments,races}.py
- apps/mobile/test/qa_booking_{flow,api_errors}_test.dart
- apps/dashboard/src/components/qa-booking-checkin.test.tsx
- qa/booking/2026-10-25/* (rules, partial reports, verified.md, this report)

## Re-run
```bash
cd backend && .venv/Scripts/python.exe -m pytest tests/test_qa_booking_*.py -q
```
Postgres races: see `concurrency.md` (needs `-p qa_pg_plugin` until RACE-01 is fixed).

## Fixes (approved 2026-10-25)
All 17 fixed, uncommitted. Each QA test's xfail/skip marker removed; the tests now pass normally.
- Backend: RACE-02, RACE-04 (appointments.py), RACE-01 (conftest honours DATABASE_URL), API-01, SEC-01, SEC-03 (staff.py), API-03 (deps.recovery_patient on every patient recovery route, `403 recovery_locked`)
- Mobile: UX-01, UX-02, UX-03, UX-04, UX-05, UX-06, UX-08, UX-09, UX-10, UX-12
- Tests updated to the new rules: test_staff agenda test (clinic-wide agenda), test_staff sign-up tests (declare an ID before approval), test_recovery relapse test (locked before first paid visit), QA isolation super-admin alerts assertion (own list, never another doctor's)

### After fixes
- Backend SQLite: 448 tests, 1 failed (`test_identity::test_nothing_readable_is_stored`, pre-existing: Windows ignores file mode 0600), 55 skipped (Postgres-only), 0 xfail left for fixed findings
- Postgres races (no plugin): 47/47 pass, 3 runs
- Mobile: analyze clean, 295 pass, 0 fail, 2 skipped

### Follow-ups found while fixing
- Dashboard Approve button gets 409 `id_not_declared` for sign-ups with no ID: hide it or show an AR + FR message
- Agenda has no doctor field; add one if the dashboard should show whose visit it is
- Check-in / set-status / set-paid still limited to the caller's own appointments (PRD §4.3 says "own"; with clinic-wide agendas this is a question)
