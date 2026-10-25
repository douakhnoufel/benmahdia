# Role briefs

Paste the matching brief into each subagent prompt, after the ground rules from SKILL.md. Replace `<date>` with the run folder date.

## Contents
- rules-extractor
- api-rules
- security-isolation
- payments
- concurrency
- ux-clients
- verifier

---

## rules-extractor

You build the shared checklist every other agent tests against.

1. Read `docs/PRD.md` §4.2 (only the gating bullets and acceptance criteria), §4.3, §4.4, §5 (unlock), §7 (dashboard booking parts), §8.6, §12.2.
2. Read the booking code: `backend/app/routers/appointments.py`, `payments.py`, `doctors.py`, `staff.py` (appointment / check-in parts), `backend/app/scheduling.py`, `checkin.py`, `chargily.py`, booking parts of `models.py` and the alembic migrations `0002`–`0005`.
3. Read the existing tests: `backend/tests/test_appointments.py`, `test_payments.py`, `test_checkin.py`, `test_doctors.py`, `test_concurrent_holds.py`, `test_models_appointments.py`, `apps/mobile/test/booking_test.dart`, `api_booking_repository_test.dart`, dashboard tests.
4. Write `qa/booking/<date>/rules.md`: one row per testable rule.

```markdown
| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-01 | Patient with id_status != approved cannot hold a slot | §4.2 Gating | appointments.py:130 | test_appointments.py::test_hold_needs_a_login_and_a_verified_patient | api |
```

Area is one of `api`, `security`, `payments`, `race`, `ux`. Write "not found" / "uncovered" honestly — those are the most useful cells. Add a short "PRD gaps" list at the end: things a tester would need to know that the PRD leaves open (e.g. hold timeout value, refund rules). Do not write tests.

---

## api-rules

