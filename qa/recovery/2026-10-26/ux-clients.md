# UX (clients) — recovery QA 2026-10-26

Agent: ux-clients (prefix UX). Scope: what the patient sees in Recovery (`apps/mobile`: locked tab, home, daily check, addiction form, habits, small goals, relapse, milestone) and what the doctor sees in the dashboard (`PatientDetail.tsx`, `Tracking.tsx`, `Alerts.tsx`). No app code was changed.

- **HEAD at start:** `c772566`. **HEAD at end:** `c772566`. The code under test did not change during the run.
- **Working tree:** the preflight snapshot showed `Alerts.tsx`, `i18n.tsx` and `booking-alerts.test.tsx` modified by another session. During this run (`git status`), those files were clean and matched HEAD. The dashboard tests ran against what is on disk, which is HEAD.
- **Resumed run:** an earlier attempt left `apps/mobile/test/qa_recovery_flow_test.dart` written but never run. I ran it as found (it compiled and passed). I then checked that every bug test fails for its stated reason, added 6 tests, and wrote the dashboard file and this report.

## Tests added

| File | Tests | Pass | Marked as known bug |
|------|-------|------|---------------------|
| `apps/mobile/test/qa_recovery_flow_test.dart` | 141 | 77 | 64 (group `skip: 'QA UX-NN: …'`) |
| `apps/dashboard/src/test/qa-recovery.test.tsx` | 24 | 20 | 4 (`it.fails`, UX-03 ×3, UX-14) |

How the bug tests work:
- **Flutter:** `testWidgets` takes only a boolean skip, so each bug test sits in a `group(…, skip: 'QA UX-NN: …')`. Pass `--dart-define=QA_RUN_BUGS=true` to run them. I did, and all 64 fail for the reason in their finding.
- **Dashboard:** `QA_RUN_BUGS=true` turns each `it.fails` back into a plain `it`. All 4 fail, either with `Unable to find role="alert"` or with `expected '9 يوم' to be '9 أيام'`.

**Mobile coverage.** Every check runs in Arabic (RTL) and French (LTR) unless noted.
- **Locked tab:** lock icon, title, why, and a Book button that opens appointments. The locked tab makes no other API call.
- **Home:** one ring per addiction, filling toward its own small goal (9→14, 40→60), the quote, today's doses with the taken count, and the longest and total stats.
- **Waiting for review:** the hourglass pill.
- **Daily check:** each of the 6 profiles plus generic asks craving and exactly its two signals from the PRD §5.6 table (generic asks craving only). Save stays off until everything is answered and says why. Saving marks today on the week strip.
- **Forms and sheets:** the addiction form (profiles, "other substance" and its 8 types, date), the add-habit sheet (list minus kept habits, own words capped at 60, reminder), the goal sheet (only steps not reached, plus automatic), and the relapse sheet.
- **Relapse:** the counter restarts, longest and total stay, and the goal returns to 1 day.
- **Relapse wording:** checked against a list of judging or diagnostic words in both languages.
- **24-hour pickers:** daily reminder, habit reminder, new-habit reminder and relapse time. No AM/PM and no ص/م.
- **Empty states:** no addiction, no dose, no habit, five habits (limit message), no quote.
- **Loading, failure and retry.**
- **Double taps** on 11 actions.
- **Every recovery refusal code:** 15 codes plus FastAPI's own 422, sent through the real `ApiRecoveryRepository` behind a fake HTTP server, plus `recovery_locked` on three kinds of save.
- **Untranslated text:** no raw `snake_case` code and no Latin word in Arabic.
- **Size checks:** 320 px wide, 320×568, 360×640, and 1.3× text. These measure with real fonts (Roboto and Arial loaded with `FontLoader`), because the test font draws every glyph 1 em wide.
- **Screen readers:** `labeledTapTargetGuideline` and `androidTapTargetGuideline` on home, daily check, addiction form and locked view (all pass), plus the semantics of each custom control.

