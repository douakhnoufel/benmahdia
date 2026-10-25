# UX (clients) — booking QA 2026-10-25

Agent: ux-clients. Scope: the patient booking flow in `apps/mobile` and the front-desk check-in box in `apps/dashboard`. No app code was changed.

## Tests added

| File | Tests | Pass | Marked as known bug |
|------|-------|------|---------------------|
| `apps/mobile/test/qa_booking_flow_test.dart` | 73 | 62 | 11 (skipped `QA UX-01/02/03/07/08`) |
| `apps/mobile/test/qa_booking_api_errors_test.dart` | 46 | 39 | 7 (skipped `QA UX-04/05/06/09`) |
| `apps/dashboard/src/components/qa-booking-checkin.test.tsx` | 27 | 27 | 0 |

Flutter's `testWidgets` only accepts `skip: bool`, so each bug test sits in a `group(..., skip: 'QA UX-NN: ...')`. To run the bug tests too (every one fails today, as it should), pass `--dart-define=QA_RUN_BUGS=true`. I ran that and checked that all 18 fail for the reason in their finding.

Mobile coverage: every screen (doctor, slot, confirm, done card/clinic, my appointments) in ar (RTL) and fr at 390 px, at 320 px, and at 1.3× text on 360 px; screen-reader labels and 48×48 tap targets (Flutter `labeledTapTargetGuideline` and `androidTapTargetGuideline`, all pass); loading, error and retry; no appointments; no free slot; the ID gate wording; hold expiry (by timer and by the server); a double tap on confirm and on pay; back from the done screen. Every booking error code goes through the real `ApiBookingRepository` behind a fake HTTP client: 18 code/action pairs × 2 languages, plus a 422. Clinic time is checked at 08:00Z and around midnight in Algiers.

Dashboard coverage: success shows "arrived" and the reminder to check the original ID card (fr and ar); RTL/LTR, with the code and phone kept LTR; time shown in clinic time; a repeated check-in; blank or spaces-only code; a code typed loosely; the 32-character input cap; Enter pressed twice; every refusal code in both languages; offline; a 422; trying again after the lockout; and an error that follows a success.

## Findings

### UX-01: "Complete your profile" still offers Skip
- Severity: high
- Rule: R-08 (PRD §4.1, §4.2 AC "cannot be skipped")
- Where: apps/mobile/lib/features/profile/profile_prompt_screen.dart:55 (`profile-skip`), profile_flow.dart:30 (`onSkip: finish`), booking_flow.dart:75-77 (comment describes a "skipped" patient); strings `profileSkip` / `profileSkipNote` in both .arb files
- Repro: `qa_booking_flow_test.dart` › "UX-01 Complete your profile has no Skip"
- Expected (PRD): the profile step is mandatory, with no Skip.
- Actual: "تخطَّ الآن" / "Passer pour l'instant" closes the step. The existing `profile_test.dart` "skip comes back and carries on" asserts the old behaviour and must change with the fix.

### UX-02: The "ID declared" label never appears in the app
- Severity: medium
- Rule: R-07 (PRD §4.2 Status values and AC: "the label is 'ID declared' / 'Identité déclarée' / 'هوية مصرّح بها'")
- Where: apps/mobile/lib/l10n/app_ar.arb, app_fr.arb (no such string); apps/mobile/lib/features/profile/profile_card.dart:32-38
- Repro: `qa_booking_flow_test.dart` › "UX-02 declared: the status label is "ID declared"" (ar, fr)
- Expected (PRD): "ID declared" is shown for `declared` and stays next to `approved`.
- Actual: the card says "في انتظار العيادة / En attente de la clinique". That is correct for "being reviewed", and "verified" appears nowhere (tested), but the required label is missing.

### UX-03: In French, the done screen overflows on the reminder line
- Severity: medium
- Rule: R-71 (PRD §8.6; CLAUDE.md "French on every screen")
- Where: apps/mobile/lib/features/booking/book_done_screen.dart:294 (a `Row` with icon + `Text(l10n.bookRemind)` and no `Flexible`)
- Repro: `qa_booking_flow_test.dart` › "UX-03 done (card|clinic) · fr · 390 wide / 320 wide / large text" (6 tests)
- Expected: no clipped text on a normal phone.
- Actual: "Nous vous enverrons un rappel" overflows by 116 px at 390 px wide, 186 px at 320, and 268 px at 1.3× text. Arabic is fine.

### UX-04: Server refusals are shown as "could not load, check your connection"
- Severity: medium
- Rule: R-72 (PRD §8.6), R-43 (Chargily down → clear error)
- Where: apps/mobile/lib/features/booking/api_booking_repository.dart:132-141 (`_failure`: every unknown code → `BookingUnavailable`); shown as `bookLoadError` by book_slot_screen.dart:101-103, book_confirm_screen.dart:93-95 and 114-119, my_appointments_screen.dart:77-79
- Repro: `qa_booking_api_errors_test.dart` › "UX-04 …" (hold `not_verified`, confirm `payment_method_unavailable`, checkout `payments_unavailable`, cancel `not_cancellable`)
- Expected: a message that matches the refusal. Examples: card payment unavailable, pay at the clinic; ID still being reviewed; this appointment can no longer be cancelled.
- Actual: "تعذّر التحميل. تحقّق من الاتصال وحاول مجدداً." for all of them. No raw code or English text reaches the screen; that part passes for all 18 codes × 2 languages.

