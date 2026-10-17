# BenMahdia — PRD

Oct 4, 2026 · @noufel douakh · Status: Draft v0.2 (updated Oct 13)

## 1. Overview

BenMahdia is a cross-platform (iOS + Android) mobile app, in Arabic and French, that connects psychiatrists with their addiction patients between sessions, hosted entirely in Algeria and sized for 200 patients at launch.

The app rests on three pillars:

1. **Auth and appointments** — secure accounts and precise, conflict-free scheduling between patients and their doctor.
2. **Recovery profile** — sobriety circles and day counters per addiction, motivational quotes, medication reminders, and an articles section in the spirit of Ta'aafi.
3. **AI support companion** — an LLM agent that offers psychological support between sessions, under the doctor's oversight.

**Problem.** Patients in addiction treatment are most at risk between appointments, when they have no contact with their doctor. Missed appointments, skipped medications, and unsupported cravings drive relapse.

**Vision.** Every patient carries their treatment in their pocket: their next appointment, their progress, their medications, and a supportive voice at any hour — while their doctor keeps visibility and control.

**Status.** Prototype / early stage. Target buyers are addiction clinics, sold as a per-clinic subscription. Pilot and first paying client: BenMahdia clinic.

## 2. Goals, non-goals and success metrics

The MVP succeeds if one clinic runs its addiction patients on the app for 3 months with fewer missed appointments and no data leaving Algeria.

**Goals**

- Let several doctors each manage their own patients from one platform.
- Reduce missed appointments and missed medication doses.
- Keep patients engaged daily through visible progress.
- Give patients safe, always-available support between sessions.
- Host all data and AI processing on servers located in Algeria.
- Ship updates quickly to both stores without breaking existing users.

**Non-goals (v1)**

- The AI never gives the patient a diagnosis, never prescribes and never changes medication. It may give the doctor flags and a short, non-binding assessment (6.5).
- No video consultations in v1.
- No booking or AI chat before identity verification (anyone can sign up, but the clinic verifies first).
- No web app for patients (doctors get a web dashboard).

**Success metrics (first 3 months)**

| Metric | Target |
| --- | --- |
| Active patients onboarded | 200 |
| Weekly active patients | ≥ 60% |
| Appointment no-show rate | −30% vs clinic baseline |
| Medication reminders confirmed | ≥ 70% |
| Crisis messages escalated to doctor | 100%, within 5 min |
| API uptime | ≥ 99.5% |
| Crash-free sessions | ≥ 99% |

## 3. Users and roles

Three roles, with each patient belonging to one primary doctor and seeing only their own data.

| Role | Who | Can do | Cannot do |
| --- | --- | --- | --- |
| Super admin | One of the 3 doctors (also holds the Doctor role) | Create and deactivate doctor accounts, approve new patient accounts, view platform stats, manage quotes library, configure AI settings | Read other doctors' patient conversations or notes through admin screens |
| Doctor (admin) | Psychiatrist | Manage their own patients, set availability, manage appointments, prescribe medication schedules, set addiction profiles, review AI alerts and summaries | See other doctors' patients (unless shared) |
| Patient | Person in treatment | Book, pay for and cancel appointments, track sobriety, confirm medications, read articles, chat with the AI companion, delete their account | See other patients, edit their medications |

**Multi-doctor rules**

- Pilot setup: BenMahdia clinic with 3 doctors, one of whom is also super admin. Doctors share one platform; data is isolated per doctor by default.
- A patient has one primary doctor; a doctor can transfer a patient to another doctor.
- Optional later: a clinic grouping so several doctors share a patient list.

**Each patient has their own addiction profile**

- One or more addictions per patient (e.g. opioids, cannabis, alcohol, tobacco, psychotropic pills, gambling, other).
- Per addiction: type, start-of-sobriety date, relapse history, triggers noted by the doctor, severity level.
- The doctor creates and edits the profile; the patient can log a relapse but cannot delete history.

## 4. Pillar 1 — Authentication and appointments

Patients join only by doctor invitation, and every appointment slot is enforced server-side so double-booking is impossible.

### 4.1 Authentication