**Dashboard coverage.** Every check runs in French and in Arabic, with `dir` and `lang` asserted.
- **Patient file, per addiction:** profile and review badge, current streak, longest streak, total sober days, the small goal (chosen or automatic), relapses with notes (dated on the Algiers day: 23:30 UTC shows as the 16th), the 30-day chart of craving and the two signals (30 columns per row; a generic addiction gets craving only), check-in days out of 30, and habits done out of 30.
- **Untranslated text:** no API code or untranslated word on the page.
- **Empty states:** no addiction, no habit, no medicine, no checks in 30 days.
- **Failed load:** a retry that loads the file.
- **Alerts inbox:** a label for `relapse`, `missed_doses`, `craving_high`, `no_checkin`, `milestone` and an unknown kind. The high-priority badge appears on the relapse only. No profile, signal or note text leaks into the inbox. The empty inbox has its own message.

## Findings

### UX-01: Every server refusal on a recovery save reads as "check your connection", and a lock on a dose or relapse shows nothing
- Severity: medium
- Rule: R-127 (PRD §8.6, DESIGN §9), R-07 (PRD §5 unlock)
- Where:
  - `apps/mobile/lib/features/recovery/api_recovery_repository.dart:56-61`: every non-2xx except `recovery_locked` becomes `RecoveryUnavailable`, and the code is dropped.
  - `recovery_screen.dart:187-196`: `_saving` catches only `RecoveryUnavailable`.
  - `recovery_screen.dart:212-222`: `_relapse` is the same.
  - `recovery_screen.dart:257-283`: the daily-check save catches everything and shows `recoverySaveError`.
  - `recovery_screen.dart:460-461`: a failed load shows `LoadError` with `bookLoadError`.
  - Strings: `app_fr.arb:362`, `app_ar.arb:537`.
- Repro: `apps/mobile/test/qa_recovery_flow_test.dart` › group "every refusal from the recovery API is explained (PRD 8.6)" › "UX-01 …" (36 tests):
  - each code in both languages: too_many_addictions, clean_since_in_future, relapse_in_future, relapse_before_start, not_found, a FastAPI 422, goal_invalid, check_locked, signals_mismatch, checkin_day_out_of_range, too_many_habits, habit_exists, dose_not_scheduled, dose_day_out_of_range, medication_not_found;
  - `recovery_locked (403)` on a daily-check save, a dose answer and a relapse.
- Expected (PRD): every refusal shows a specific localised message. A patient whose recovery is locked sees the locked state with its Book button.
- Actual:
  - **Refusals:** every refusal shows "تعذّر الحفظ. تحقّق من الاتصال وحاول مجدداً." / "Enregistrement impossible. Vérifiez la connexion et réessayez." even though the network is fine. One reachable case: a patient who added an addiction today and logs a relapse "yesterday" gets `relapse_before_start`, shown as a connection problem.
  - **Lock on a check save:** shows the same connection message.
  - **Lock on Taken or on "Restart my counter":** throws an uncaught `RecoveryLocked`. Nothing appears on screen.
  - **What passes:** no raw code and no English text reaches the screen in any of the 36 cases. A real network loss correctly says "check your connection" and keeps the answers on screen (passing test).
  - **Precedent:** this is the same pattern as booking UX-04 (2026-10-25).

### UX-02: The relapse note and the exact substance have no length limit, though the server caps them
- Severity: low
- Rule: R-21, R-11 (PRD §5.1, §3; the limits themselves are G-14)
- Where:
  - Fields: `apps/mobile/lib/features/recovery/recovery_widgets.dart:351-356` (relapse note `TextField`, no `maxLength`) and `addiction_form_screen.dart:145-152` (substance, no `maxLength`).
  - Server caps: `backend/app/routers/recovery.py:57-64` (100) and `:85-95` (500).
- Repro: `qa_recovery_flow_test.dart` › "UX-02 the relapse note stops at the 500 characters the server takes" and "UX-02 the exact substance stops at the 100 characters the server takes" (ar, fr).
- Expected: the field stops at the length the server accepts, as the own-words habit field already does (60).
- Actual: the patient can type more. The server's 422 is then shown as "check your connection" (UX-01), and the relapse is not logged.

### UX-03: In the dashboard, a failed confirm/reject, "mark read" or medicine "stop" gives the doctor no message
- Severity: medium
- Rule: R-121 (PRD §7, §8.6)
- Where: `apps/dashboard/src/pages/PatientDetail.tsx:79-88` (review failure: `catch { reload(); }`), `PatientDetail.tsx:244-254` (stop), `apps/dashboard/src/pages/Alerts.tsx:26-37` (mark read)
- Repro: `apps/dashboard/src/test/qa-recovery.test.tsx` › "feedback when the server refuses a change (UX-03)" (3 `it.fails`). Each first checks that the request was sent, then waits for `role="alert"`.
- Expected: a visible error, as the profile change (`profileFailed`) and the prescription (`prescribeFailed`) already show.
- Actual: the page quietly reloads. The doctor may believe the addiction was confirmed, the alert read, or the medicine stopped.

