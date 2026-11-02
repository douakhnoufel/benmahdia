# BenMahdia — habit tracking design (2026-11-02)

Approved by the user ("I liked it"). Canvas (Nafas design system, Arabic RTL, 390×844): https://claude.ai/artifact/UgKQxEc1udgtJMumRF4JsP

Nothing in the repo was changed by this design work. It extends the existing recovery slices (counter, milestones, relapse, daily check, doses, quote); new backend pieces would be habits (`Habit`, `HabitLog`) and craving logs (`CravingLog`).

## Screens on the canvas
1. **Today (Recovery tab)**: sobriety ring toward the next milestone, money saved (DZD) and longest streak pills; "I have a craving" card (brand-deep); 3 habit cards (check / count types) with anchor or if-then line, 7-day dots (teal kept, gray missed, dashed sun ring = grace day), progress bar; "see all habits"; nav bar. Interactive: check pops in (~260 ms), respects reduced motion.
2. **Craving moment (urge surfing)**: breathing circle (inhale 4 · hold 4 · exhale 6), timer, intensity 1–10 at start, optional HALT chips (hungry, angry, lonely, tired, other), **"try now" tip: eat something spicy (harissa, hot pepper), the strong taste keeps the senses busy** (asked for by the user, 2026-11-02), the patient's if-then plan with a call shortcut, "Craving passed" CTA, companion link, always-visible urgent-help link.
3. **Craving passed**: intensity before → after, month chart of cravings (before/after pairs), one trigger insight ("most cravings after 22:00 when tired") that offers a matching habit.
4. **Progress**: month heatmap (4 teal levels + grace-day mark, week starts Saturday), consistency %, longest streak, cravings passed, "when cravings come" bars from HALT.
5. **Milestone (30 days)**: rising sun on brand-night → brand-deep, milestone trail 7 → 14 → 30 → 60 → 90 → 180, short line + quote, "Continue", "Share this milestone with your doctor".

## Design rules kept
- No red, no X marks, no confetti; missed = soft gray. Calm, dignified motion.
- Teal fills use `primary-icon` (the design system's proposed contrast fix), teal text `primary-ink`.
- Max 3–5 habit cards on Today, then "see all".
- Numbers Western digits in LTR spans; 44 px tap targets.

## Ideas behind it (feature list)
Forgiving streaks (consistency % + 1 grace day/week, habits separate from the sobriety counter), craving button with before/after intensity, HALT triggers + insights, if-then plans, habit anchors, tiny habits that level up after 7 good days, money saved + clinic-approved body-recovery timeline, one-tap mood/sleep, pre-appointment summary for the doctor (with consent), Ramadan mode, discreet notifications.

## Ideas round 2 (from the user, 2026-11-02)
| Idea | How it fits | Builds on |
| --- | --- | --- |
| **"I'm having a difficult moment" button** | Becomes the craving button: opens the patient's **doctor-approved support plan**, saved coping activities (breathing, spicy tip, walk…), contacts, and **whether the clinic is open now** (from the clinic hours). Urgent help stays visible. | Craving screen on the canvas, ClinicCard hours |
| **30-second daily check-in** | Mood + craving intensity + optional note, then the patient's own trends. Replaces the separate mood/sleep idea. | Existing daily check (slice 2) — extend, don't replace |
| **Prepare my next appointment** | Patient saves questions during the week; before the visit they become a short agenda to edit and share with the doctor. | Next-appointment card, booking |
| **Progress beyond a streak** | Celebrate appointments attended, check-ins done and personal goals, not only sober days. A relapse never erases these. | Milestones, progress screen |
| **My motivation space** | Private reasons for recovery, photos, voice notes, messages. Stays on the phone by default; never shared unless the patient chooses. | New |
| **Gentle return after inactivity** | "Good to see you again" + one easy next step. No list of missed tasks, no overdue badges. | Today screen |
| **Doctor-assigned weekly goals** | Doctor and patient agree small goals; patient marks "Done", "Difficult" or "I need help" ("I need help" raises an alert like a relapse does). | Medications pattern (slice 3), alerts (slice 4), dashboard patient file |
| **Voice check-ins (Arabic, French, Darja)** | Speak instead of type, review the transcript, choose what to save or share. Darja speech-to-text is weak and audio is sensitive: needs the same AI/hosting decision as the companion (PRD §6). | Later, after the AI decision |
| **Offline support kit** | Support plan, chosen articles and appointment details cached on the phone, readable with no network. | Offline-first logs |
| **Explain what the doctor can see** | A sharing label beside every journal, check-in, motivation item and AI conversation: "Only you", "Your doctor sees this", "Shared summary". Fits Algeria's personal-data law (18-07) and patient trust. | All screens; consent screens in the restructure spec |

## Daily quotes
3–4 positive quotes per day as local notifications, from a clinic-approved library (ar + fr, tagged by theme), no repeats until the library cycles, neutral wording.

## Not decided / open
- All numbers on the canvas are sample data; the quote is a draft for the clinic to approve.
- The spicy-food tip needs the doctor's approval (not for patients with ulcers, reflux or stomach-upsetting medicines). Idea: rotate several craving tips (spicy food, mint gum, a glass of water, a short walk) and let the doctor turn one off per patient.
- Who writes the support plan (doctor in the dashboard, patient fills contacts?) and what "clinic available" means outside hours.
- Suggested first build: difficult-moment screen (with support plan), habits with forgiving streaks, daily check-in extension, sharing labels everywhere.
- Next design: "add habit" sheet (anchor picker + "When ___, I will ___"), support plan, check-in sheet, appointment prep, motivation space.
- Data model sketch: `Habit {kind: check|count|duration, target, anchor, schedule, ifThenPlan?}`, `HabitLog`, `CravingLog {intensityBefore, intensityAfter, trigger?}`, `SupportPlan`, `AppointmentQuestion`, `WeeklyGoal {status: done|difficult|need_help}`, `MotivationItem` (local only); offline-first logs.
