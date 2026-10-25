## Ground rules (pass these to every agent)

These come from the project's CLAUDE.md and apply to every subagent, so paste them into each brief:

- Source of truth is `docs/PRD.md` (booking: §4.2 gating, §4.3, §4.4, §5 unlock, §7 dashboard, §8.6 localisation, §12.2 workflow) and `docs/DESIGN.md`. A behaviour the PRD does not specify is a **question**, not a bug.
- Testers (steps 1–3) do not edit app code (`backend/app`, `apps/*/lib`, `apps/dashboard/src` outside test files). Only fixers in step 5 do, and only after the user approves the plan.
- Access is the PRD §3 role matrix, not "everyone sees only their own": patient = only self; doctor = every appointment and agenda in the clinic (booking data is clinic-wide), but clinical data (notes, medications, addictions, AI chats/flags) only for own patients plus shared or transferred ones; clinic staff / secretary = ID queue and front-desk check-in, never clinical data (notes, meds, chats); super admin = doctor rights plus admin screens, never other doctors' notes or chats. Where the PRD leaves a case open (e.g. how "shared" is recorded, which doctors a secretary serves), report a QUESTION, don't guess.
- Each agent writes only to the files it owns (listed per role) so parallel agents never collide.
- No real patient data: fake names, Algerian test phones like `06612345NN`, seeded doctors.
- No medical content in test logs, fixtures, or notification assertions.
- A test that exposes a real bug stays in the suite but must not break it: pytest `@pytest.mark.xfail(strict=True, reason="QA <ID>: <one line>")`, vitest `test.fails(...)`, Flutter `skip: 'QA <ID>: <one line>'`. Strict xfail means that when the bug is fixed the test flips to failing and someone removes the marker.
- Never claim a test passed without running it. If something could not run (no Docker, no Flutter SDK), say so plainly.

## Workflow

## Environment facts (from preflight, 2026-10-25)
- Repo root: C:\Users\noufe\OneDrive\Desktop\benmahdia (Windows; Bash tool is Git Bash).
- Backend Python: backend/.venv/Scripts/python.exe  (run: cd backend && .venv/Scripts/python.exe -m pytest ...)
- Backend baseline: 216 passed, 1 failed (tests/test_identity.py::test_nothing_readable_is_stored — pre-existing, not ours), 1 skipped (test_concurrent_holds, needs Postgres).
- Docker: NOT available. Postgres race tests cannot run this time.
- Flutter: C:/src/flutter/bin/flutter.bat (not on Bash PATH; call by full path or export PATH="/c/src/flutter/bin:$PATH").
- Dashboard: node_modules missing; run `npm install` in apps/dashboard before vitest.
- Run folder: qa/booking/2026-10-25/
- Finding format and severity guide: see "Finding format" in .claude/skills/booking-test-team/SKILL.md.