### UX-04: A double tap sends two requests on five one-tap actions
- Severity: low
- Rule: R-58, R-70 (idempotent on the server, so no duplicate rows); PRD §8.6 (slow 3G)
- Where: `recovery_screen.dart:198-204` (`_mark`), `:232-240` (`_checkIn`), `:324-336` (`_toggleHabit`), `:350-363` (`_removeHabit`), `:396-404` (`_stopReminder`). None has an in-flight flag. Their buttons stay enabled during the call: `recovery_widgets.dart:456-460`, `:480-487`, `:768-781`, and `tracking_widgets.dart:471-475`, `:488-492`.
- Repro: `qa_recovery_flow_test.dart` › group "a double tap sends one request" › "UX-04 Taken on a dose", "UX-04 "day without use" tick", "UX-04 habit done today", "UX-04 remove a habit", "UX-04 stop the daily reminder". Each fails with `Expected <1>, Actual <2>`.
- Expected: one request per tap.
- Actual: two requests. A second habit removal would get `not_found` from the real API, so the patient sees "check your connection" right after the habit disappeared.
- What passes: Save on the daily check, Save on the addiction form, "Restart my counter", Save on the add-habit sheet, a goal step, and milestone Continue all send one request (passing tests).

### UX-05: The counter shows days only, not "days (and hours)"
- Severity: medium
- Rule: R-27 (PRD §5.1)
- Where: `apps/mobile/lib/features/recovery/recovery_widgets.dart:91-96` (ring label `ringDaysLabel(days)`), `apps/mobile/lib/widgets/sobriety_ring.dart`
- Repro: `qa_recovery_flow_test.dart` › "UX-05 the counter shows days and hours (PRD 5.1)" (ar, fr). The test uses 9 days and 3 hours since the start.
- Expected (PRD): "One circular counter per addiction showing days (and hours) since the sobriety start date."
- Actual: "9 jours sans consommer" with no hours. For the whole first day after a relapse, the counter reads 0.

### UX-06: Reaching the 4-week small goal is not celebrated
- Severity: medium
- Rule: R-36 (PRD §5.6 "Goal reached → celebration, and the next step is suggested")
- Where: `apps/mobile/lib/features/recovery/recovery_screen.dart:114-140` (`_celebrate` shows only `pendingMilestone`) and `recovery_models.dart:238`. The steps 1, 3, 7 and 14 coincide with milestones; 28 does not (the next milestone is 30).
- Repro: `qa_recovery_flow_test.dart` › "UX-06 reaching the 4-week goal is celebrated (PRD 5.6)" (ar, fr; THC addiction on day 28).
- Expected (PRD): a celebration when the goal is reached.
- Actual: no celebration screen. The ring moves silently to the next goal.

### UX-07: Medication reminders are not built: no local dose reminder and no Snooze
- Severity: high
- Rule: R-72, R-71 (PRD §5.3, §12.3)
- Where:
  - `apps/mobile/lib/features/recovery/recovery_widgets.dart:637-787`: `DosesCard` offers Taken / Not taken only.
  - `recovery_models.dart:301`: `enum DoseStatus { due, taken, skipped }`.
  - `recovery_reminders.dart`: schedules the daily-check and habit reminders only.
- Repro: `qa_recovery_flow_test.dart`:
  - "UX-07 a due dose offers Taken, Skipped and Snooze (PRD 5.3)" (ar, fr): 2 answers found where 3 are expected.
  - "UX-07 today's due dose gets a neutral local reminder (PRD 5.3)" (ar, fr): nothing is scheduled at 21:00 for the due dose.
- Expected (PRD): reminders for each dose time, scheduled locally on the phone with neutral text and working offline. The patient answers Taken / Skipped / Snooze.
- Actual: a patient on medication is never reminded. They must open the app to see the dose. Missed doses then raise `missed_doses` alerts (R-101), which the phone did nothing to prevent. The alerts tester carries this as "UX-07" too.