- **Open sign-up:** any patient can create an account in the app with their phone number and a password, or with Google / Apple — no invite needed, then takes a live selfie and uploads a photo of their ID card for identity verification (4.2).
- **Login:** phone number + password, or Sign in with Google / Apple. Social login never skips identity verification. OTP by SMS for first login and password reset (local Algerian SMS gateway).
- **App lock:** 4–6 digit PIN or Face ID / fingerprint every time the app opens — protects privacy if the phone is shared.
- **Sessions:** short-lived JWT access token (15 min) + rotating refresh token; doctor can revoke a patient's sessions.
- **Doctors and super admin:** email + password + mandatory 2FA (TOTP app).
- **Account lockout** after 5 failed attempts; all logins audited.

### 4.2 Identity verification at sign-up

Every new patient proves who they are before using the app: a live face photo and a photo of their national ID card, matched by our server and approved by their doctor.

- **Flow:** after creating the account, the patient (1) takes a live selfie in the app with a simple liveness check (blink or turn the head), (2) uploads a photo of the front and back of their national ID card (taken with the camera or picked from the gallery or files), (3) submits. The account stays **pending verification** until the clinic approves it (a doctor or the super admin).
- **Capture rules:** the selfie must be taken live with the in-app camera (no gallery), so an old or borrowed photo can't be used. The ID can be uploaded; the app checks it for blur, glare and that the whole card is visible before allowing submission.
- **Face match:** our server in Algeria compares the selfie with the ID photo using an open-source face model and gives a match score. The score helps the doctor decide; it never rejects anyone on its own. Check the model's license allows commercial use.
- **Doctor approval:** a clinic doctor or the super admin sees both photos and the score, then approves or rejects with a reason. The patient can retry up to 3 times.
- **Pending accounts:** cannot book appointments or use the AI companion until approved (to confirm with the clinic).
- **Privacy and security:** ID and face photos are identity and biometric data. They are stored encrypted on Algerian servers, never sent to foreign verification services, never shown in notifications or logs, and visible only to the staff who review them and the patient's doctor. Every view is recorded in the audit log. The ID number is not extracted or stored unless the clinic needs it.
- **Consent:** a dedicated screen explains why the photos are collected, who can see them and how long they are kept. This processing must be included in the ANPDP authorization file.

**Acceptance criteria**

- [ ] The selfie cannot come from the gallery; the ID photo can be uploaded.
- [ ] A pending patient cannot open the AI companion or book an appointment.
- [ ] Only the reviewing staff and the patient's doctor can view the photos, and each view appears in the audit log.

### 4.3 Appointment management

- **Doctor availability:** weekly recurring schedule, short slots of 5, 10 or 15 min (set per doctor), breaks, holidays and one-off blocked days.
- **Booking:** patient picks a doctor and a free slot (the first doctor they book becomes their primary doctor) and pays online to confirm it (4.4); or the doctor books for the patient.
- **Precision rules:**
  - All times stored in UTC, displayed in Africa/Algiers (UTC+1).
  - Database constraint prevents overlapping appointments per doctor.
  - Slot is locked during booking to avoid two patients taking it at once.
  - Minimum notice to book or cancel (e.g. 24 h, configurable per doctor).
  - Patients can book up to 60 days ahead.
- **Follow-up:** after a visit, the app suggests the next one about 30 days later and opens the calendar on that day; the patient can pick an earlier or later day. A follow-up costs the same as any appointment.
- **Pilot payment:** until Chargily is wired, the app confirms only "pay at the clinic" appointments; card payments are confirmed solely by the signed webhook, never by the app.
- **Statuses:** requested → awaiting payment → confirmed → completed / cancelled / no-show / rescheduled. An unpaid hold is released after a short timeout (e.g. 15 min, to confirm).
- **Reminders:** push notification 24 h and 1 h before; doctor sees a daily agenda.
- **History:** patient sees past and upcoming appointments; doctor sees attendance rate per patient.
- **Doctor notes** after each appointment (private, never visible to the patient or the AI unless the doctor chooses).

**Acceptance criteria**

- [ ] Two patients booking the same slot simultaneously: exactly one succeeds.
- [ ] Reminder arrives within 1 minute of scheduled time on iOS and Android.
- [ ] A patient sees only free slots, never other patients' bookings or details.