### UX-05: A cancel answered with `appointment_not_found` throws, and the patient sees nothing
- Severity: low
- Rule: R-72
- Where: apps/mobile/lib/features/booking/my_appointments_screen.dart:72-81 (catches only `TooLateToCancel` and `BookingUnavailable`); api_booking_repository.dart:138 maps `appointment_not_found` → `SlotUnavailable`
- Repro: `qa_booking_api_errors_test.dart` › "UX-05 cancel 404 appointment_not_found …"
- Expected: a message, then the list refreshes.
- Actual: an uncaught `SlotUnavailable`, no snackbar, and the stale list stays on screen.

### UX-06: The booking code is never shown to the patient
- Severity: medium (the front-desk check-in depends on it)
- Rule: R-56/R-57 (PRD §4.3 "shown to the patient as text")
- Where: apps/mobile/lib/features/booking/booking_models.dart (`Appointment` has no code field); api_booking_repository.dart `_appointmentFrom` ignores `checkin_code` (the API sends it: backend/app/routers/appointments.py:73); book_done_screen.dart and my_appointments_screen.dart show no code
- Repro: `qa_booking_api_errors_test.dart` › "UX-06 a confirmed appointment shows its 6-character booking code"
- Expected (PRD): a confirmed appointment shows its 6-character code as text. The QR is explicitly not built yet.
- Actual: the code never appears, so the patient has nothing to type at the desk's Today box.

### UX-07: No empty state when there is no doctor to book
- Severity: low
- Rule: none in PRD (brief: empty states)
- Where: apps/mobile/lib/features/booking/book_doctor_screen.dart:58-84
- Repro: `qa_booking_flow_test.dart` › "UX-07 no doctor to book …"
- Expected: a short message explaining that no doctor is available.
- Actual: only the title, the description and a disabled "choose day and time" button.

### UX-08: The hold countdown counts timer ticks instead of following the clock
- Severity: low
- Rule: R-20/R-26 (hold of 15 min; the server is the authority)
- Where: apps/mobile/lib/features/booking/book_confirm_screen.dart:44 and 65-71 (`_left -= _tick` each tick; never recomputed from `expiresAt - now()`)
- Repro: `qa_booking_flow_test.dart` › "UX-08 the countdown follows the clock …" (the clock jumps 10 min while one tick runs)
- Expected: the time left matches `hold_expires_at`.
- Actual: it shows 14:58 when about 4:59 is really left. Timers do not catch up after the phone sleeps or the app is in the background, so the patient can be told they still have time after the server has released the slot.

### UX-09: An unpaid hold in "my appointments" offers "Cancel appointment", and the server refuses it
- Severity: medium
- Rule: R-32 (cancel only `confirmed`), R-27 (a hold is released, not cancelled)
- Where: apps/mobile/lib/features/booking/my_appointments_screen.dart:178 (`canCancel` checks only the notice); `Appointment.isUpcoming` includes `awaitingPayment`
- Repro: `qa_booking_api_errors_test.dart` › "UX-09 an open hold (awaiting payment) offers no 'cancel appointment'"
- Expected: no cancel button, or "give back the hold" (`DELETE …/hold`).
- Actual: the button is shown. Tapping it gets `409 not_cancellable`, which the app then shows as a connection error (UX-04).

### UX-10: Notice and horizon are hard-coded in the copy
- Severity: low
- Rule: R-13 (notice "configurable per doctor"), R-14
- Where: .arb keys `bookNotice`, `bookTooSoon`, `bookCancelRule`, `bookChangeHint`, `apptLocked` ("24 ساعة" / "24 h") and `bookNoFree` ("الشهرين القادمين" / "deux prochains mois"). Meanwhile `ApiBookingRepository` reads `notice_hours` / `horizon_days` per doctor (api_booking_repository.dart `_doctorFrom`)
- Repro: static (read the strings)
- Expected: the text uses the doctor's notice and horizon.
- Actual: a doctor with a 48 h notice would still be shown "24 h".

