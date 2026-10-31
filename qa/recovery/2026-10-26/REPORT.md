# Recovery QA — 2026-10-26 (finished 2026-10-30)

Scope: the recovery pillar (PRD §3 addictions, §5 unlock, §5.1–5.6, §7 alerts and patient file, §8.3, §8.6, §12.3). Booking, articles and the AI companion are out of scope. Code under test: `c772566`, unchanged for the whole run.

Every finding was checked by an independent verifier. The full table, with the PRD wording, code lines and each test's failure message, is in [verified.md](verified.md). The partial reports are [api-rules.md](api-rules.md), [security-isolation.md](security-isolation.md), [alerts-privacy.md](alerts-privacy.md) and [ux-clients.md](ux-clients.md). The rules checklist is [rules.md](rules.md).

## Summary

- **Confirmed bugs: 31.** 1 critical, 2 high, 15 medium, 13 low.
  - 11 of these are PRD features that were never built (see "Not built").
- **Questions for you:** 15 PRD gaps (listed at the end). SEC-02 is still the main one.
- **Rejected findings:** none.
- **Rules covered:** 124 of 130 now have a test. Before the run, 92 of 130 had one.
- **New tests:**
  - Backend: 138 passing, 3 PostgreSQL-only skips, 30 strict xfails marking bugs.
  - Mobile: 87 passing, 64 skipped as bug tests.
  - Dashboard: 24 passing, 4 of them `it.fails` marking bugs.
- **Not run:**
  - The full Flutter suite (only the two QA files ran).
  - Anything on a real device: TalkBack/VoiceOver, notifications, FLAG_SECURE.
  - Mobile time-zone behaviour, because this machine is already on Algiers time.

## Confirmed bugs

Most severe first. Ids are the testers'; merged ids are shown in brackets.

### Critical

| ID | Bug | Where | Proving test |
|---|---|---|---|
| SEC-07 (+API-04, API-05) | Two near-simultaneous first saves of a daily check end in an unhandled `IntegrityError` (500). The server log then prints the answers: craving, signals and their values. The same select-then-insert race gives a 500 on a habit tick, a v1 tick and a dose answer. This was confirmed through a live uvicorn run and on PostgreSQL, where 77 to 97 of 240 duplicate saves were 500s. | `addiction_checks.py:150-164`, `habits.py:200-203`, `checkins.py:59-64`, `medications.py:278-289`, `db.py:24` (no `hide_parameters`) | `test_qa_recovery_isolation.py::test_a_second_simultaneous_first_save_of_a_check_is_not_a_500` and 5 more |

### High

| ID | Bug | Where | Proving test |
|---|---|---|---|
| UX-07 | Medication reminders are not built: there is no local dose reminder and no Snooze button (PRD §5.3). | `recovery_widgets.dart:637-787`, `recovery_reminders.dart` | `qa_recovery_flow_test.dart` "UX-07 …" |
| SEC-06 | A doctor reading a patient's addictions, checks, habits or medications writes no audit row (PRD §8.3). | `staff_recovery.py:57`, `addiction_checks.py:254`, `habits.py:232`, `medications.py:155` | `test_qa_recovery_isolation.py::test_a_doctor_reading_clinical_data_is_audited` |

### Medium

| ID | Bug | Where |
|---|---|---|
| API-01 (+API-03) | Checks, habits and ticks use the UTC date, not the Algiers day. Between 00:00 and 01:00 in Algiers, the edit lock, the week strip, the doctor's chart and the habit summary all use the wrong day. | `addiction_checks.py:108,158,196,267`, `habits.py:241`, `checkins.py:31` |
| ALERT-01 | A high-craving day saved after its nightly run never completes a `craving_high` run. | `alerts_job.py:79-127` |
| ALERT-02 | Deleting the account does not notify the doctor (PRD §12.5; the code has a TODO). | `me.py:65` |
| UX-01 | Every server refusal on a recovery save reads "check your connection". A lock on a dose answer or a relapse shows nothing at all. | `api_recovery_repository.dart:56-61`, `recovery_screen.dart:187-222` |
| UX-03 | Dashboard: a failed confirm/reject, "mark read" or medicine "stop" shows the doctor no message. | `PatientDetail.tsx:79-88,244-254`, `Alerts.tsx:26-37` |
| UX-05 | The counter shows days only. PRD §5.1 says "days (and hours)". | `recovery_widgets.dart:91-96` |
| UX-06 | Reaching the 4-week small goal is not celebrated. | `recovery_screen.dart:114-140` |
| UX-08 | A screen reader cannot press the 1–5 ratings, the habit tick, the clean-since date, the relapse time or the habit reminder. | `tracking_widgets.dart:120,471`, `addiction_form_screen.dart:156`, `recovery_widgets.dart:330` |
| UX-11 | The milestone celebration does not scroll, so at two years of badges Continue falls off a small screen. | `milestone_screen.dart:53-118` |
| SEC-08, API-09, API-10, API-13, API-14, UX-16 | Not built (see below). | — |

