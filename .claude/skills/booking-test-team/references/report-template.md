# Booking QA — <YYYY-MM-DD>

## Summary
- Confirmed bugs: <n> (critical <n>, high <n>, medium <n>, low <n>)
- Questions for you: <n>
- Rules covered: <covered>/<total> (was <before>/<total>)
- New tests: <n> passing, <n> xfail/skip marking confirmed bugs
- Not run: <area — reason>, or "none"

## Confirmed bugs
<!-- most severe first; use the finding format from SKILL.md, verdict CONFIRMED only -->

## Questions (PRD silent or ambiguous)
<!-- one line each: what the code does today, what the PRD says, what we need you to decide -->

## Rejected findings
<!-- one line each with reason, so the user can see the verifier worked -->

## Baseline
- Before: <backend pass/fail>, <mobile>, <dashboard>
- After: <same>, pre-existing failures listed separately

## Files added
<!-- from git status vs preflight -->

## Re-run
```bash
cd backend && python -m pytest tests/test_qa_booking_*.py -q
```
<!-- plus mobile/dashboard/Postgres commands actually used -->
