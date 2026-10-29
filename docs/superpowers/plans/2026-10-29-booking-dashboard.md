# Booking dashboard — implementation plan

Oct 29, 2026 · Status: done (Oct 29), on branch `claude/booking-dashboard`

Goal: finish the doctor dashboard for the booking system (PRD 4.3, 4.4, 7).
Six features are missing, plus one bug found while reading the code.

Rules that apply to every step (CLAUDE.md):

- Arabic RTL + French for every new string; colors, fonts and spacing only from design tokens.
- Schedule data (who has a visit when) is clinic-wide. Clinical data (notes) only for the doctor's own patients. Enforced in the API.
- No medical content in alerts, logs or the audit log (audit stores row ids only).
- Tests for every new endpoint, including the isolation cases (other doctor, patient token, no token).
- One small commit per step.

## What already exists

| Piece | Where |
| --- | --- |
| `DoctorProfile` (slot length, price, notice, hold) | `backend/app/models.py:228` |
| `Availability` (weekly windows, breaks = gaps) | `models.py:250` |
| `AvailabilityException` (blocked day + reason) | `models.py:273` |
| Slot arithmetic | `backend/app/scheduling.py` |
| Patient receipt endpoint | `backend/app/routers/appointments.py:317` |
| Field encryption (AES-GCM, key in `.env`) | `backend/app/idcrypto.py` |
| Staff routes, `current_doctor` | `backend/app/routers/staff.py` |

Today the hours can only be changed in the database (`backend/app/seed.py` says so).

## Step 0 — Fix: agenda actions on other doctors' rows

`GET /v1/staff/agenda` returns every doctor's visits (correct, PRD 3), but the
rows don't say whose visit it is. The Today page shows "Mark paid / Completed /
No-show" on all rows, and the API answers 404 for the other doctors' rows, so the
button silently does nothing.

- Backend: add `doctor_name_ar`, `doctor_name_fr` and `mine: bool` to `AgendaItem`.
- Dashboard: show the doctor's name column; show action buttons only when `mine`.
- Tests: agenda flags `mine` correctly for two doctors.

## Step 1 — Who is signed in: `GET /v1/staff/me`

Needed to show the super-admin pages and the doctor's own settings.

- Returns `id`, `role` (`doctor` / `super_admin`), `name_ar`, `name_fr`.
- Tests: doctor, super admin, patient token → 403, no token → 401.

## Step 2 — Availability page (PRD 4.3, 7: "weekly schedule, holidays, slot length")

**Backend** — all scoped to the signed-in doctor:

| Endpoint | Does |
| --- | --- |
| `GET /v1/staff/availability` | slot length, notice hours, weekly windows, blocked days from today on |
| `PUT /v1/staff/availability/windows` | replaces the whole weekly schedule in one transaction |
| `PUT /v1/staff/availability/settings` | `slot_minutes` ∈ {5, 10, 15}, `notice_hours` 0–168 |
| `POST /v1/staff/availability/blocked-days` | blocks a day (`day`, optional `reason` ≤ 120 chars) |
| `DELETE /v1/staff/availability/blocked-days/{id}` | unblocks it (own only, else 404) |

Validation: weekday 0–6, minutes on a 5-minute grid, start < end, no two windows
overlapping on the same day, at most 6 windows per day; a blocked day cannot be
in the past; the same day twice → `409 already_blocked`.

Safety:

- Changes lock the doctor's row (`with_for_update`), like `hold_slot` does, so a
  patient can't hold a slot while the hours are being replaced.
- A change **never moves or cancels** existing confirmed appointments. Each write
  returns `conflicts`: upcoming confirmed visits that now fall outside the hours
  or on a blocked day (time + patient phone, no clinical data). The page shows
  them so the clinic can call those patients.
- Every change goes in the audit log.

**Dashboard** — new nav item "Availability" (الأوقات / Disponibilités):

- One row per weekday, each with its windows (from–to, 24 h, `dir="ltr"`), add / remove a window, the gaps shown as breaks, and "N slots" per day.
- Slot length (5 / 10 / 15) and notice (hours).
- Blocked days: list + add a date with an optional reason + remove.
- Save button; after saving, a warning card lists any `conflicts`.
- Loading, error, empty states like the other pages.

**Tests:** each endpoint (happy path, validation, another doctor's exception → 404,
patient → 403), conflict reporting, and the patient calendar reflecting the new hours.
Dashboard: render, add/remove window, save, conflict warning, both languages.

## Step 3 — Prices (PRD 4.4: "set per doctor by the super admin")

**Backend:**

| Endpoint | Does |
| --- | --- |
| `GET /v1/admin/doctors` | every doctor: names, price, slot length |
| `PUT /v1/admin/doctors/{id}/price` | `price_dzd` 0–100 000 |

