# Security / isolation: booking QA, 2026-10-25

Tester: security-isolation. Rules covered: every row with Area = security in `rules.md` (R-17, R-31, R-40, R-62, R-64, R-65, R-66, R-67, R-68, R-69, R-70). Checked against the PRD §3 role matrix as updated: booking data is clinic-wide, clinical data stays with each doctor.

Test file: `backend/tests/test_qa_booking_isolation.py` (new; this is the only code file I touched).

Command (run from `backend/`):

```
.venv/Scripts/python.exe -m pytest tests/test_qa_booking_isolation.py -p no:cacheprovider -p no:logging --disable-warnings
```

Result: **88 passed, 5 xfailed** in 79 s, SQLite. Each xfail is strict and points to a finding below.

## Findings

### SEC-01: The doctor agenda shows only the caller's own appointments, not the whole clinic's
- Severity: high
- Rule: R-65 (PRD §3, multi-doctor rules)
- Where: backend/app/routers/staff.py:166 (`Appointment.doctor_id == doctor.user_id` in `agenda`)
- Repro: test_doctor_sees_another_doctors_agenda in backend/tests/test_qa_booking_isolation.py (xfail)
- Expected (PRD): "appointments and agendas are visible to every doctor in the clinic". Doctor A's agenda for a day lists doctor B's booked visits as well.
- Actual: doctor A gets only their own rows. Also, the existing test `tests/test_staff.py:80 test_agenda_shows_only_my_booked_visits_of_the_day` asserts the old own-only rule, so it will fail once this is fixed. I did not edit it. The fixer needs to update it at the same time.

### SEC-02: Any doctor the patient has booked once can read that patient's clinical data
- Severity: high
- Rule: R-67 (PRD §3)
- Where: backend/app/routers/medications.py:110-124 (`_own_patient`, also used by backend/app/routers/staff_recovery.py:21,65 for addictions); related: backend/app/routers/recovery.py:182-191 (`_doctor_of` sends relapse alerts to whichever doctor the patient booked *last*)
- Repro: test_one_booking_with_another_doctor_does_not_open_clinical_data (xfail). Patient's history is with doctor A, then they book one visit with doctor B, and both A and B get 200 on `/v1/staff/patients/{id}/medications` and `/addictions`.
- Expected (PRD): each patient has one primary doctor. A doctor sees clinical data (notes, medications, addictions, AI flags) only for their own patients plus shared or transferred ones. Booking is now clinic-wide, so a booking alone must not grant clinical access.
- Actual: the code treats "has a non-hold appointment with this doctor" as ownership. A patient can be linked to several doctors this way. No primary-doctor, sharing or transfer field exists in `models.py`. The test only asserts "at most one doctor reads it". It does not assume which doctor is primary (see Q2).

### SEC-03: Super admin cannot use any doctor screen
- Severity: high
- Rule: R-70 (PRD §3)
- Where: backend/app/routers/staff.py:88-94 (`current_doctor` requires `Role.doctor`; `Role.super_admin` is a separate value, models.py:32-35)
- Repro: test_super_admin_can_use_doctor_booking_screens (xfail). A super admin with a doctor profile signs in (staff login accepts the role, staff.py:107), then `GET /v1/staff/agenda` returns 403 `forbidden`.
- Expected (PRD): the super admin is "one of the 3 doctors (also holds the Doctor role)".
- Actual: refused on every `/v1/staff/*` route. Isolation still holds: the super admin cannot read another doctor's patients' medications or addictions (test_super_admin_cannot_read_another_doctors_patients_clinical_data passes, though only because every staff route refuses them).

### SEC-04: There is no clinic-staff (secretary) role, so front-desk check-in and ID review by staff are impossible
- Severity: high
- Rule: R-62, R-69 (PRD §3, §4.3 booking code, §4.2 approval, §7)
- Where: backend/app/models.py:32-35 (`Role` = super_admin, doctor, patient); staff.py:88-94
- Repro: test_a_clinic_staff_role_exists (xfail)
- Expected (PRD): clinic staff review and approve or reject ID declarations, and a secretary can run check-in at the front desk. They never see clinical data.
- Actual: the role does not exist. Check-in (`/v1/staff/checkin`) and ID approval are reachable only with a doctor token. I could not test the "staff see no clinical fields" half beyond the agenda and check-in reply shapes (those pass, see below).