### Low

| ID | Bug | Where |
|---|---|---|
| API-06 | The HH:MM check accepts a trailing newline and non-ASCII digits. On PostgreSQL, `"21:30\n"` gives a 500. | `checkins.py:28`, `medications.py:39` |
| ALERT-03 | `no_checkin` ignores checks on an addiction added in the last 3 days. The fix depends on question Q-05. | `alerts_job.py:134-143` |
| UX-02 | The relapse note and the exact substance have no length limit in the app, though the server caps them at 500/100. | `recovery_widgets.dart:351`, `addiction_form_screen.dart:145` |
| UX-04 | A double tap sends two requests on Taken, the day tick, the habit tick, habit remove and stop reminder. | `recovery_screen.dart` (5 places) |
| UX-09 | The 1–5 rating circles are 44 px high, below 48×48. | `tracking_widgets.dart:125-141` |
| UX-10 | In Arabic the "pills" type is called "hallucinogenic pills", and its name differs between the app and the dashboard. PRD §3 says "psychotropic". | `app_ar.arb:503`, `app_fr.arb:333`, `i18n.tsx:106,286` |
| UX-12 | The next-visit date tile clips the French month at 1.3× text. | `recovery_widgets.dart:574-597` |
| UX-13 | Cairo and Inter are not bundled, so the app uses system fonts. | `apps/mobile/pubspec.yaml` |
| UX-14 | Dashboard Arabic day counts are not pluralised ("9 يوم"). | `i18n.tsx:135` |
| UX-15 | The recovery screens use values that are not tokens: `AppSpace.xs + 2`, a button height of 44 instead of 52, and Tailwind arbitrary values. | see verified.md |
| API-11, API-12, UX-17 | Not built (see below). | — |

### Not built (PRD features with no code)

| ID | Sev | Feature | PRD |
|---|---|---|---|
| UX-07 | high | Local dose reminders with Taken / Skipped / Snooze | §5.3 |
| SEC-08 | medium | Screenshot blocking on sensitive screens | §8.3 |
| API-09 | medium | The doctor records triggers and a severity level per addiction | §3, §9 |
| API-10 | medium | The doctor sees medication adherence | §7 |
| API-13 | medium | Quote library managed by the super admin; doctors add their own quotes | §5.2 |
| API-14 | medium | The doctor corrects the clean-since date, the substance or the type | §3 |
| UX-16 | medium | Streak history chart, patient-list filters, mobile doctor view | §7 |
| API-11 | low | The doctor edits a medication schedule | §7 |
| API-12 | low | Quote of the day picked by recovery stage | §5.2 |
| UX-17 | low | Quote favourites and share-as-image | §5.2 |
| UX-13 | low | Cairo and Inter fonts bundled | DESIGN §2 |

### Carried from the booking QA (not new)

- **SEC-02 (open question):** any doctor with a non-hold booking reads all 5 clinical routes. That includes a cancelled-only booking or a future one. Such a doctor can also stop another doctor's prescription and receives that patient's relapse, craving and milestone alerts. 7 xfail tests pin it.
- **SEC-04:** there is no clinic-staff role. "Staff never see clinical data" holds only because no such role exists.

## Questions (PRD silent or ambiguous)