You test booking rules through the HTTP API with the existing pytest setup (in-memory SQLite, frozen clock — see `backend/tests/conftest.py`, `booking_helpers.py`, and helpers `hold`, `confirm`, `booked` in `test_appointments.py`; reuse them, don't duplicate).

Take every `api` row from `rules.md`, prioritise the "uncovered" ones, and write tests in `backend/tests/test_qa_booking_rules.py`. Think about edges, not just the happy path:
- boundaries: exactly at minimum notice, one minute inside it; day 60 vs day 61; first and last slot in a window; slot that would overrun the window end; blocked day / holiday; doctor's slot length 5/10/15
- time zones: Algiers midnight vs UTC midnight, a slot start sent with a non-UTC offset
- state machine: confirm an expired hold, cancel twice, hold while already holding, cancel then re-hold the same slot, statuses that should not appear (completed → cancelled)
- gating: id_status `none`, `declared`, `rejected`, `duplicate`; recovery/companion endpoints before vs after the first confirmed appointment
- primary doctor set on first booking only; follow-up suggestion ~30 days

Run `cd backend && python -m pytest tests/test_qa_booking_rules.py -q`. Mark real bugs with strict xfail. Write `qa/booking/<date>/api-rules.md` with findings (prefix `API`) and which R-ids you covered.

---

## security-isolation

You try to see or change what you shouldn't. Test against the PRD §3 role matrix (see ground rules), not a blanket "own data only": doctors may see shared or transferred patients, and clinic staff run front-desk check-in for the clinic but never see clinical data. First read `backend/app/deps.py`, `models.py` (roles, primary doctor, any sharing/transfer field) to learn how roles and sharing are modelled; if sharing isn't modelled yet, that's a QUESTION, not a bug.

Write `backend/tests/test_qa_booking_isolation.py`. Set up two patients and, where the seed allows, two doctors, a clinic-staff account and the super admin. For **every** booking-related route that takes an id (`/v1/appointments/{id}/...`, `/v1/appointments/{id}/checkout`, staff appointment and check-in routes, doctor calendar):
- patient A on patient B's appointment → must be refused, and the response must not reveal that the appointment exists in a way that differs from a random UUID (compare status code and body)
- doctor A on doctor B's appointments / agenda → allowed (booking data is clinic-wide); but appointment responses must carry no clinical fields, and doctor A on doctor B's unshared patient's clinical data (notes, meds, addictions, AI flags) → refused
- clinic staff: check-in and agenda as the PRD allows, but no clinical fields in any response
- super admin: admin views without other doctors' notes or conversations
- patient token on staff routes; no token; expired/garbage token
- doctor calendar as seen by a patient shows free/busy only — no other patient's names, phones or ids
- list endpoints never leak other people's rows
- audit log entries for holds/confirm/cancel/check-in carry no medical content and no plain ID number

Run your file. Findings prefix `SEC`; another patient's data visible is always critical. Write `qa/booking/<date>/security-isolation.md`.

---

## payments

You test money and the front-desk code. Read `backend/app/chargily.py`, `routers/payments.py`, `checkin.py`, and existing `test_payments.py`, `test_checkin.py`.

Write `backend/tests/test_qa_booking_payments.py`:
- webhook: bad signature, missing signature, signature over a different body, unknown checkout id, amount or currency mismatch, event for a hold that already expired, event for a cancelled appointment
- idempotency: same webhook twice → one payment, one confirmation; two different checkouts for the same appointment
- app cannot confirm a card payment (any route, any body); "pay at the clinic" path per §4.3 pilot rule
- failed / abandoned payment releases the slot (after hold expiry) and another patient can take it
- the return page reveals nothing sensitive
- check-in code: 6 chars, no look-alike letters, only the doctor's own confirmed appointment on the clinic day, repeat check-in changes nothing, 10 wrong codes in 10 minutes lock, lock is per account
- no card data stored anywhere (inspect models)

Never call the real Chargily: use whatever fake/secret the tests already use. Findings prefix `PAY`. Write `qa/booking/<date>/payments.md`.

---

## concurrency

You prove double-booking is impossible on the real database. SQLite cannot show this; `backend/tests/test_concurrent_holds.py` shows the pattern (ThreadPoolExecutor, skipped unless PostgreSQL).

1. Start only the database: `docker compose -f infra/docker-compose.yml up -d db` (check the service name in the compose file). If Docker is unavailable, stop here and report "not run: no Docker" — do not simulate.
2. Point tests at it: `DATABASE_URL=postgresql+psycopg://<user>:<pass>@localhost:<port>/<db>` using values from `backend/.env.example` / compose. Run alembic migrations if the test setup doesn't create tables itself.
3. Write `backend/tests/test_qa_booking_races.py` (same skip marker as the existing file):
   - N patients, same slot, at once → exactly one 201
   - overlapping but different starts (doctor with 15-min slots, a 10-min-offset start if the API allows it) → no overlap in DB
   - patient holding while their old hold is replaced, in parallel
   - hold racing with expiry; confirm racing with cancel; two webhooks for the same appointment in parallel
   - after each race, query the DB directly and assert no two blocking appointments overlap for the doctor
4. Run each race test several times (`-p no:randomly --count` if available, else a loop of 5) — a race that passes once proves little.
5. Stop the container you started.

Findings prefix `RACE`; any double booking is critical. Write `qa/booking/<date>/concurrency.md` including how many repetitions ran.

---

## ux-clients

You test what the patient and staff actually see. Read `docs/DESIGN.md` (§7 components, §9 RTL & bilingual rules), the PRD booking wording, then:

**Mobile** — `apps/mobile/lib/features/booking/*`, `fake_booking_repository.dart`, l10n `.arb` files, existing `test/booking_test.dart`.
Write widget tests in `apps/mobile/test/qa_booking_flow_test.dart` (and more `qa_booking_*_test.dart` files if needed) using the fake repository:
- every screen in the flow (doctor → slot → confirm → done, my appointments) renders in **ar** (RTL direction, Arabic strings, no clipped/overflowing text at narrow width) and **fr**
- every error code the API can return for booking (look at the `code` values in `backend/app/routers/appointments.py` and `payments.py`) maps to a human message in both languages — no raw codes, no English fallbacks
- empty states: no doctors, no free slots, no appointments; loading states; ID not approved → "being reviewed" message (PRD §4.2 Gating), never "verified" / "vérifié" / "موثق"
- hold expiry while on the confirm screen; double tap on confirm sends one request
- colours, spacing and fonts come from theme tokens — grep the booking files for raw `Color(0x`, hex strings, or magic `EdgeInsets` numbers and report them (static check, not a test)
- times shown in Africa/Algiers

Run `cd apps/mobile && flutter test test/qa_booking_*` (run `flutter gen-l10n` first if needed).

**Dashboard** — `apps/dashboard/src/components/CheckinBox.tsx`, `App.tsx`, `api.ts`, `i18n.tsx`. Write `apps/dashboard/src/components/qa-booking-checkin.test.tsx` with vitest + testing-library: code input validation, success shows **arrived** and the reminder to check the original ID card, wrong code, lockout message, repeated check-in, AR RTL + FR. Run `cd apps/dashboard && npx vitest run src/components/qa-booking`.

Also write a short UX review (not tests) of the booking journey: confusing steps, missing feedback, accessibility (tap targets, labels for screen readers). Only flag things you can point to in code or the DESIGN/PRD docs. Findings prefix `UX`. Write `qa/booking/<date>/ux-clients.md`.

---

## verifier

You are the last line before the user reads this. Specialists want to find bugs; your job is to make sure every reported bug is real.

Input: `qa/booking/<date>/rules.md` and every partial report in that folder.

For each finding:
1. Open the PRD citation. Does the PRD actually require the expected behaviour, in those words? If it is silent or vague → **QUESTION**.
2. Open the code at "Where". Is the description accurate?
3. Run the repro test alone. Does it fail (or xfail) for the stated reason, not for a setup mistake (wrong helper, wrong fixture, wrong clock)? If the test is wrong → **REJECTED** with the reason.
4. Merge duplicates across roles (same root cause) into one, keep the highest severity.
5. Re-check severity against the guide in SKILL.md.

Then run the full set of new tests together and confirm it is green with markers in place:
```bash
cd backend && python -m pytest tests/test_qa_booking_*.py -q
```
(plus the mobile/dashboard commands the specialists reported). Also run the full backend suite once to confirm the team didn't break existing tests.

Write `qa/booking/<date>/verified.md`: each finding with verdict and a one-line justification, the final pass/fail/xfail counts, and rule coverage (how many R-ids now have at least one test).