- Super admin only (new `current_super_admin` dependency); a plain doctor gets 403.
- A new price applies to new holds only: booked appointments keep their stored price (already how `Appointment.price_dzd` works).
- Audited.

**Dashboard:** "Prices" page, in the nav only when `me.role == super_admin`. One
row per doctor with the price in DA and a Save button.

**Tests:** super admin can, doctor 403, patient 403, invalid price 422, existing appointment keeps its old price.

## Step 4 — Pending booking requests on Today (PRD 7: "Today: agenda, pending booking requests, unread alerts")

In this code a "request" is an open hold (`awaiting_payment`, not expired). The
agenda hides them on purpose.

- Backend: `GET /v1/staff/holds?day=` → the clinic's open holds for that day (time, doctor, patient phone, method if chosen, minutes left). Read-only: a card hold is confirmed only by Chargily's webhook, a clinic hold only by the patient.
- Dashboard: a "Waiting for payment" card above the agenda; hidden when empty.
- Also on Today: an "Unread alerts: N" card that opens the Alerts page (the count already exists in `App.tsx`).
- Tests: expired holds are excluded, confirmed visits are excluded, patient → 403.

## Step 5 — Appointment history + attendance in the patient file (PRD 4.3: "doctor sees attendance rate per patient")

- Backend: `GET /v1/staff/patients/{id}/appointments` → all of the patient's appointments in the clinic (schedule data), newest first: time, doctor, status, paid, method, price, `mine`, `has_note` (own appointments only). Plus `attendance`: completed, no-shows, rate = completed / (completed + no-shows), `null` when there are none.
- Only for the doctor's own patients (same rule as the rest of the patient file), else 404.
- Dashboard: "Appointments" card in `PatientDetail` with the attendance rate on top and the list below.
- Tests: rate math, other doctor's patient → 404, holds not listed.

## Step 6 — Private doctor notes (PRD 4.3: "Doctor notes after each appointment")

- New table `appointment_notes`: `id`, `appointment_id` (unique, FK, cascade), `doctor_id`, `text_enc`, `created_at`, `updated_at`. Migration `0013_appointment_notes.py`.
- Text encrypted at rest with `idcrypto` (its own `kind`); ≤ 5 000 characters.
- `GET` / `PUT /v1/staff/appointments/{id}/note`: only the appointment's own doctor (another doctor → 404). Writable once the visit has started. Empty text deletes the note.
- Never returned by any patient route, never sent to the AI, never in logs; the audit stores the note id only.
- Dashboard: in the appointment history (Step 5), a "Note" button on own appointments opens an editor.
- Tests: own doctor read/write, other doctor 404, patient 403, before start → 409, stored encrypted (raw column ≠ text), no patient endpoint exposes it.

## Step 7 — Payments and receipts (PRD 4.4, 7: "Payments: paid / unpaid status per appointment, receipts")

- Backend: move the receipt builder out of `appointments.py` into one shared function (patient route unchanged).
- `GET /v1/staff/appointments/{id}/receipt`: own appointments; super admin any. Not paid → 409.
- `GET /v1/staff/payments?from=&to=` (max 92 days): own appointments (super admin: all) with paid / unpaid, method, amount, and totals.
- Dashboard: "Payments" page with a date range, the table and totals; a "Receipt" button on paid rows (also in Today and the patient history) opens a dialog with "Copy as text".
- Tests: receipt for own / other doctor / super admin, totals, range limit, refactor keeps the patient receipt identical.

## Order and commits

0 → 1 → 2 → 3 → 4 → 5 → 6 → 7, each step = backend + tests, then dashboard + tests, then one commit. After each step: `pytest`, dashboard `vitest` + `tsc` + lint.

## Decisions (Oct 29)

1. Doctor books for the patient: not in this round.
2. Notes are always private in v1: no "share with the AI" toggle.
3. The Availability page starts the week on Saturday.
4. "Needs refund" payments: later, once the clinic sets its refund rules.

## Follow-ups found while building

- **No super admin in the seed.** `app/seed.py` creates one plain doctor, so nobody can open the Prices page until an account's role is set to `super_admin` in the database. Which pilot doctor is the super admin is the clinic's call.
- **Time fields follow the browser's locale.** The Availability page uses the browser's time picker: 24-hour on a French or Arabic computer, AM/PM on an English one.
- **Patient-file access is still "any doctor the patient booked once"** (QA SEC-02, still a strict xfail). The new history card uses the same rule; notes are stricter (the visit's own doctor only).
- **Refunds** for card payments that arrive after their slot was released are still to be decided with the clinic.
