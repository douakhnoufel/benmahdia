# Mobile app skeleton: journey, navigation, saved session, Profile & Settings

Date: 2026-10-23 · Scope: `apps/mobile` (Flutter, Riverpod) · Status: **awaiting review**

## 1. Why

The app was run on a real Android phone on 2026-10-22. The screen order was wrong, things were in the wrong place, and errors appeared at startup, at sign-up/login, in the home tabs and during the ID scan. Causes found in the code:

- **Nothing is saved.** No secure storage, no shared preferences. Every launch runs splash → intro → welcome, and the login is lost.
- **No navigation map.** Screens are chained by hand (`openSignUp`, `openLogin`, `openProfile`, `openHome`, `openBooking`, `pushAndRemoveUntil`), so Back and the order of screens depend on each call site.
- **Dead duplicate feature.** `features/verification/` is never opened; `features/profile/` does the same job.
- **No place for the account.** Nowhere to see the ID status, change the language or log out.
- **Tests run on fakes only** (177 pass), so camera, ML Kit and server failures never show in tests.

Crash triage with real phone logs is a **separate** task, done after this skeleton.

## 2. Patient journey (decided 2026-10-23)

1. **Intro.** Shown in the phone's language: `ar` or `fr`, otherwise `ar`. First launch only.
2. **Language.** Chosen once on a full-screen picker (العربية / Français). The phone's language is pre-selected when it is ar or fr.
3. **Account.** The existing sign-up / login: phone + OTP + password, or Google.
4. **Profile, mandatory.** Consent, then document choice (national ID or passport), live scan, confirm/edit, selfie. There's no Skip.
5. **Home, locked except Appointments.**
   - While the ID is under review, Appointments shows "Your ID is being reviewed".
   - Once it's approved, the patient picks a doctor and a slot and pays (existing booking flow).
6. **First booking confirmed (paid)** → Recovery and Companion unlock, and from then on the app opens on Recovery.
7. **Later, separate spec:** a questionnaire after booking, from which the app decides each patient's tracking. Patients are not all tracked the same way.

### ID approval (backend + dashboard: separate spec, listed here so the app shows the right states)

- **Automatic approval** when every check passes:
  - fields read by the scanner and not edited by hand
  - passport check digits valid
  - ID number not already used (HMAC)
  - exactly one clear face in the selfie
- **When a check is unsure**, the declaration goes to the **clinic staff** queue in the dashboard.
- **Staff can always approve or reject,** including overturning an automatic approval, with a reason.
- **Each decision records who made it:** `auto` or the staff member. The doctor does not approve IDs.
- **Known risk.** The checks prove the card is readable and unused, not that it belongs to the person holding the phone. Mitigations:
  - the front-desk comparison with the original card at the first visit (already in PRD §4.2)
  - later, a selfie ↔ card-photo face match before auto-approval
- **Note for the backend spec:** "not edited by hand" and "one face" are signals sent by the app, so a modified app could fake them. The staff override is the backstop.

## 3. Saved state

`sessionProvider` (Riverpod `AsyncNotifier`) exposes one immutable `Session` value:

| Field | Source | Saved where |
|---|---|---|
| `introSeen` | local | `shared_preferences` |
| `locale` (`ar` / `fr` / null) | local | `shared_preferences` |
| `tokens` (access + refresh) | auth API | `flutter_secure_storage` |
| `idStatus` (`none` / `declared` / `approved` / `rejected` / `duplicate`) | `GET /me` | memory + last known value in `shared_preferences` |
| `firstBookingConfirmed` | `GET /me` | memory + last known value in `shared_preferences` |

- **Loading** reads local values first. It then refreshes `idStatus` and `firstBookingConfirmed` from the server when signed in.
- **Offline:** the last known values are used and an "offline" banner is shown. The patient is **not** signed out.
- **Logout** clears the tokens and the cached server values and keeps `introSeen` and `locale`.
- **New packages:** `go_router`, `shared_preferences`, `flutter_secure_storage`.
- **Backend need:** one endpoint (or the existing profile endpoint) must return `id_status` and whether a paid appointment exists. Check what exists before adding.

## 4. Navigation

`go_router`, created **once** in a kept-alive provider and never rebuilt.

| Path | Screen | Navigator |
|---|---|---|
| `/splash` | splash (only while `sessionProvider` loads) | root |
| `/intro` | intro slides | root |
| `/language` | language picker (new) | root |
| `/welcome`, `/signup`, `/login`, `/otp`, `/password` | existing auth screens | root |
| `/profile-setup/...` | existing profile flow (`features/profile` renamed `features/profile_setup`) | root |
| `/home/appointments` | Appointments tab | shell branch 0 |
| `/home/recovery` | Recovery tab | shell branch 1 |
| `/home/companion` | Companion tab | shell branch 2 |
| `/book/...` | booking steps (doctor → slot → confirm → done) | root (above the tab bar) |
| `/me` | Profile & Settings (new) | root (above the tab bar) |