### 4.4 Appointment payment

The patient pays for each appointment in the app through Chargily Pay; a slot is confirmed only once it is paid.

- **Methods:** CIB and Edahabia cards through Chargily Pay (Algerian gateway, amounts in DZD).
- **Flow:** patient picks a slot → slot is held → Chargily checkout opens → Chargily sends a signed webhook to the backend → appointment becomes confirmed and both sides are notified.
- **Price:** set per doctor by the super admin.
- **Receipts:** the patient sees a receipt in the app; the doctor and super admin see paid / unpaid status per appointment.
- **Cancellations and refunds:** deadline, refund or credit, and no-show rules to decide with the clinic.
- **Security:** the app never sees or stores card numbers; only Chargily's payment id and status are kept.

**Acceptance criteria**

- [ ] An appointment is confirmed only after a verified Chargily webhook, never from the app alone.
- [ ] A failed or abandoned payment releases the slot.
- [ ] The same webhook received twice does not record two payments.

## 5. Pillar 2 — Recovery profile

The home screen shows one progress circle per addiction, a daily quote, and today's medications — the reason patients open the app every day.

### 5.1 Sobriety circles and day counters

- One circular counter per addiction showing days (and hours) since the sobriety start date.
- The circle fills toward the next milestone: 1, 3, 7, 14, 30, 60, 90, 180, 365 days, then yearly.
- Milestone reached → celebration screen and badge; doctor is notified.
- **Relapse logging:** patient taps "I relapsed", optionally adds a note or trigger. Counter resets, but the app shows the longest streak and total sober days so progress is never erased. Message tone is supportive, never judgmental.
- Relapse → doctor gets an alert; the AI companion offers a supportive check-in.

### 5.2 Motivational quotes

- One quote per day, chosen by addiction type and recovery stage.
- Library managed by the super admin; doctors can add their own.
- Languages: Arabic, French (and optionally Darja and English).
- Patient can save favourites and share as an image.

### 5.3 Medication reminders

- Doctor sets each medication: name, dose, times per day, start/end date, instructions.
- Reminders are **scheduled locally on the phone**, so they work offline and no medical data passes through Apple or Google push servers.
- Patient taps **Taken / Skipped / Snooze**; history syncs to the server.
- Missed doses for 2+ days in a row → alert on the doctor's dashboard.
- Notification text stays neutral ("Time for your reminder") — no drug names on the lock screen.

### 5.4 Optional daily check-in (v1.1)

- 10-second mood and craving rating (1–5) once a day, plotted for the doctor.

### 5.5 Articles and resources

A library of short articles, like Ta'aafi's, that patients can read at any time.

- Topics: understanding addiction, cravings and triggers, relapse prevention, medication, family and support, motivation.
- Written or approved by the clinic's doctors and published from the dashboard, in Arabic and French.
- Filtered by addiction type; patients can save favourites.
- The AI companion can suggest a relevant article during a chat.

## 6. Pillar 3 — AI support companion

A self-hosted LLM agent gives supportive, CBT-style conversation between sessions; it is a companion under the doctor's supervision, never a replacement for the psychiatrist.

### 6.1 What it does

- Listens and responds empathetically in Arabic, French, and Darja.
- Uses evidence-based techniques: craving "urge surfing", breathing exercises, trigger identification, cognitive reframing, motivational interviewing.
- Knows safe context about the patient: first name, addiction type(s), current streak, upcoming appointment, today's medications taken or not. It never sees the doctor's private notes.
- Encourages the patient to keep appointments and medications.
- Sends the doctor flags and a short assessment of how the patient is doing in the program (6.5), if the patient consented.

### 6.2 What it must never do

- Tell the patient a diagnosis, or recommend or change medication or doses.
- Claim to be a human or a doctor — it introduces itself as an AI assistant.
- Give information that facilitates drug use, sourcing, or self-harm.
- Judge, shame, or moralise about relapse.

### 6.3 Safety and escalation (mandatory for launch)