### SEC-05: A plain doctor approves and rejects ID declarations
- Severity: medium
- Rule: R-69 (PRD §3, §4.2 Approval)
- Where: backend/app/routers/staff.py:353 (`approve`) and :373 (`reject`), both use `current_doctor`
- Repro: test_a_plain_doctor_cannot_approve_an_id (xfail). The seeded doctor gets 200 on `POST /v1/staff/signups/{id}/approve`.
- Expected (PRD): approval belongs to clinic staff (and the super admin, "approve new patient accounts"). A plain doctor's role row does not list it.
- Actual: any doctor can approve or reject. The existing tests `tests/test_staff.py:170 test_signups_list_and_approve` and `:185 test_reject_signup` assert doctors do this. Not edited. Depends on SEC-04.

## Questions (the PRD does not say; not counted as bugs)

- **Q1: Can a doctor act on another doctor's appointment?** PRD §3 says a doctor can "manage appointments (and see every doctor's appointments and agenda)". Today doctor A gets 404 when marking completed or no-show (`/staff/appointments/{id}/status`), marking paid (`/paid`) or checking in a code that belongs to doctor B's appointment (staff.py:130-134, :208; `tests/test_checkin.py:125`, `tests/test_staff.py:115`). Is managing others' appointments meant to be read-only, or allowed?
- **Q2: How is the primary doctor recorded, and how are sharing and transfer recorded?** None of it is modelled. Which doctor is primary when a patient has booked several? Should relapse alerts (recovery.py:182) go to the primary doctor instead of the last-booked one?
- **Q3: Which doctors does a secretary serve?** Is check-in clinic-wide (any doctor's code) or per doctor? This is needed to build SEC-04.
- **Q4: Should doctors still see ID data once clinic staff exist?** Today any doctor can open the full name and birth date of every patient in the sign-up queue (staff_identity.py:40-57). This is ID data, not clinical data, but once SEC-04/05 are fixed it may belong to staff only.
- **Q5: Is the patient's phone booking data?** With the agenda going clinic-wide (SEC-01), every doctor would see every patient's phone (`AgendaItem.patient_phone`). I assume this is intended, but please confirm.

## What passed (no finding)

- **R-64**: patient A on patient B's appointment. `DELETE /hold`, `POST /confirm`, `/cancel` and `/checkout`, each on B's hold and on B's confirmed visit, return exactly the same status and body as a random UUID (404 `appointment_not_found`). B's row is unchanged and no Chargily checkout is opened (8 cases).
- **R-31**: `GET /v1/appointments` and `/follow-up` show only the caller's rows. Another patient's id and check-in code are absent.
- **R-17**: the patient calendar has slot keys `start` and `free` only. A slot that someone else booked or holds is `free: false`. The body contains none of the other patient's id, phone, appointment id or code.
- **R-68**: a patient token on 9 staff routes returns 403 `forbidden`. A doctor token on 9 patient routes returns 403 `forbidden`. A missing, garbage or forged (wrong-secret) token on all 18 routes returns 401. A refresh token used as an access token returns 401. An expired access token (clock moved past 15 min) returns 401 for both patient and doctor.
- **R-66**: agenda and check-in replies use only id, patient_id, patient_phone, start, end, status, method, price_dzd, paid and checked_in_at. They have no clinical keys, and no medication text appears even when the patient has medications, addictions and alerts. The check-in code is not echoed. Patient appointment replies have no clinical keys either.
- **R-67** (clear case): a doctor with no link to a patient gets the same 404 as for a random id on list, prescribe and stop medications, list addictions, confirm addiction and mark another doctor's alert read. Their alert list and patient list stay empty, and nothing is changed.
- **R-40**: hold, confirm, cancel and check-in each write one audit line whose target is the appointment UUID. A wrong check-in code is logged with no target. No booking audit line contains the check-in code, a typed wrong code, the phone, or clinical text. (The ID-number half is covered only indirectly: booking targets are all UUIDs.)
