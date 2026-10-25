# Fixer rules (approved by the user: fix all 17 confirmed bugs)

Read first: qa/booking/2026-10-25/ground-rules.md, qa/booking/2026-10-25/verified.md (your findings), and step 5 "Fix" in .claude/skills/booking-test-team/SKILL.md.

- Fix ONLY your assigned findings, ONLY in your assigned files. Other fixer agents are editing other files at the same time. If a fix needs a file outside your list, stop and report instead of editing it.
- Smallest change that makes the finding's test pass, matching surrounding style and comment density.
- Keep each fix a separate, self-contained change (the user wants one small commit per fix later). Do NOT run git commit, git add, git stash or git checkout.
- Remove the xfail(strict) / skip / test.fails marker for each fixed finding so its test passes normally. Never weaken or delete a test to make it pass; if a test looks wrong, stop and say so.
- Project rules: design tokens only; every new user-facing string in Arabic (RTL) AND French; no medical content in logs or notifications; access enforced in the API; DB changes via a new Alembic migration (next number after the latest in backend/alembic/versions).
- Run your area's FULL suite after your fixes, not only the one test, and report real results.
- Postgres is running: container benmahdia-db-1, 127.0.0.1:5432, benmahdia/benmahdia/benmahdia. Do not stop it. Use 127.0.0.1, not localhost.

Reply with: per finding — fixed or not, files changed, one-line description; marker removals; exact commands run and results.
