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
- `backend/tests/test_cravings.py`: 9 tests. **8 passed; the window test was
  just rewritten** (old row moved back 40 days in the DB instead of advancing the
  clock, which tripped token expiry) and **has not been run yet**. Run:
  `cd backend && .venv/Scripts/python -m pytest tests/test_cravings.py -q`.

## Still to do (mobile)
- `lib/features/craving/`: `craving_models.dart`, `craving_repository.dart`
  (interface + provider switched on `API_BASE_URL`, same as recovery),
  `fake_craving_repository.dart`, `api_craving_repository.dart`,
  `breathing_circle.dart` (inhale 4 · hold 4 · exhale 6; still under reduced
  motion), `difficult_moment_screen.dart` (intensity 1–10, HALT chips, breathing,
  rotating tip, if-then plan + call clinic, clinic open/closed, companion link,
  urgent help via existing `showCrisisSheet`, "craving passed" → before/after).
- `lib/widgets/sharing_label.dart`: "Only you" / "Your doctor sees this".
- Touch: `recovery_screen.dart` (entry card only), `app_tokens.dart` (breathing
  timings), `local_store.dart` (if-then plan), `app_ar.arb` / `app_fr.arb`
  (~30 `moment…` keys) + `flutter gen-l10n`.
- Tests: `test/difficult_moment_test.dart`, `test/sharing_label_test.dart` (ar+fr,
  reduced motion).
- Push screens with `Navigator.of(context).push` like `recovery_screen.dart`; no go_router.
- After: rerun the four checks, run on the phone, summary + changed files.

## Repo cautions
- Another session (`benmahdia-0f`) works in this repo and commits whatever is
  staged: always `git add` files by name, never `-A`. Never commit `.env`.
- Its uncommitted edits (profile/scan files, l10n generated files) are not ours.
- Step 0 leftovers: dashboard logo + favicon (from `logo.png`), Android
  notification icon (white-only; needs the user's OK to derive it).