### UX-08: A screen reader cannot activate the daily-check ratings, the habit tick, or the date and time buttons
- Severity: medium
- Rule: R-50, R-124 (PRD §8.6 accessibility)
- Where: each control is wrapped in `Semantics(button: true, label: …, excludeSemantics: true)` with no `onTap`. That wrapper drops the child's tap action (and the checkbox's checked state):
  - `apps/mobile/lib/features/recovery/tracking_widgets.dart:120-125`: 1–5 rating
  - `tracking_widgets.dart:471-475`: habit checkbox
  - `tracking_widgets.dart:477-481`: habit reminder time
  - `addiction_form_screen.dart:156-160`: clean-since date
  - `recovery_widgets.dart:330-334`: relapse time
- Repro: `qa_recovery_flow_test.dart` › group "screen readers and tap targets (PRD 8.6)" › "UX-08 …" (5 tests). Each fails with "missing actions: [tap]".
- Expected: each control is a button (or checkbox) that a TalkBack or VoiceOver user can activate.
- Actual:
  - The labels read well ("Envie de consommer : 3 sur 5"), but double-tapping does nothing.
  - Save needs every rating, so a screen-reader user cannot complete the daily check at all.
  - The habit tick also loses its checked state.
- What passes: Flutter's `labeledTapTargetGuideline` on every screen. It cannot see a control that exposes no action.

### UX-09: The 1–5 rating circles are smaller than 48×48
- Severity: low
- Rule: R-50 (PRD §8.6 "Large tap targets")
- Where: `apps/mobile/lib/features/recovery/tracking_widgets.dart:125-141`: `height: 44`, with the width shared by five `Expanded` cells.
- Repro: `qa_recovery_flow_test.dart` › "UX-09 daily check: each 1-5 rating is at least 48×48 (320 wide)"
- Expected: at least 48×48, the Android minimum. Every other control in recovery meets it (`androidTapTargetGuideline` passes).
- Actual: 41.6 × 44 at 320 px. The guideline test misses this because the rating exposes no tap action (UX-08).

### UX-10: The "pills" type is called "hallucinogenic pills" in Arabic, and its name differs in each app
- Severity: low
- Rule: R-124, R-125 (PRD §3 "psychotropic pills", §8.6)
- Where: `apps/mobile/lib/l10n/app_ar.arb:503` (`pills{الأقراص المهلوسة}`), `app_fr.arb:333` (`Psychotropes (comprimés)`), `apps/dashboard/src/i18n.tsx:106` (`أقراص`), `:286` (`Médicaments (comprimés)`)
- Repro: `qa_recovery_flow_test.dart` › "UX-10 the Arabic name of the pills type is not "hallucinogenic" (PRD 3)"
- Expected: one name matching the PRD's "psychotropic pills", the same in the app and the dashboard.
- Actual:

  | Where | Arabic | French |
  |-------|--------|--------|
  | Patient app | "hallucinogenic pills" | "psychotropes" |
  | Doctor dashboard | "pills" | "medicines (tablets)" |

  Pregabalin, the profile mapped to this type, is not hallucinogenic, and the dashboard's "medicines" reads like a prescription.

### UX-11: The milestone celebration does not scroll, so Continue can fall off a small screen
- Severity: medium
- Rule: R-30 (PRD §5.1), R-124 (PRD §8.6 "works on low-end phones")
- Where: `apps/mobile/lib/features/recovery/milestone_screen.dart:53-118`: a `Column` with two `Spacer`s inside `SafeArea`, no scroll view. The badge `Wrap` grows by one chip per year after day 365.
- Repro: `qa_recovery_flow_test.dart` › group "the milestone celebration on a small phone" › "UX-11 two years of badges, 320×568 · ar/fr" and "… 360×640 · fr"
- Expected: the celebration and its Continue button fit or scroll on a small phone.
- Actual: overflow by 98 px (ar) and 124 px (fr) at 320×568, and 52 px (fr) at 360×640. Continue ends up below the screen. The patient's only way out is the system back gesture. One year of badges at 360×640 fits (passing test).

### UX-12: The next-visit date tile clips the French month at 1.3× text
- Severity: low
- Rule: R-124 (PRD §8.6)
- Where: `apps/mobile/lib/features/recovery/recovery_widgets.dart:574-597`: a fixed 52×56 box holds the day and the full month name ("octobre"; `app_fr.arb:152` uses full names).
- Repro: `qa_recovery_flow_test.dart` › "UX-12 1.3× text, 360 wide: nothing overflows" (fr)
- Expected: no clipped text with a larger system font.
- Actual: "A RenderFlex overflowed by 16 pixels on the bottom". Arabic fits, and so does French at 1.0× (passing tests).

