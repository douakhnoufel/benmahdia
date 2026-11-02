# BenMahdia — patient ↔ doctor: medication messages + CBT journal (2026-11-02)

Designed on the canvas (second row "Patient ↔ doctor"): https://claude.ai/artifact/UgKQxEc1udgtJMumRF4JsP — artboards `MedMessage`, `DoctorMeds`, `Journal`. Not built yet. Builds on slice 3 (prescriptions, doses) and slice 4 (alerts, dashboard patient file).

## 1. Message my doctor about this medication (v1 = simple)
**Patient (mobile)**
- Action "مراسلة الطبيب بخصوص هذا الدواء" on each medication card.
- Reason (one): how I feel / possible side effects · I missed a dose · hard to follow the schedule · running out · I have a question.
- Note (text, required) + optional "since when" chips (today, a few days, a week, longer).
- Auto-attached server-side: medication name, prescribed dose/schedule, timestamp. The patient never retypes them.
- Shown before sending: "Messages may not be read immediately. Don't change your medication based on this message alone." + link to urgent help.
- Sharing label: "Only your doctor sees this".
- After sending: status New → Read → Replied; "keep taking your medicine as prescribed until the doctor replies".

**Doctor (dashboard)**
- Messages appear under the patient's medication history (Medications tab of the patient file) and in a "Medication messages" list with an unread count.
- Statuses: New → Reviewed → Replied. "Mark as read", text reply, "Edit prescription" opens the existing prescribing workflow.

**Notifications:** private and neutral (no medicine name, no medical words), for the patient (doctor replied) and the doctor (new message).

**v1 scope:** text notes, doctor replies, read status, private notifications. No attachments, no chat threads beyond one reply per message, no voice.

**Data sketch:** `MedicationMessage {id, patient_id, medication_id, reason enum, note ≤1000, since enum?, med_snapshot {name, dose, schedule}, created_at, status new|reviewed|replied, reviewed_at?, reply?, replied_at?, doctor_id}`. Audit log without the note text (same rule as alerts). Routes: `POST /v1/me/medications/{id}/messages`, `GET /v1/me/medication-messages`, `GET /v1/staff/patients/{id}/medication-messages`, `POST …/{msg}/review`, `POST …/{msg}/reply`.

## 2. My CBT journal — « Mon carnet TCC / دفتري »
**Patient sheet fields:** الموقف Situation · الأفكار Thoughts · المشاعر Emotions + intensity (0–100 %, several emotions) · السلوك Behaviour · ملاحظة للطبيب Note to the doctor (optional).
- Example: "After an argument I wanted to use. I called someone close. I want to discuss it at my next session."
- **Private by default.** The patient explicitly turns on "Share this sheet with my doctor" per sheet; label "Only you" / "Your doctor sees it and can reply".
- Exercises assigned by the doctor show as a banner with progress (e.g. "Record one difficult situation every day this week · 3/7").

**Doctor:** assigns an exercise, reads shared sheets only, leaves feedback on a sheet. A "دفتري" tab in the patient file.

**Data sketch:** `JournalEntry {id, patient_id, situation, thoughts, emotions [{name, intensity}], behaviour, note_for_doctor?, shared bool, shared_at?, exercise_id?, created_at}`, `JournalFeedback {entry_id, doctor_id, text, created_at}`, `Exercise {id, patient_id, doctor_id, title, instructions, per_week target, start, end}`.

## Open questions
- Unshared journal sheets: on the phone only, or on the server encrypted?
- Exercise library: free text by the doctor, or a few clinic-approved templates (thought record, behaviour log, coping plan)?
- Reply time the clinic can promise (shown to the patient), and what happens outside clinic hours.
- Should "strong side effects" also raise an alert like a relapse?