**Tabs:** `StatefulShellRoute.indexedStack`, one branch per tab. Each tab keeps its own state, and tapping the active tab returns it to its root. The tab order stays as in DESIGN.md: Appointments · Recovery · Companion.

**Redirect**, a pure function `redirect(Session, location) → location?`, checked in this order:

1. Session loading → `/splash`.
2. `!introSeen` → `/intro`.
3. `locale == null` → `/language`.
4. No tokens → `/welcome`, or stay if already on an auth path.
5. `idStatus ∈ {none, rejected}` → `/profile-setup`. A rejected patient sees the reason and tries again; a `duplicate` patient sees the neutral message.
6. On a non-home path that isn't allowed → home. Home is `/home/recovery` if `firstBookingConfirmed`, otherwise `/home/appointments`.

Notes:
- **Locked tabs.** Recovery and Companion are not redirected away; they render a locked state ("Book your first appointment to unlock" + Book button). Locked = `!firstBookingConfirmed`.
- **The redirect re-runs on session changes** through `refreshListenable`, a small `Listenable` that `ref.listen`s to `sessionProvider` and is disposed with it.
- Back uses `PopScope` where needed. After reaching home, Back never returns to auth or profile screens.
- **Removed:** `openSignUp` / `openLogin` / `openProfile` / `openHome` / `openBooking`, `home_shell.dart`'s IndexedStack and generation counter, `core/app_route.dart`. The page transition is kept as a `CustomTransitionPage`.
- **Deleted:** `features/verification/` and its tests, and `widgets/lang_toggle.dart` with its uses in intro, welcome and auth widgets.

## 5. Profile & Settings (`/me`)

**Top bar on each tab:**
- The tab title at the start edge.
- An avatar button at the end edge (`radius.pill`, 44 px target, label "الملف الشخصي والإعدادات / Profil et paramètres"). It shows the patient's initial, or a person icon.
- A **dot** on the avatar when the ID needs action (`rejected`, or the automatic check asked for a new photo). It disappears after resubmitting.

**`/me`**, full screen with a back arrow, in cards using DESIGN.md tokens:

1. **Identity.** The declared name, or the phone number before declaration. Then the ID status in the PRD §4.2 wording, never "verified":
   - `declared` → "ID declared · being reviewed"
   - `approved` → "ID declared · approved"
   - `rejected` → reason + "Send again" (submissions left out of 4)
2. **My doctor.** The primary doctor's name after the first booking. Read-only.
3. **Language.** العربية / Français. Switching it applies at once and is saved. Android 13+ per-app language through `res/xml/locales_config.xml`.
4. **Log out.** Confirms first, then clears the session, and the redirect goes to `/welcome`.
5. **Footer:** the app version.

**Not in this spec:**
- consents (need the consent screens)
- app lock (PIN/biometric)
- delete account (needs the PIN, PRD §12.5)
- the reminder time, which stays in Recovery

## 6. Errors

- **Startup never crashes.** Unreadable or corrupt saved data → treated as signed out, then `/welcome`.
- **Token expired.** One shared refresh (already built for booking). If the refresh fails → clean sign-out, then `/welcome`, with no error page.
- **Server unreachable** → last known state + offline banner. Actions that need the server show the existing snackbar.
- **Camera permission refused** → "Camera access needed" + "Open settings", instead of a black screen.
- **Unknown path** → the redirect sends the patient to the right place in the journey.
- **One error sink at startup:** `FlutterError.onError` + `PlatformDispatcher.onError`, installed before `runApp`. Logs hold the error type and route only, never medical content or ID fields (CLAUDE.md).

## 7. Tests

- **`redirect`, table-driven:** every combination of loading / intro / locale / tokens / `idStatus` / `firstBookingConfirmed` / location → the expected result.
- **Session:**
  - fake storage: still signed in after a restart
  - logout clears tokens and keeps the language
  - corrupt data → signed out
  - offline → last known state kept
- **Widget journeys:**
  - first launch end to end (intro → language → sign-up → profile → Appointments locked home)
  - reopening while signed in goes straight to home
  - Back from home never reaches auth
  - tapping the active tab returns to its root
  - locked tabs show the Book button
  - `/me` shows each ID status, the language switch and logout
- **RTL (ar) and LTR (fr)** for the new screens: language, locked tab, top bar, `/me`.
- **Existing tests** move to the router. Only the `verification/` tests are deleted.
- **Manual phone checklist** (Android, `flutter run` over USB), written into the plan:
  1. first launch
  2. kill and reopen
  3. airplane mode
  4. refuse the camera
  5. Arabic ↔ French
  6. log out

## 8. Out of scope

- crash triage on the phone (next task)
- backend/dashboard: automatic ID checks, clinic staff role, staff queue
- questionnaire + personalized tracking
- consent screens
- PIN/biometric lock
- delete account
- local notifications

## 9. PRD changes in the same review

PRD.md is updated with this spec:
- §3 roles: clinic staff
- §4.1 and §4.2: mandatory profile, approval by app or clinic staff, not the doctor
- §5: recovery unlocks after the first confirmed booking
- §7: the staff queue
- §12.1 and §12.3: the new order