### UX-13: Cairo and Inter are not bundled, so every screen falls back to system fonts
- Severity: low
- Rule: R-129 (DESIGN §2 "Arabic UI font: Cairo … Latin / French font: Inter")
- Where: `apps/mobile/pubspec.yaml` (the `flutter:` section has no `fonts:` and no assets); `apps/mobile/lib/theme/app_tokens.dart:136-142` itself says "Both must be bundled as assets"
- Repro: static: `sed -n '/^flutter:/,$p' apps/mobile/pubspec.yaml`
- Expected: the design fonts ship with the app.
- Actual: `fontFamily: 'Cairo'` and `'Inter'` resolve to nothing, and the phone draws its system font. The text sizes are tuned to Cairo and Inter metrics, so the overflow margins differ from the design. This is app-wide; I report it here because every recovery screen shows it.

### UX-14: Arabic day counts in the patient file are not pluralised ("9 يوم", "64 يوم")
- Severity: low
- Rule: R-125 (PRD §8.6)
- Where: `apps/dashboard/src/i18n.tsx:135` (`daysCount: '{n} يوم'`), used by `PatientDetail.tsx:189` for current, longest, total and goal
- Repro: `apps/dashboard/src/test/qa-recovery.test.tsx` › "UX-14: "9 يوم" is not Arabic; 3 to 10 days take the plural "أيام""
- Expected: correct Arabic number agreement ("يومان", "9 أيام", "64 يوماً"). The mobile app already does this with ICU plurals (`ringDaysLabel`, `milestoneBody`).
- Actual: "9 يوم", "21 يوم", "64 يوم".

### UX-15: Off-token values in the recovery screens (static check)
- Severity: low
- Rule: R-129 (DESIGN §1-5, CLAUDE.md "colours, fonts and spacing only from design tokens")
- Where (mobile):
  - `recovery_widgets.dart:213` `spacing: AppSpace.xs + 2`. This is 6 px, off the 4-px grid; booking UX-12 flagged the same pattern.
  - `recovery_widgets.dart:853` `EdgeInsets.only(top: 2)`.
  - `recovery_widgets.dart:589` `height: 1.1` (overrides the token line height).
  - `recovery_widgets.dart:694` and `:336`: buttons at `Size(0, 44)`, against DESIGN §7 "Button … height 52". The theme already uses 52 at `app_theme.dart:87,98`.
  - `tracking_widgets.dart:134` rating `height: 44`.
  - `milestone_screen.dart:133-139`: badge 148×148, border 6.
  - Icon sizes 14/18/20/28/40, the 8-px dot and the 32-px day dot (no icon-size tokens exist in DESIGN).

  Where (dashboard):
  - `Tracking.tsx:133` `grid-cols-[minmax(7rem,9rem)_1fr]`
  - `Tracking.tsx:134` `gap-[2px]`
  - `Tracking.tsx:188` `h-[48px]`
  - `Tracking.tsx:200` `rounded-t-[4px]`
  - `Alerts.tsx:54` and `PatientDetail.tsx:266` `min-w-[12rem]`
- Repro: `grep -nE "Color\(0x|#[0-9A-Fa-f]{6}|Colors\.[a-z]" apps/mobile/lib/features/recovery/*.dart apps/mobile/lib/features/home/*.dart apps/mobile/lib/widgets/sobriety_ring.dart` (no hits); `grep -nE "EdgeInsets\.(only|symmetric|all|fromLTRB)\([^)]*[^A-Za-z.][0-9]+|xs \+ |height: 1\.|Size\(0, 44\)|height: 44" …`; `grep -nE "\[[0-9#m][^]]*\]" apps/dashboard/src/pages/{PatientDetail,Tracking,Alerts}.tsx`
- Actual: every colour is an `AppColors` token or a Tailwind token. There is no `Color(0x…)`, no hex and no `Colors.*` in the mobile recovery, home or ring files, and no hex in the dashboard recovery pages. The sobriety ring uses `teal100` for the track, `teal500`→`teal400` for progress and `sand400` for the badge, as DESIGN §7 specifies (R-130).

