# Handoff — step 1 "difficult moment" (branch feat/clinic-logo)

Brief: `docs/specs/TERMINAL_PROMPT.md`. Design: `docs/specs/habit-tracking-design.md`.
Rules: plan first, additive only, ar+fr strings, design tokens only, run the four
checks before and after, stop after each step with a summary and changed files.

## Decisions taken by the user (2026-11-02)
1. Craving logs are saved on the **server** (doctor sees them): sharing label
   "Your doctor sees this" on the screen.
2. **Rotating tips**: spicy food (harissa, hot pepper), mint gum, a glass of
   water, a short walk. The clinic must approve the wording before launch; a
   per-patient on/off for the doctor comes later.
3. The **if-then plan** ("When ___, I will ___") is written by the patient and
   kept **on the phone** ("Only you"). The doctor's support plan comes later.
4. Show **clinic open now / closed** from the existing `ClinicInfo.hours`.
5. **No new doctor alert** in step 1 (the daily check's `craving_high` exists).
- HALT chips: 5 (hungry, angry, lonely, tired, other) — the spec wins over the brief's 4.
- Migrations: the repo was at 0020, so step 1 uses **0021** (the brief said 0011).
- Tokens: teal fills `AppColors.teal600` (#0c8578), teal text `teal700`.

## Baseline (before any step-1 code)
- `flutter analyze`: no issues. `flutter test`: 451 passed, 23 skipped.
- Dashboard `npm run typecheck`: clean. (Dashboard vitest has 19 failures on a
  clean tree; not part of the comparison.)
- Backend pytest: run started, result not recorded — rerun before comparing.

## Done (backend, committed as wip)
- `backend/app/models.py`: `CravingLog` (patient FK cascade, started_at,
  intensity_before 1–10, triggers JSON, passed_at, intensity_after 1–10). No free text.
- `backend/alembic/versions/0021_craving_logs.py`: new table + index.
- `backend/app/routers/cravings.py`:
  - `POST /v1/me/cravings` {intensity, triggers[]} → 201
  - `PATCH /v1/me/cravings/{id}` {intensity} → passed, once only (409 `craving_already_passed`)
  - `GET /v1/me/cravings?days=30` (1–90), newest first
  - `GET /v1/staff/patients/{id}/cravings` via `clinic_patient` (colleague access audited)
  - Path is `/v1/me/cravings` to match `/v1/me/habits` (the plan said `/v1/recovery/cravings`).
- `backend/app/main.py`: both routers registered.
- `backend/tests/test_cravings.py`: 9 tests, **all passing**. The window test
  was failing: the conftest clock is frozen, so two cravings logged in one test
  got the same `started_at` and "newest first" had no defined order. It now
  calls `advance(minutes=5)` between the two rows. Run:
  `cd backend && .venv/Scripts/python -m pytest tests/test_cravings.py -q`.

## Done (mobile, branch feat/difficult-moment-mobile)
- `lib/features/craving/craving_models.dart`: `CravingTrigger` (HALT, 5),
  `CravingLog`, `IfThenPlan`, `CravingAlreadyPassed` (extends
  `RecoveryUnavailable`), intensity bounds 1–10.
- `craving_repository.dart` (interface + provider switched on `API_BASE_URL`),
  `fake_craving_repository.dart` (`locked` / `failing` / `seed` for tests),
  `api_craving_repository.dart` (same http plumbing as recovery: 401 refresh
  once, `recovery_locked`, 409 → `CravingAlreadyPassed`, malformed answer →
  `RecoveryUnavailable`, never a crash).
- `breathing_circle.dart`: inhale 4 · hold 4 · exhale 6 from the new
  `AppMotion.breatheInMs/HoldMs/OutMs`; under reduced motion it is still and
  shows one calm instruction with no countdown.
- `difficult_moment_screen.dart`: four steps (start → breathing → closing →
  passed) with intensity 1–10 (44 px targets that wrap), HALT chips, rotating
  tip (spicy · mint gum · water · walk), the if-then plan, clinic open/closed
  from `ClinicInfo.hours` + tap to call, companion link, urgent help in the
  app bar at every step, then before → after. Also `DifficultMomentCard` and
  `openDifficultMoment` for the way in.
- `lib/widgets/sharing_label.dart`: "Only you" (lock) / "Your doctor sees
  this" (eye).
- Touched: `recovery_screen.dart` (entry card above the daily check only),
  `app_tokens.dart` (breath timings), `local_store.dart` (if-then plan; the
  write is fire-and-forget like `writeLocale` / `writeSession` — an awaited
  secure-storage write never completes under `flutter test`), `app_ar.arb`
  (60 entries) / `app_fr.arb` (58) + `flutter gen-l10n`.
- Tests: `test/difficult_moment_test.dart` (12), `test/sharing_label_test.dart`
  (3), ar + fr, reduced motion, failing-save path. The sample clinic answers
  after 200 ms, so those tests wait for it explicitly.

## Still to do (step 1)
- Run it on the phone (ARTEMIS or a device) and look at the screen.
- The clinic must approve the four tip wordings before launch; a per-patient
  on/off for the doctor comes later.
- A month chart of cravings and the trigger insight from the design's
  "craving passed" screen are not built: step 1 shows before → after only.

## Repo cautions
- Another session (`benmahdia-0f`) works in this repo and commits whatever is
  staged: always `git add` files by name, never `-A`. Never commit `.env`.
- Its uncommitted edits (profile/scan files, l10n generated files) are not ours.
- Step 0 leftovers: dashboard logo + favicon (from `logo.png`), Android
  notification icon (white-only; needs the user's OK to derive it).