- **Crisis detection** on every message: a separate classifier plus keyword rules detect suicidal thoughts, self-harm, overdose, violence, or medical emergency.
- On a crisis signal the AI stops normal conversation and shows a crisis screen: Algerian emergency numbers and the clinic's phone (exact numbers to confirm with the clinic), plus a one-tap call button.
- The patient's doctor receives an immediate high-priority alert.
- Every conversation is stored encrypted. Doctors see only flagged conversations (crisis or risk signals) and the AI flags and assessments — never the full chat history. Patients are told this at consent.
- Rate limit and session length limit to discourage unhealthy dependence; the AI regularly points the patient back to their doctor and real-life support.
- Clear disclaimer and explicit consent at first use.

### 6.4 Model approach

- First option: the LLM service of coconutStudio, an Algerian AI company — confirm it runs in Algeria and will sign a data-processing agreement for health data. Fallback: an open-weight model (e.g. Qwen, Llama, Gemma or Mistral family, 7–14B parameters, quantized) served with vLLM on a GPU server in Algeria — evaluate each on Arabic and Darja quality before choosing.
- System prompt + patient context injected per conversation (no fine-tuning needed for v1).
- Optional RAG over a doctor-approved knowledge base (coping techniques, psychoeducation).
- Red-team test set of 100+ risky prompts must pass before launch and on every model change.

### 6.5 Doctor brief: flags and short assessment

From the chats and the app data, the AI gives the doctor flags and a short assessment of the patient's progress in the program; the doctor always makes the clinical call.

**Flags**

- **Crisis** (instant, highest priority): suicidal thoughts, self-harm, overdose, violence.
- **Relapse risk rising:** stronger or more frequent cravings, contact with triggers, talk of using again.
- **Treatment issues:** missed doses, side effects or wish to stop medication mentioned in chat.
- **Mood:** low mood, hopelessness, sleep problems, anxiety repeated over several days.
- **Disengagement:** no app use or no chat for several days (threshold set by the doctor).

**Short assessment** — weekly and before each appointment, a few lines per patient:

- Program status: on track / needs attention / at risk.
- Mood and craving trend, medication adherence, streak.
- Main triggers and themes the patient raised this week.
- Observations worded with caution (e.g. "signs consistent with rising relapse risk"), plus suggested topics for the next appointment.

**Rules**

- Labelled "AI assessment — to be confirmed by the doctor"; decision support only, no formal diagnosis codes.
- Every flag shows the messages or data it is based on; those messages become visible to the doctor as a flagged conversation.
- Never shown to the patient.
- The doctor marks each flag or assessment as accurate or not; this feedback is used to tune the prompts.

**Acceptance criteria**

- [ ] Every flag links to the evidence it is based on.
- [ ] A patient can never see an assessment or a flag about them.
- [ ] A crisis flag reaches the doctor within 5 minutes.

## 7. Doctor / admin dashboard

Doctors work from a web dashboard (desktop browser) plus a lighter doctor view inside the mobile app for alerts and today's agenda.

**Doctor screens**

- **Today:** agenda, pending booking requests, unread alerts.
- **Alerts inbox:** crisis flags (highest priority), AI risk flags, relapses, missed medications, no-shows, milestones.
- **Patient list:** search and filter by addiction, streak, risk level, last activity.
- **Patient file:** addiction profile(s), streak history chart, medication adherence, appointments, mood check-ins, AI flags and short assessments and flagged conversations (no full chat history), private notes.
- **Medications:** create and edit schedules per patient.
- **Availability:** weekly schedule, holidays, slot length.
- **New patients:** review sign-ups (ID photos and match score), then approve or reject.

* **Payments:** paid / unpaid status per appointment, receipts.
* **Articles:** write, edit and publish articles for patients.

**Super admin screens**

- Doctor accounts (create, deactivate, reset 2FA).
- Platform stats (active users, appointments, uptime) — aggregated, no clinical content.
- Quotes and articles library, appointment prices and Chargily settings, AI configuration (crisis numbers, disclaimer text), minimum app version.
- Audit log of sensitive actions.

## 8. Non-functional requirements

All patient data, backups, and AI inference stay on servers physically in Algeria; the only exceptions are the push-notification relay and Google / Apple sign-in, which carry no medical content.

### 8.1 Hosting in Algeria