### UX-16: Doctor views from PRD §7 are not built: streak history chart, patient-list filters, mobile doctor view
- Severity: medium
- Rule: R-120, R-119, R-122 (PRD §7)
- Where:
  - `apps/dashboard/src/pages/PatientDetail.tsx`: counters only, no streak history chart.
  - `apps/dashboard/src/pages/Patients.tsx:18`: filters by phone only. The API returns no addiction, streak or activity fields (`backend/app/routers/staff.py:67-72`).
  - `apps/mobile`: no doctor view. Medication adherence (R-74) is the API tester's API-10.
- Repro: static (no code exists)
- Expected (PRD §7):
  - **Patient file:** a streak history chart.
  - **Patient list:** search and filter by addiction, streak, risk level and last activity.
  - **Mobile app:** "a lighter doctor view … for alerts and today's agenda".
- Actual: none of the three exists. The per-addiction relapse list and 30-day chart partly cover the history.

### UX-17: Quote favourites and "share as an image" are not built
- Severity: low
- Rule: R-80 (PRD §5.2)
- Where: `apps/mobile/lib/features/recovery/recovery_widgets.dart:790-830` (`QuoteCard` has no action)
- Repro: static
- Expected (PRD): "Patient can save favourites and share as an image."
- Actual: the quote card is text only. Quote management (API-13) and the stage-based choice (API-12) belong to the API tester.

## Questions (PRD/DESIGN silent: not bugs)

- **Q-UX-1: Which time zone does Recovery display?**
  - **Booking:** converts every time to Africa/Algiers (`api_booking_repository.dart:42-71`; PRD §4.3 "displayed in Africa/Algiers").
  - **Recovery:**
    - uses the phone's zone: `clean_since` goes through `.toLocal()` (`api_recovery_repository.dart:126`);
    - "today" is `DateTime.now()` (`recovery_screen.dart:233, 245, 325`);
    - the relapse sheet uses the phone clock (`recovery_widgets.dart:280-287`).
  - **Reminders:** the daily-check and habit reminders are scheduled in Africa/Algiers (`local_notifications.dart:71`).
  - **Consequence:** a patient whose phone is in another zone sees one clock in Recovery and gets reminders on another. I could not exercise this: the test machine is UTC+1 (W. Central Africa Standard Time), the same offset as Algiers, and `flutter test` cannot override the zone. This is the same family as G-03 and API-01..03.
- **Q-UX-2: Error wording per recovery code** (needed to fix UX-01). What should the patient read for:
  - `relapse_before_start` (for example "a relapse can't be before your start date");
  - `check_locked` ("today's check can no longer be changed"?);
  - `signals_mismatch` (the doctor changed the profile while the screen was open: reload the questions?);
  - `too_many_addictions` (10);
  - `recovery_locked` on a save: show the locked tab?
- **Q-UX-3: Should the dashboard chart mirror in Arabic?** The 30-day chart is forced left-to-right in Arabic (`Tracking.tsx:83-84`, "like a timeline"). DESIGN §9 says "full RTL (mirror layout…)". Is a left-to-right time axis inside an Arabic page intended?
- **Q-UX-4: Can the patient cancel the relapse sheet after answering "No"?** Answering "No" to "Today without X?" saves `used = true` and then opens the relapse sheet (`recovery_screen.dart:289-298`). If the patient cancels the sheet, the check stays "used" and the counter does not move. PRD §5.6 says "answering No opens relapse logging". Should cancelling be possible, and should the doctor's chart then show a declared use with no relapse? Today it does.

## UX review (not tests)

- **All-or-nothing load.**
  - **Code:** `recovery_screen.dart:63-108` waits for 11 calls; one failure (for example the quote or the doses) replaces the whole tab with `LoadError`.
  - **Message:** that error says "check your connection" (`bookLoadError`) even for a 500 or a refusal.
  - **Effect:** a patient whose quote service fails loses their counters, too.
- **Missing feedback:**
  - Removing a habit (the ✕ at `tracking_widgets.dart:488-492`) acts at once, with no confirmation, no undo and no "removed" message.
  - The doctor's profile change (`PatientDetail.tsx:118-131`) applies on select, with no confirmation. A mis-click silently changes the patient's daily questions.
  - Together with UX-01 and UX-03, these are the main feedback gaps.