### UX-11: There is no receipt in the app
- Severity: medium
- Rule: R-55 (PRD §4.4 "the patient sees a receipt in the app")
- Where: apps/mobile/lib/features/booking/* (no receipt screen or string); the done screen shows only "amount paid"
- Repro: static
- Expected (PRD): a receipt the patient can open.
- Actual: none. What the receipt must contain is not specified (see Q3).

### UX-12: Off-token sizes in the booking screens (static check)
- Severity: low
- Rule: CLAUDE.md "colours, fonts and spacing only from design tokens"; DESIGN §2–3
- Where: `fontSize: 12` at book_slot_screen.dart:577 and my_appointments_screen.dart:382, 580 (the smallest token, `AppType.caption`, is 13); `AppSpace.md + 2` / `AppSpace.sm + 2` / `AppSpace.xs + 2` at book_confirm_screen.dart:283, 506-507, book_slot_screen.dart:309, 311, 473, booking_widgets.dart:76, 113; `bottom: 6` at book_slot_screen.dart:564; `SizedBox(height: 2)` at book_slot_screen.dart:333, 583 and my_appointments_screen.dart:530; `AppRadius.card - 4` at book_confirm_screen.dart:511
- Repro: `grep -n "fontSize: [0-9]\|+ 2\|bottom: 6\|height: 2\|card - 4" apps/mobile/lib/features/booking/*.dart`
- Actual: every colour in the booking files is an `AppColors` token: no `Color(0x…)` and no hex. The only exception is `Colors.transparent` at book_slot_screen.dart:541, which is acceptable.

## Questions (PRD/DESIGN silent)

1. **Error wording per code.** What should the patient read for `not_verified` (approval withdrawn), `payments_unavailable` (Chargily down: offer "pay at the clinic"?), `doctor_not_found`, and an expired session (`token_invalid` after a failed refresh)? Today all of them say "check your connection" (UX-04).
2. **Repeated check-in on the dashboard.** The desk sees "Patient arrived" again. Should it say "already arrived at HH:MM" using `checked_in_at`?
3. **Receipt contents** (UX-11): amount, method, Chargily id, date? A PDF or an in-app screen?
4. **Lockout duration.** The API sends `retry_after`, but the box says "wait a few minutes". Should it show the exact wait, and disable the button meanwhile?
5. **Payment control.** DESIGN §7 specifies a segmented "Payment toggle (Cash / CIB-card)", but the app uses three radio cards (Edahabia, CIB, clinic). Which one is right?
6. **Code format in the dashboard input.** Should the box check the 6-character, no-look-alike format before sending, or keep accepting anything up to 32 characters and let the server decide? Today wrong formats count toward the 10-failure lockout.
7. **"First doctor becomes your primary doctor."** The doctor screen promises this (`bookDoctorBody`), but R-34 says the backend does not store it. Keep the sentence?

## UX review (not tests)

- **Confusing step:** a patient with no ID yet (or one who skipped, UX-01) can open "my appointments", and the "+" button sends them to the profile step with no explanation. The card above explains it, but the "+" button gives no feedback of its own.
- **Missing feedback:** server refusals all read as network trouble (UX-04). An expired session reads as "check your connection" instead of asking the patient to sign in again (Q1).
- **Hold countdown:** the "held for mm:ss" banner is not a live region, so a screen-reader user is never told that time is running out. The time-up view does have a header. Combined with UX-08, the countdown is the weakest part of the flow.
- **After payment:** the done screen confirms and promises reminders 24 h and 1 h before, but R-54 says no reminder job exists in the backend. The patient is told about reminders that will not arrive. This is a cross-reference for the API owner, not counted as a UX finding.
- **Accessibility, good:** tap targets and labels pass Flutter's guidelines on every booking screen in Arabic, and nothing overflows in Arabic even at 1.3× text. Doctor cards, slot pills and payment cards carry `button`/`selected` semantics, and times are LTR inside RTL text.
- **Dashboard check-in:** labelled input; results announced through `role="status"` / `role="alert"`; the code field is forced LTR; double submit is blocked. Nothing to flag.

## Commands run

```
cd apps/dashboard && npm install                                   # ok (audit warnings only)
cd apps/mobile && C:/src/flutter/bin/flutter.bat test test/booking_test.dart          # toolchain check: 26 passed
cd apps/mobile && C:/src/flutter/bin/flutter.bat test test/qa_booking_flow_test.dart test/qa_booking_api_errors_test.dart
    # 101 passed, 18 skipped (QA UX-xx)
cd apps/mobile && C:/src/flutter/bin/flutter.bat test test/qa_booking_flow_test.dart --dart-define=QA_RUN_BUGS=true
    # 62 passed, 11 failed = exactly the UX-01/02/03/07/08 tests
cd apps/mobile && C:/src/flutter/bin/flutter.bat test test/qa_booking_api_errors_test.dart --dart-define=QA_RUN_BUGS=true
    # 39 passed, 7 failed = exactly the UX-04/05/06/09 tests
cd apps/mobile && C:/src/flutter/bin/flutter.bat analyze test/qa_booking_flow_test.dart test/qa_booking_api_errors_test.dart   # no issues
cd apps/dashboard && npx vitest run src/components/qa-booking      # 27 passed
cd apps/dashboard && npx tsc -b --noEmit                           # no errors
```
`flutter pub get` / `gen-l10n` were not needed: `.dart_tool` and the generated l10n were already present.
