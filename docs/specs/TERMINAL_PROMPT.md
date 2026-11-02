Hi. You're in the BenMahdia repo. It's a Flutter + Riverpod patient app in apps/mobile,
a React + TypeScript dashboard for doctors in apps/dashboard, and a backend with
routers and migrations up to 0010. Recovery slices 1 to 4 already work, and I don't want
to lose any of that.

What I want: add the new features described in docs/specs/habit-tracking-design.md and
docs/specs/patient-doctor-messages-spec.md, one step at a time, without breaking
anything that already works.

Please start by reading CLAUDE.md, the PRD, DESIGN.md and both spec files. If anything
in them disagrees with what I write here, they win.

How I'd like you to work:

- Plan first. Before you touch any code, tell me which files you'll add, which existing
  files you'll change and why, and any new migrations, routes or translation keys.
  Then wait until I say "go".
- Only add, don't rework. New files, new migrations starting at 0011, new endpoints
  under /v1. Don't rename, move or delete what's there. Leave navigation as it is
  (moving to go_router is a separate job). New screens open the same way current ones do.
- Copy what's already there: same folders, the same fake/API repository switch on
  API_BASE_URL, Riverpod providers, every string in Arabic and French (nothing
  hardcoded), right-to-left first, Nafas design tokens only (teal fills use
  primary-icon #0c8578), tap targets of at least 44px, Western digits, no emoji and
  no exclamation marks.
- Branding belongs to the clinic. Every logo in the app and the dashboard comes from
  the clinic's files in branding/clinic/: launcher icon, splash screen, app header,
  dashboard sidebar, favicon, login page and notification icon. Check
  for any leftover placeholder or "Nafas" logo and swap it for the clinic's. Don't
  draw, generate or download a logo. If a size or variant is missing, tell me what
  you need. Small interface icons such as phone or lock stay in the icon set we use now.
- Respect privacy. Notifications stay neutral and never name a medicine or a
  substance. CBT journal sheets are private unless the patient shares a specific one.
  Audit logs never keep the text of a note.
- Prove nothing broke. Run flutter analyze, flutter test, the backend tests and the
  dashboard typecheck before you start and again when you finish, so I can compare.
- Stop after each step and give me a short summary plus the list of changed files.

The steps:
0. Clinic branding: swap every logo and icon for the clinic's files. Nothing else.
1. The "difficult moment" screen: breathing circle, craving intensity 1–10, HALT chips
   (hungry, angry, lonely, tired), the spicy food tip, the if-then plan, then a
   "craving passed" view with before and after. Also a small label that says who can
   see something ("Only you" / "Your doctor sees this").
2. Habits with forgiving streaks (one grace day), the 30-second daily check-in added
   to the existing check-in, and the monthly progress heatmap.
3. "Message my doctor about this medication": 5 reasons, medicine details attached
   automatically, the warning before sending, New → Reviewed → Replied, and the
   doctor's side in the patient's Medications tab on the dashboard (reply, mark as
   read, link to the existing prescription flow).
4. The CBT journal "Mon carnet TCC / دفتري": 5 fields, sharing one sheet at a time,
   exercises the doctor assigns, and doctor feedback.
5. 3 or 4 positive quotes a day as local notifications, taken from a clinic-approved
   list, with no repeats.

Let's begin with step 0. Read everything and send me the plan only.