- Candidate providers to evaluate: Algérie Télécom data centers, ICOSNET, and the mobile operators' enterprise cloud offers. Selection criteria: GPU availability, uptime SLA, backup options, price in DZD.
- Production: 1 application server + 1 GPU server for the LLM + managed or self-run PostgreSQL with daily encrypted backups to a second Algerian location.
- No third-party analytics or crash tools that send data abroad; use self-hosted alternatives (e.g. self-hosted Sentry / GlitchTip, Umami).

### 8.2 Legal and compliance

- Comply with Algerian Law 18-07 on personal data protection; health data is sensitive and requires declaration/authorization with the national authority (ANPDP). Confirm the procedure with a local lawyer before launch. Status: ANPDP registration started; the form needs CNAS/CASNOS numbers, which require a legal status first (e.g. auto-entrepreneur). Planned setup: the clinic is data controller for its patients and you are the processor, under a written agreement.
- Explicit, granular patient consent: app use, AI chat, sharing AI summaries with doctor.
- Patient right to export their data and to delete their account from inside the app (required by Apple and Google). Deletion erases personal data after a grace period; anything the clinic must keep by law follows the retention policy agreed with the clinic.

### 8.3 Security

- TLS 1.3 everywhere; encryption at rest for the database and backups; AI conversations encrypted per patient.
- Role-based access control enforced in the API, not just the UI.
- Audit log of who viewed or changed patient data.
- No sensitive data in push notifications, logs, or app screenshots (screenshot blocking on sensitive screens).
- Penetration test before launch.

### 8.4 Cross-platform and updates

- One Flutter codebase for iOS and Android; minimum iOS 15 and Android 8.
- Distribution through App Store and Google Play; Android APK as a fallback for clinic devices.
- **Fast updates:** Shorebird code push for Dart-only fixes (minutes, no store review); store releases for native changes.
- **Forced update:** the API returns a minimum supported version; older apps show an update screen.
- Backend versioned API (/v1) so old app versions keep working during rollout.

### 8.5 Performance and scale

- Sized for 200 patients and 3 doctors at launch, designed to reach 2,000 without re-architecture.
- API p95 response < 300 ms; app cold start < 3 s on mid-range Android.
- AI first token < 2 s; up to 20 concurrent chats on one GPU.
- Uptime ≥ 99.5%; restore from backup tested monthly (RPO 24 h, RTO 4 h).

### 8.6 Localisation and accessibility

- Arabic (full right-to-left layout) and French at launch.
- Large tap targets, readable fonts, works on low-end phones and slow 3G/4G.

## 9. Technical architecture and data model

A Flutter app and a React dashboard talk to one FastAPI backend; the database, the LLM, and backups all run in Algeria.

&#91;embedded content: system architecture · Algeria-hosted\]

Only the push relay (Apple/Google) sits outside the country, and it carries generic text with no medical content.

**Stack**

| Layer | Choice |
| --- | --- |
| Mobile app | Flutter (Dart), Riverpod, local notifications, secure storage |
| Doctor dashboard | React + TypeScript |
| Backend | FastAPI (Python), Celery/Redis for reminders and background jobs |
| Database | PostgreSQL with row-level access by doctor |
| AI | coconutStudio LLM (first option) or vLLM with an open-weight model; separate crisis classifier |
| Infra | Docker Compose, Nginx, self-hosted monitoring and error tracking |
| CI/CD | GitHub Actions → store builds; Shorebird for code push |
| Payments | Chargily Pay (CIB / Edahabia), signed webhooks |
| Sign-in | Phone + password, Google Sign-In, Sign in with Apple |

**Core data model**