1. **SEC-02 / G-01: primary doctor, sharing and transfer.** Which doctor owns clinical access, and which one gets each alert? Can a doctor stop another doctor's prescription?
2. **G-02: what happens after a paid visit is cancelled.** Today recovery locks again. The doctor keeps the file and missed-dose alerts keep firing. Is that right?
3. **G-03: whose "day".** Do checks, habits, ticks and the edit lock follow the Algiers day? This sets the API-01 fix. Should an answer about tomorrow be accepted (API-02, API-18)? Should the app show Algiers time or the phone's time (Q-UX-1)?
4. **G-04: "missed doses on 2+ days".** Does "skipped" count as missed? Does one dose of two clear the day? Do days before the course was entered count?
5. **G-05 / G-18: alert repeats and inbox order.** Today missed_doses repeats daily and craving_high/no_checkin every 3 days, and the inbox is newest-first. Is that what you want?
6. **Q-05 / G-06: daily check with several addictions.** For `no_checkin`, does a check on any addiction count, or must every addiction be checked? Should a patient with no addiction ever get `no_checkin`?
7. **G-07: pending and rejected addictions.** Should a pending addiction raise alerts before the doctor reviews it? Should a rejected one still take relapses, goals and pick the quote?
8. **G-08 / G-09: relapse and corrections.** Is a relapse's "note or trigger" one field? Which fields may the doctor correct?
9. **G-10: goals after day 28.** May the patient choose 60/90/180/365 as a small goal?
10. **G-11 / API-19: medications.** What does Snooze do? Should the doctor edit a schedule or stop and recreate it? Should a stopped course stay in the patient's history?
11. **G-12: accounts being deleted or locked again.** Should nightly alerts stop for them?
12. **G-13: quotes.** What is a "recovery stage"? Who adds, edits and deactivates quotes?
13. **G-14: limits the PRD doesn't state.** 10 addictions, a 500-character note, 60-character habit words, 6 dose times, 90 chart days.
14. **Q-UX-2/3/4: smaller UI decisions.**
    - The wording for each refusal code (needed for UX-01).
    - The direction of the 30-day chart in Arabic.
    - Whether the patient may cancel the relapse sheet after answering "No".
15. **Smaller confirmations.**
    - The doctor sees the words of a custom habit (G-19).
    - Wording for buprenorphine or pregabalin taken as prescribed (G-17).
    - Whether a double "I relapsed" counts as one event (API-15).

## Rejected findings

None. Every xfail, Flutter bug test and `it.fails` fails on its own assertion. No test needed a fix.

## Baseline

| Suite | Before the team | After |
|---|---|---|
| Backend (SQLite, full) | 1 failed, 479 passed, 47 skipped, 8 xfailed | 1 failed, 617 passed, 50 skipped, 38 xfailed |
| Mobile (QA files) | — | 87 passed, 64 skipped |
| Dashboard (full) | — | 7 files, 114 passed |

The one backend failure is pre-existing: `tests/test_identity.py::test_nothing_readable_is_stored`. The whole difference is the three new QA files: +138 passed, +3 skipped, +30 xfailed. The team broke nothing.

## Files added

- `backend/tests/test_qa_recovery_rules.py`
- `backend/tests/test_qa_recovery_isolation.py`
- `backend/tests/test_qa_recovery_alerts.py`
- `apps/mobile/test/qa_recovery_flow_test.dart`
- `apps/mobile/test/qa_recovery_privacy_test.dart`
- `apps/dashboard/src/test/qa-recovery.test.tsx`
- `qa/recovery/2026-10-26/`: this report, `verified.md`, the four partial reports, `rules.md` and the baseline files

No app code was changed.

## Re-run

```bash
cd backend && .venv/Scripts/python.exe -m pytest tests/test_qa_recovery_rules.py tests/test_qa_recovery_isolation.py tests/test_qa_recovery_alerts.py -q -o addopts=""
cd apps/mobile && flutter test test/qa_recovery_flow_test.dart test/qa_recovery_privacy_test.dart --no-pub
cd apps/dashboard && npx vitest run src/test/qa-recovery
```

To see the bugs fail, pass `--runxfail` to pytest, `--dart-define=QA_RUN_BUGS=true` to Flutter, or set `QA_RUN_BUGS=true` for vitest.

The PostgreSQL-only race tests need a database. Set `DATABASE_URL=postgresql+psycopg://benmahdia:benmahdia@127.0.0.1:5432/<scratch db>` and add `-k "parallel or simultaneous or plain_ascii"`.