- **Confusing wording:**
  - In French, the dose button and the resulting state both read "Pris" (`app_fr.arb:300,302`). A button labelled with a past participle looks like a state already set.
  - "Ajouter une autre addiction" / "أضف إدماناً آخر" (`app_fr.arb:358`, `app_ar.arb:533`) uses "addiction", while the first entry says "ce dont je me rétablis" / "ما تتعافى منه" (`:357`, `:532`). The tone is gentler in the first.
- **Screen readers:**
  - **Gaps:**
    - The loading spinner (`recovery_screen.dart:454`) has no semantics label.
    - The dashboard chart cells carry `aria-label` on plain `<span>`s with no role (`Tracking.tsx:154-158`, `:197`). ARIA does not allow names on generic elements, and most screen readers skip them. The `<details>` table is the accessible path, and it works.
  - **What works:** the week-strip dots, the ring (one label), the clinic phones, the alert rows and the locked view read well.
- **Tap targets:** everything passes Flutter's 48×48 guideline except the ratings (UX-09). The dose buttons are drawn 44 high but get a padded 48 hit area.
- **Good:**
  - **Relapse wording:** supportive in both languages ("Ce n'est pas un échec", "لا بأس، هذا جزء من الطريق"). It says what is kept and that the doctor will be told "pour vous soutenir". No judging or diagnostic word appears in the sheet, the snackbar or the button labels.
  - **After a relapse:** longest and total stay on screen.
  - **Time pickers:** all are 24-hour, and times stay LTR inside Arabic.
  - **Layout:** nothing overflows at 320 px in either language, except UX-11 and UX-12.
  - **Dashboard:** dates are in Algiers time and every alert kind is named in both languages with no medical content.

## R-ids covered

R-07, R-11, R-21, R-25 (app side, via the daily-check "No" path), R-26, R-27, R-28, R-30, R-36, R-37, R-41, R-44 (app sample catalogue), R-50, R-51 (app sample catalogue: 2–3 notes, non-empty AR+FR), R-58, R-59, R-70, R-71, R-72, R-80, R-81 (app side: `no_quote` shows no card and no error), R-114, R-115 (alert "Open" untouched; labels), R-116, R-117, R-119, R-120, R-121, R-122, R-124, R-125, R-126 (app-side texts), R-127, R-128, R-129, R-130.

## Commands run

```
git rev-parse --short HEAD                                                     # c772566 (start)
cd apps/mobile && flutter pub get                                              # Got dependencies!
cd apps/mobile && flutter gen-l10n                                             # ok (info line only)
cd apps/mobile && flutter test test/qa_recovery_flow_test.dart --no-pub        # 00:23 +77 ~58: All tests passed!  (as found)
cd apps/mobile && flutter test test/qa_recovery_flow_test.dart --no-pub --dart-define=QA_RUN_BUGS=true
                                                                               # 00:59 +77 -58: Some tests failed.  (every bug test fails for its reason)
cd apps/mobile && flutter test test/qa_recovery_flow_test.dart --no-pub --dart-define=QA_RUN_BUGS=true --name "recovery_locked|screen reader"
                                                                               # 00:11 +7 -12: Some tests failed.  (the 6 new bug tests among them)
cd apps/mobile && flutter test test/qa_recovery_flow_test.dart --no-pub        # 00:22 +77 ~64: All tests passed!  (final)
cd apps/dashboard && npx vitest run src/test/qa-recovery                       # Tests 3 failed | 21 passed (24)  (my fixtures; fixed)
cd apps/dashboard && npx vitest run src/test/qa-recovery                       # Tests 24 passed (24)  (final)
cd apps/dashboard && QA_RUN_BUGS=true npx vitest run src/test/qa-recovery      # Tests 4 failed | 20 passed (24)  (the 4 bug tests fail as expected)
cd apps/dashboard && npx vitest run                                            # Test Files 7 passed (7); Tests 114 passed (114)
grep (static token checks above)                                               # see UX-15
git rev-parse --short HEAD                                                     # c772566 (end)
```

## Not run

- `apps/mobile/test/qa_recovery_privacy_test.dart`: owned by another tester, never run by me.
- **Time-zone behaviour of the mobile Recovery (Q-UX-1):** the machine's zone equals Algiers, and the test runner cannot change it.
- **Real TalkBack/VoiceOver on a device:** semantics are checked in widget tests only.
- **Backend tests:** not my role.