| Entity | Key fields |
| --- | --- |
| User | id, role (super\_admin / doctor / patient), phone, email, password hash, auth provider (password / Google / Apple), 2FA, language, deleted\_at |
| DoctorProfile | user\_id, specialty, slot length, booking/cancel notice |
| Patient | user\_id, primary\_doctor\_id, birth year, consent flags |
| Addiction | patient\_id, type, sobriety\_start, severity, triggers, active |
| Relapse | addiction\_id, date, note |
| Availability | doctor\_id, weekday, start, end, exceptions |
| Appointment | doctor\_id, patient\_id, start\_utc, end\_utc, status, price, payment\_id, private note |
| Medication | patient\_id, name, dose, times, start/end, instructions |
| DoseLog | medication\_id, scheduled\_at, status (taken / skipped / missed) |
| ChatMessage | patient\_id, role, encrypted content, risk flag, created\_at |
| Alert | doctor\_id, patient\_id, type, priority, read |
| Quote | text, language, addiction type, stage, author |
| AuditLog | actor, action, target, timestamp |
| Payment | appointment\_id, amount\_dzd, chargily\_id, status (pending / paid / failed / refunded), paid\_at |
| Article | title, body, language, addiction type, author doctor, published |
| AIAssessment | patient\_id, period, status (on track / attention / at risk), flags, text, evidence message ids, doctor feedback |

## 10. Release plan

About 16 weeks from kickoff to a 200-patient launch, with a pilot clinic gating the public release.

1. **Phase 0 — Foundations (weeks 1–2):** legal status (auto-entrepreneur) and CNAS/CASNOS numbers, ANPDP file, Algerian hosting contract, Chargily merchant account, Apple and Google developer accounts, design system, CI/CD, staging environment.
2. **Phase 1 — Core (weeks 3–7):** auth (phone, Google, Apple), ID verification, roles, doctor availability, 10–15 min appointments, Chargily payment, reminders, account deletion, doctor dashboard v1.
3. **Phase 2 — Recovery profile (weeks 6–9):** addiction profiles, sobriety circles, relapse flow, quotes, medication reminders, articles section.
4. **Phase 3 — AI companion (weeks 8–12):** model selection on Arabic/Darja, GPU deployment, crisis detection, escalation, red-team testing.
5. **Phase 4 — Pilot (weeks 13–15):** 1 clinic, 3 doctors, 20–30 patients; security pen test; fix and tune.
   - **Gate:** zero missed crisis escalations, crash-free ≥ 99%, doctor sign-off.
6. **Phase 5 — Launch (week 16):** store release, onboarding of up to 200 patients.

**Later (v1.1+):** daily mood check-ins, clinic grouping, video consultations, offline chat history.

## 11. Risks and open questions

The biggest risks are GPU hosting availability in Algeria and the AI's behaviour with vulnerable patients.

| Risk | Impact | Mitigation |
| --- | --- | --- |
| No suitable GPU server available locally | AI pillar delayed | Confirm with providers in Phase 0; fallback to a smaller CPU-quantized model with slower replies |
| AI gives harmful or wrong advice | Patient harm, legal liability | Crisis classifier, strict system prompt, red-team suite, doctor oversight, clear disclaimer |
| Weak Arabic/Darja quality of open models | Low trust and engagement | Benchmark several models with real (anonymised) phrasing from the clinic |
| Apple developer account and payment from Algeria | iOS release blocked | Open the account early; check payment card options |
| Push relay through Apple/Google servers | Conflicts with "100% Algeria" requirement | Generic notification text, local scheduling for medications |
| Low daily engagement | Doctors lose interest | Milestones, quotes, doctor encouragement messages |
| No legal status yet | Can't finish ANPDP, sign with the clinic or open Chargily | Register as auto-entrepreneur first, then CNAS/CASNOS, NIF and a business bank account |
| Chargily merchant approval takes time | Paid booking blocked at pilot | Apply early; during the pilot the doctor can confirm slots paid at the clinic |
| Google / Apple sign-in runs outside Algeria | Questions on the 100% Algeria rule | Only identity tokens pass, no health data; declare it in the ANPDP file |
| AI assessment read as a medical diagnosis | Liability; could be treated as a medical device | Decision support only, doctor confirms, cautious wording, no diagnosis codes; check with a lawyer |
| Fake or spam sign-ups | Staff time wasted reviewing accounts | SMS OTP and rate limits at sign-up; ID verification before any booking |

**Open questions (details to add later)**

- [ ] Pilot clinic confirmed: BenMahdia — 3 doctors, one is super admin. Remaining: pilot start date
- [ ] Business model: per-clinic subscription (decided). Remaining: monthly vs yearly billing, price in DZD, patient cap per plan
- [ ] Exact Algerian crisis/emergency numbers and the clinic's on-call line.
- [ ] Can a patient see more than one doctor (e.g. psychiatrist + psychologist)?
- [ ] Doctor access to AI chats: flagged conversations and summaries only (decided)
- [ ] Data retention period after a patient leaves treatment, including ID card and face photos.
- [ ] Final hosting provider and server specs.
- [ ] Languages for v1: Arabic + French only, or Darja and English too?

