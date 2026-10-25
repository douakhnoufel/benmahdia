---
name: booking-test-team
description: Runs a team of subagents that audits and tests the BenMahdia booking system end to end — backend API rules (holds, confirm, cancel, notice, 60-day window, ID gating), patient/doctor data isolation, Chargily payments and webhook, double-booking races on PostgreSQL, the Flutter booking flow, the dashboard Today/check-in page, and booking UX (Arabic RTL + French, error and empty states, design tokens). The team adds missing tests, writes a verified findings report against docs/PRD.md, then — after the user approves a fix plan — fixes the confirmed bugs in app code. Use this whenever the user wants to test, QA, audit, stress, review or "check" booking, appointments, slots, holds, payments, check-in codes or the booking screens — even if they only say "make agents test the app", "is booking solid?" or "find bugs in appointments".
---

# Booking test team

Orchestrate several subagents that each attack one side of the booking system, then have an independent verifier confirm every finding before it reaches the user. The output is (1) new tests in the repo, (2) one findings report, and (3) after the user approves a fix plan, fixes for the confirmed bugs. Testing and fixing are separate phases: testers never edit app code, so a test can't be bent to match a bug, and the user sees the plan before any app code changes (project rule: "Show me a plan before any big change").

Why a team: booking touches four codebases (FastAPI, PostgreSQL constraints, Flutter, React) and several kinds of risk (rules, security, money, races, UX). One agent doing everything tends to go deep on the first area and skim the rest. Specialists in parallel give even coverage; the verifier removes false positives, which matter a lot here because the user acts on this report.

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

### 0. Preflight (you, ~2 minutes)

Check what can run so agents don't waste time discovering it:

```bash
cd backend && python -m pytest -q -x 2>&1 | tail -5      # backend baseline
docker info >/dev/null 2>&1 && echo docker-ok              # needed for the Postgres race tests
flutter --version 2>/dev/null | head -1                    # mobile
cd apps/dashboard && npx vitest --version 2>/dev/null      # dashboard
```

Note the baseline: how many tests pass/fail *before* the team touches anything. Pre-existing failures are reported separately, not blamed on the team. Also note `git status` so you can show the user exactly what the team added.

Create the run folder `qa/booking/<YYYY-MM-DD>/` (agents drop their partial reports there).

### 1. Rules extraction (one agent, sequential)

Spawn one agent with the **rules-extractor** brief from `references/roles.md`. It reads the PRD sections above plus the booking code and returns `qa/booking/<date>/rules.md`: a numbered checklist (`R-01`, `R-02`, ...) of every testable booking rule, each with its PRD citation, where it is enforced in code (file:line) or "not found", and which existing test covers it (or "uncovered").

This runs first because every specialist needs the same rule list — otherwise each re-reads the PRD differently and the report can't be cross-checked.

### 2. Specialists (five agents, in parallel, one message)

Spawn all five in the **same message** so they run at once. Give each: the ground rules, the path to `rules.md`, its role brief from `references/roles.md`, and its owned files.

| Role | Covers | Owns |
|---|---|---|
| api-rules | holds, confirm, cancel, notice, 60-day window, slot grid, expiry, follow-up, ID gating, unlock after first paid appointment | `backend/tests/test_qa_booking_rules.py` |
| security-isolation | PRD §3 role matrix on every booking route (patient, doctor, shared/transferred patient, clinic staff, super admin), IDOR on every `{appointment_id}`, audit logs carry no medical content | `backend/tests/test_qa_booking_isolation.py` |
| payments | checkout, Chargily webhook signature, idempotency, abandoned/failed payment releases slot, never confirmed from app, check-in code rules | `backend/tests/test_qa_booking_payments.py` |
| concurrency | double-booking races on real PostgreSQL: same slot, overlapping slots, hold vs confirm vs expiry, cancel vs re-book | `backend/tests/test_qa_booking_races.py` |
| ux-clients | Flutter booking flow + dashboard Today/check-in: states, errors, AR RTL + FR strings, design tokens, PRD wording | `apps/mobile/test/qa_booking_*_test.dart`, `apps/dashboard/src/**/qa-booking*.test.tsx` |

Each specialist returns a partial report `qa/booking/<date>/<role>.md` using the finding format below, and the list of test files it added with the exact command it ran and the result.

### 3. Verification (one agent, sequential)

Spawn the **verifier** brief. It gets all partial reports. For each finding it re-reads the PRD citation and the code, re-runs the specific test, and marks it **CONFIRMED** (reproduced, PRD clearly requires the behaviour), **QUESTION** (PRD silent or ambiguous — needs the user), or **REJECTED** (test was wrong, misread rule, or duplicate). It also runs the whole new-test set once to confirm the suite is green with the xfail/skip markers in place.

The verifier is a different agent on purpose: specialists are motivated to find bugs, so they over-report. A fresh reader with no stake catches that.

### 4. Report (you)

Merge into `qa/booking/<date>/REPORT.md` using `references/report-template.md`. Then tell the user in chat, briefly:

- confirmed bugs (most severe first), questions for them, coverage of the rules checklist
- what was added (`git status` diff vs preflight) and the commands to re-run it
- what could not run and why

Then show a **fix plan**: one line per confirmed bug — root cause, files to change, size (small / medium / big), and the test that will prove it. Leave QUESTIONs out of the plan until the user answers them. Wait for the user's OK (they may pick a subset).

### 5. Fix (fixer agents, after approval)

Group approved bugs by files touched. One fixer agent per group; groups that touch different files run in parallel, overlapping groups run one after another. Each fixer gets the finding, its test, and the ground rules, and:

1. Changes the smallest amount of app code that makes the test pass, matching the surrounding style. Respects project rules: design tokens only, AR RTL + FR for any new string, no medical content in logs/notifications, API enforces access, migrations via Alembic for DB changes.
2. Removes the xfail / `test.fails` / `skip` marker so the test now passes normally.
3. Runs the area's full suite (not just the one test) to catch regressions.
4. Reports the diff summary and test results. Never weakens or deletes a test to make it pass — if the test itself looks wrong, it stops and says so.

Finally run every suite once more yourself and update REPORT.md with what was fixed. Offer small commits, one per fix plus one per area for the new tests; commit only when the user says so.

## Finding format

Every agent uses this so the verifier and report can merge mechanically:

```markdown
### <ROLE-PREFIX>-<NN>: <one-line title>
- Severity: critical | high | medium | low
- Rule: R-xx (PRD §x.y) — or "none (question)"
- Where: path/to/file.py:123
- Repro: test name in path, or exact steps
- Expected (PRD): ...
- Actual: ...
```

Prefixes: `API`, `SEC`, `PAY`, `RACE`, `UX`. Severity guide: **critical** = double-booking, another patient's data visible, appointment confirmed without payment; **high** = a rule from the PRD acceptance criteria broken; **medium** = rule broken outside acceptance criteria, or a missing error state; **low** = wording, token, or polish.

## Scaling down

If the user names one area ("just test payments"), run preflight, rules extraction, that one specialist, and the verifier. Skip roles that cannot run in this environment rather than faking them, and list them as "not run" in the report.