* [ ] Appointment price, and refund rules for cancellations and no-shows.
* [ ] Whose Chargily account receives the payments: the clinic's or yours?
* [ ] Who writes and approves the articles, and how many at launch?
* [ ] coconutStudio: confirm hosting in Algeria, pricing and data-processing terms.

## 12. System workflows

The five flows below are what the backend, the patient app and the dashboard must support end to end.

### 12.1 Patient onboarding

1. The patient downloads the app and creates an account: phone + password, or Google / Apple.
2. No invite is needed, but nothing clinical (booking, AI chat) unlocks before verification.
3. An SMS OTP confirms the phone number.
4. The patient photographs their ID card and takes a live selfie; the server computes a match score and clinic staff approve or reject. Once approved, the patient picks a doctor and books (12.2).
5. Consent screens (app use, AI chat, summaries to the doctor, ID photos), then PIN or biometric lock, then the home screen.

### 12.2 Booking and payment

1. The patient picks a free 5–15 min slot; the slot is held for 15 min (one open hold per patient).
2. Chargily checkout opens (CIB / Edahabia).
3. The backend verifies Chargily's webhook → the appointment is confirmed → both sides are notified; reminders go out 24 h and 1 h before.
4. After the visit the doctor marks it completed or no-show and can add a private note.

### 12.3 Daily recovery loop

1. The patient opens the app: day counters, quote of the day, today's medications.
2. They mark each dose taken or skipped and can read an article.
3. A logged relapse resets the counter (longest streak kept), alerts the doctor, and the AI offers a supportive check-in.

### 12.4 AI chat and escalation

1. Every message first goes through the crisis classifier and keyword rules.
2. No risk → the LLM replies with the patient's safe context.
3. Risk → crisis screen with emergency numbers, instant doctor alert, conversation flagged.
4. The doctor gets flags in real time and a short assessment weekly and before each appointment (if the patient consented).

### 12.5 Account deletion

1. Settings → Delete account → confirm with PIN.
2. The account is disabled at once and the doctor is notified.
3. Personal data is erased after the grace period; records the clinic must keep follow the retention policy.

## 13. Build steps

Paperwork first, because ANPDP, Chargily and the clinic contract all depend on your legal status.

**Step 1 — Paperwork (now)**

- [ ] Register as auto-entrepreneur.
- [ ] Get CNAS/CASNOS, NIF and a business bank account.
- [ ] Finish and submit the ANPDP authorization file.
- [ ] Sign the processing agreement and pilot terms with BenMahdia.
- [ ] Open the Chargily merchant account and the Apple and Google developer accounts.
- [ ] Confirm coconutStudio's terms; choose the Algerian host.

**Step 2 — Foundations (weeks 1–2)**

- [ ] Repo, CI/CD, staging server, Arabic RTL + French design system.
- [ ] Database schema from section 9.

**Step 3 — Core (weeks 3–7)**

- [ ] Open sign-up with phone / Google / Apple, OTP, PIN lock, roles.
- [ ] ID verification and doctor approval.
- [ ] Availability, 10–15 min booking, Chargily payment and webhooks, reminders.
- [ ] Account deletion; doctor dashboard v1.

**Step 4 — Recovery profile (weeks 6–9)**

- [ ] Counters, milestones, relapse flow, quotes, medication reminders.
- [ ] Articles section and its editor in the dashboard.

**Step 5 — AI companion (weeks 8–12)**

- [ ] Test coconutStudio against open models on Arabic and Darja.
- [ ] Crisis detection, doctor alerts, flagging, weekly summaries.
- [ ] Red-team with 100+ risky messages written with the doctors.

**Step 6 — Pilot (weeks 13–15)**

- [ ] BenMahdia, 3 doctors, 20–30 patients; pen test; fixes.

**Step 7 — Launch (week 16)**

- [ ] Store release and onboarding of up to 200 patients.
