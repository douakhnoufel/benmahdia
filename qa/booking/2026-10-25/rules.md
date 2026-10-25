# Booking rules checklist — 2026-10-25

Written by the rules-extractor. Sources: `docs/PRD.md` §3 (role matrix, updated: booking data is clinic-wide, clinical data stays per doctor), §4.2 gating, §4.3, §4.4, §5 unlock, §7, §8.6, §12.2. Code read at commit `ed39254` plus the working tree.

How to read the columns:
- **Enforced at**: file:line where the rule is enforced. `not found` = no code enforces it. `partial` = some of it is enforced, the note says what is missing.
- **Covered by**: an existing test that checks the rule. `uncovered` = no test. `partial` = a test touches it but misses the edge named.
- File shorthands: `appt` = `backend/app/routers/appointments.py`, `pay` = `backend/app/routers/payments.py`, `staff` = `backend/app/routers/staff.py`, `doc` = `backend/app/routers/doctors.py`, `sched` = `backend/app/scheduling.py`. Test files: `t_appt` = `backend/tests/test_appointments.py`, `t_pay` = `test_payments.py`, `t_chk` = `test_checkin.py`, `t_doc` = `test_doctors.py`, `t_staff` = `test_staff.py`, `t_race` = `test_concurrent_holds.py`, `t_mod` = `test_models_appointments.py`, `m_book` = `apps/mobile/test/booking_test.dart`, `m_api` = `apps/mobile/test/api_booking_repository_test.dart`, `m_prof` = `apps/mobile/test/profile_test.dart`, `d_dash` = `apps/dashboard/src/test/dashboard.test.tsx`.

## Gating (PRD §4.2, §5)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-01 | A patient whose ID is not approved cannot hold, confirm, check out, list or cancel (API) | §4.2 Gating + AC | `backend/app/deps.py:32-38` (`verified_patient`; checks `User.status == verified`, not `id_status` directly) | t_appt::test_hold_needs_a_login_and_a_verified_patient, test_list_needs_a_verified_patient; t_pay::test_checkout_needs_a_verified_patient | api |
| R-02 | Each non-approved ID state is refused: `none`, `declared`, `rejected`, `duplicate` | §4.2 Status values, Gating | `deps.py:37` (all map to `pending_verification`/`rejected` account status) | partial — only a pending account (`declared`/`none`) is tested; `rejected` and `duplicate` uncovered | api |
| R-03 | Doctor list and calendar are closed to non-approved patients and to no token | §4.2 Gating | `doc:75`, `doc:84` | t_doc::test_doctors_need_a_login, test_pending_patient_cannot_see_doctors, test_calendar_needs_a_verified_patient | api |
| R-04 | After approval the patient can book | §4.2 Gating | `staff:352-369` sets `verified` | t_staff::test_approved_patient_can_then_book | api |
| R-05 | Automatic approval when all checks pass (scanner-read, unedited, HMAC unused, one face) unlocks booking without staff | §4.2 Approval | not found — only `staff:360` sets `verified`; no auto path in `backend/app/routers/identity.py` | uncovered | api |
| R-06 | Recovery tracking (addictions, daily check, medications seen by patient) refused until the first appointment is confirmed (paid) | §4.2 AC, §5 Unlock, §12.1 step 6 | not found — `backend/app/routers/recovery.py:38-41` and `checkins.py:38` only check role | uncovered | api |
| R-07 | App shows "being reviewed" on the appointments screen while ID is `declared`; never "verified" / "vérifié" / "موثق" | §4.2 Gating, AC | `apps/mobile/lib/features/booking/booking_flow.dart:88-109` | m_prof::"after sending, the card waits for the clinic", "an approved patient sees no card and can book"; wording check uncovered | ux |
| R-08 | The profile step cannot be skipped (booking gate must not offer a skip path) | §4.1, §4.2 | partial — `booking_flow.dart:75-77` comment and m_prof "skip comes back and carries on" describe a skip, contradicting "no Skip" | m_prof::"a patient who skipped sees the card, and book leads to it" (tests the opposite of the PRD) | ux |

## Slots and calendar (PRD §4.3)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-09 | Slot length is 5, 10 or 15 min per doctor (DB check) | §4.3 Availability | `backend/app/models.py:233` `ck_slot_minutes` | t_mod::test_allowed_slot_lengths, test_rejects_other_slot_lengths; t_doc::test_slot_length_follows_the_doctor (10 min only; 5 min uncovered) | api |
| R-10 | Weekly recurring windows; breaks are gaps; a slot must fit entirely inside a window | §4.3 Availability | `sched:170-178` | t_doc::test_calendar_shape_and_rules; last-slot-overrun edge uncovered | api |
| R-11 | Holidays / one-off blocked days have no slots and cannot be held | §4.3 Availability | `appt:112-118`, `sched:215-216` | t_doc::test_blocked_day_is_closed; t_appt::test_slot_rules | api |
| R-12 | A hold must be on the doctor's slot grid (no off-grid start) | §4.3 | `appt:119-120` | t_appt::test_off_grid_start_is_refused | api |
| R-13 | Minimum notice to book (default 24 h, per doctor): slot earlier than now+notice is refused; exactly at notice is allowed | §4.3 Precision | `appt:106-107` (`start < now + notice`) | t_appt::test_slot_rules (inside notice); exact boundary and per-doctor value uncovered | api |
| R-14 | Booking horizon 60 days ahead | §4.3 Precision | `appt:108-111` (clinic day `>= today+60` refused, so today..today+59), `backend/app/config.py:61`; calendar `doc:110` | t_appt::test_slot_rules (day far beyond); t_doc 60 days; day 59 vs day 60 boundary uncovered | api |
| R-15 | Times stored in UTC, shown in Africa/Algiers; a start sent with a non-UTC offset is normalised | §4.3 Precision | `appt:77-80` (`_naive_utc`), `sched:157-167`; mobile `api_booking_repository.dart:34` (fixed +1 h) | t_doc::test_calendar_shape_and_rules (08:00Z = 09:00); m_api "now is clinic time", "reads the calendar in clinic time"; non-UTC offset in hold body uncovered | api |
| R-16 | Algiers midnight vs UTC midnight: horizon/notice/"today" use the clinic day | §4.3 Precision | `appt:108-109`, `sched:166-167` | uncovered for holds/calendar (only check-in has t_chk::test_the_day_is_the_clinic_day_not_the_utc_day) | api |
| R-17 | Patient calendar shows free/busy only — no other patient's name, phone or id | §4.3 AC 3 | `doc:38-41` (`SlotOut` has only start, free), `sched:213-229` | t_doc::test_booked_slot_is_not_free_and_reveals_nothing | security |
| R-18 | Active holds and confirmed visits block a slot; expired holds, cancelled, completed, no-show do not | §4.3 Statuses | `sched:181-189`; `appt:155` | t_doc::test_active_hold_blocks_but_expired_hold_does_not, test_cancelled_appointment_frees_the_slot; completed/no-show uncovered | api |
| R-19 | Different slot sizes (doctor changes slot length) still cannot overlap | §4.3 Precision | `appt:152-159` (range overlap) | t_doc::test_overlapping_slot_sizes_block_each_other | api |

## Holds, confirm, cancel (PRD §4.3, §12.2)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-20 | Holding a free slot creates `awaiting_payment` with `hold_expires_at = now + 15 min` (per doctor) | §4.3 Statuses, §12.2.1 | `appt:164-173`, `models.py:247` | t_appt::test_hold_creates_a_timed_reservation | api |
| R-21 | Unknown doctor → 404 | — (robustness) | `appt:136-137` | t_appt::test_hold_unknown_doctor | api |
| R-22 | Two patients on the same slot: second is refused (sequential) | §4.3 AC 1 | `appt:152-162` | t_appt::test_second_patient_cannot_take_the_same_slot | api |
| R-23 | Simultaneous holds on one slot: exactly one 201 (real DB) | §4.3 AC 1, "slot is locked" | `appt:133-135` (row lock), `models.py:517-523` EXCLUDE gist, `backend/alembic/versions/0002_appointments.py:95-97`, `appt:176-181` | t_race::test_one_of_many_simultaneous_holds_wins (skipped: no PostgreSQL / Docker this run) | race |
| R-24 | DB constraint prevents overlapping active appointments per doctor | §4.3 Precision | `models.py:517-523` (PostgreSQL only; SQLite has none) | partial — only via t_race (skipped) | race |
| R-25 | One open hold per patient: a new hold releases the old one; a failed new hold keeps the old one | §12.2.1 | `appt:145-151`, rollback `appt:160-162` | t_appt::test_new_hold_replaces_the_patients_old_one, test_failed_hold_keeps_the_patients_old_one; parallel replace uncovered | api |
| R-26 | An unpaid hold is released after the timeout; the slot is free for others | §4.3 Statuses, §4.4 AC 2 | `appt:92-100`, `appt:144`, `sched:188` | t_appt::test_expired_hold_frees_the_slot; t_doc::test_active_hold_blocks_but_expired_hold_does_not | api |
| R-27 | Patient can give a hold back; only their own and only while it is a hold | §12.2 (implied) | `appt:185-197` | t_appt::test_release_hold_frees_the_slot, test_release_refuses_other_patients_and_confirmed | api |
| R-28 | App may confirm only "pay at the clinic"; card methods refused from the app | §4.3 Pilot payment, §4.4 AC 1 | `appt:212-213` | t_appt::test_card_payment_cannot_be_confirmed_from_the_app | payments |
| R-29 | Confirming an expired hold fails (`hold_expired`) and frees the slot | §4.3 Statuses | `appt:216-219` | t_appt::test_confirm_after_the_hold_ran_out | api |
| R-30 | Confirm twice / someone else's appointment refused | §4.3 | `appt:211`, `appt:214-215` | t_appt::test_confirm_someone_elses_or_twice | api |
| R-31 | Patient's list shows only their own, oldest first, hides expired holds | §4.3 History, §3 | `appt:229-245` | t_appt::test_list_shows_only_my_appointments_oldest_first, test_list_hides_open_holds_that_ran_out | security |
| R-32 | Cancel allowed only for `confirmed`, only outside the notice (exactly at notice allowed) | §4.3 Precision | `appt:282-287` | t_appt::test_cancel_outside_the_notice, test_cancel_inside_the_notice_is_refused, test_cancel_refuses_other_patients_and_non_confirmed; exact boundary and cancel twice uncovered | api |
| R-33 | Cancel frees the slot and hides the check-in code | §4.3 | `appt:288-289`, `appt:73`, `sched:185-189` | t_doc::test_cancelled_appointment_frees_the_slot; t_chk::test_a_cancelled_appointment_no_longer_shows_its_code | api |
| R-34 | First doctor the patient books becomes their primary doctor | §4.3 Booking, §3 | not found — no primary-doctor field in `models.py`; `recovery.py:182-190` uses the doctor *last* booked | uncovered | api |
| R-35 | Follow-up suggested ~30 days after the latest visit, own visits only | §4.3 Follow-up | `appt:248-270` (counts `confirmed` too, i.e. a future visit) | t_appt::test_follow_up_is_empty_without_a_visit, test_follow_up_is_30_days_after_the_latest_visit, test_follow_up_ignores_other_patients; m_book Follow-up group | api |
| R-36 | Follow-up costs the same as any appointment | §4.3 Follow-up | `appt:171` (price copied from doctor profile at hold) | uncovered | api |
| R-37 | Doctor can book for a patient | §4.3 Booking | not found — no staff booking route | uncovered | api |
| R-38 | Doctor sets availability (weekly schedule, holidays, slot length) | §4.3, §7 Availability | not found — only `backend/app/seed.py:50` writes `Availability` | uncovered | api |
| R-39 | Doctor marks completed / no-show only after start, only own visit, only from confirmed/completed/no-show | §12.2.4 | `staff:232-249` | t_staff::test_mark_completed_or_no_show_after_start, test_cannot_mark_a_future_or_someone_elses_visit; cancelled→completed uncovered | api |
| R-40 | Hold/confirm/cancel/check-in are audited with no medical content and no plain ID number | CLAUDE.md, §4.2 | `appt:175`, `appt:224`, `appt:290`, `staff:227`, `staff:216` (code not logged) | t_appt::test_hold_is_audited_without_medical_content (hold only); confirm/cancel/check-in uncovered | security |

## Payments (PRD §4.4)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-41 | Checkout only for CIB / Edahabia, only own live hold | §4.4 Methods, Flow | `pay:51-59` | t_pay::test_checkout_opens_a_chargily_payment, test_checkout_refuses_clinic_and_bad_states | payments |
| R-42 | Checkout amount = doctor price in DZD | §4.4 Price | `pay:61`, `backend/app/chargily.py:165-166` | t_pay::test_checkout_opens_a_chargily_payment | payments |
| R-43 | Chargily down / no key → clear error, nothing confirmed | §4.4 | `chargily.py:157-180` | t_pay::test_checkout_when_chargily_is_down, test_checkout_without_a_key_is_unavailable | payments |
| R-44 | Card appointment confirmed only by a correctly signed webhook (bad, missing, other-key signature refused) | §4.4 AC 1, §4.3 Pilot | `pay:91-92`, `chargily.py:184-191` | t_pay::test_paid_webhook_confirms_the_appointment, test_bad_or_missing_signature_is_refused; signature over a different body uncovered | payments |
| R-45 | Same webhook twice → one payment, one confirmation | §4.4 AC 3 | `pay:100-103`, `models.py:350` unique `chargily_id` | t_pay::test_same_webhook_twice_records_one_payment | payments |
| R-46 | Failed / cancelled / expired payment releases the slot for another patient | §4.4 AC 2 | `pay:121-125` | t_pay::test_failed_payment_releases_the_slot (`checkout.failed` only; `canceled`/`expired` uncovered) | payments |
| R-47 | Paid webhook for a hold that has already expired must not confirm it (the hold was released) | §4.3 Statuses, §4.4 AC 2 | partial — `pay:110` checks status only, not `hold_expires_at`; an expired hold not yet purged gets confirmed | partial — t_pay::test_payment_after_the_slot_was_lost_is_flagged_for_refund covers only the case where the slot was purged and retaken | payments |
| R-48 | Paid webhook after the slot was lost → payment kept, flagged for refund, no confirmation | §4.4 | `pay:117-120` | t_pay::test_payment_after_the_slot_was_lost_is_flagged_for_refund | payments |
| R-49 | Unknown checkout id / unknown event type acknowledged, changes nothing; malformed body 400 | §4.4 | `pay:93-103`, `pay:126-127` | t_pay::test_unknown_checkout_and_event_are_acknowledged | payments |
| R-50 | Webhook for a cancelled appointment does not revive it | §4.3 Statuses | `pay:110` (status must be `awaiting_payment`) | uncovered | payments |
| R-51 | App never sees or stores card numbers; only Chargily id and status kept | §4.4 Security | `models.py:333-353` (no card columns) | uncovered (model inspection) | payments |
| R-52 | Payment return page reveals nothing sensitive, in AR + FR | §4.4, §8.6 | `pay:133-144` | t_pay::test_return_page_in_both_languages | payments |
| R-53 | Pay-at-clinic: doctor marks paid / unpaid; card payments set only by Chargily | §4.3 Pilot, §4.4 Receipts | `staff:252-270` | t_staff::test_mark_clinic_payment_paid_and_unpaid, test_card_payments_are_set_only_by_chargily | payments |
| R-54 | Patient and doctors are notified when the appointment is confirmed; reminders 24 h and 1 h before (generic text, no medical content) | §4.4 Flow, §4.3 Reminders, §12.2.3 | not found — no notification or reminder job (`backend/app/jobs.py` has none) | uncovered | api |
| R-55 | Patient sees a receipt in the app | §4.4 Receipts | not found | uncovered | ux |

## Check-in (PRD §4.3, §7)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-56 | Each confirmed appointment (clinic or card) gets a 6-char code without look-alike letters, unique | §4.3 Booking code | `backend/app/checkin.py:250-272`, `models.py:292`; issued `appt:223`, `pay:115` | t_chk::test_clinic_booking_gets_a_code_the_patient_can_read, test_card_payment_gets_a_code_from_the_webhook, test_codes_are_unique_and_easy_to_read | payments |
| R-57 | Code shown to the patient only while confirmed | §4.3 | `appt:73` | t_chk::test_a_cancelled_appointment_no_longer_shows_its_code | payments |
| R-58 | Valid code marks the patient arrived; typed loosely is accepted | §4.3 | `staff:204`, `staff:220-228` | t_chk::test_checking_in_marks_the_patient_as_arrived, test_the_code_may_be_typed_loosely | payments |
| R-59 | Code works only for the doctor's own confirmed appointment on the clinic day | §4.3 | `staff:205-209`, `staff:221-225` | t_chk::test_another_doctors_code_looks_like_an_unknown_code, test_a_code_works_only_on_the_day_of_the_visit, test_the_day_is_the_clinic_day_not_the_utc_day, test_only_a_confirmed_appointment_can_check_in | payments |
| R-60 | Repeat check-in changes nothing | §4.3 | `staff:220` | t_chk::test_checking_in_twice_changes_nothing | payments |
| R-61 | 10 wrong codes in 10 minutes lock the box for that account for a while; lock is per account | §4.3 | `staff:189-202`, `config.py:57-58` | t_chk::test_too_many_wrong_codes_make_the_account_wait, test_the_wait_ends_and_other_doctors_are_not_affected, test_valid_but_unusable_codes_do_not_count_as_guesses | payments |
| R-62 | A secretary (clinic staff) can also run check-in at the front desk | §4.3 Booking code, §3 | not found — `staff:88-94` `current_doctor` accepts only `Role.doctor`; no clinic-staff role in `models.py:32-35` | uncovered | security |
| R-63 | Dashboard Today: success shows **arrived** + reminder to check the original ID card; error messages for invalid / not today / not checkable / too many | §4.3, §7 | `apps/dashboard/src/components/CheckinBox.tsx:8-11` | d_dash Check-in: arrived + ID reminder, empty code, Arabic; wrong-code and lockout messages uncovered | ux |

## Roles and access (PRD §3, §7)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-64 | Patient A cannot see or act on patient B's appointment; the reply equals a random id's (404 `appointment_not_found`) | §3, §4.3 AC 3 | `appt:83-89`, `pay:53-55` | t_appt::test_release_refuses_other_patients_and_confirmed, test_confirm_someone_elses_or_twice, test_cancel_refuses_other_patients_and_non_confirmed; body equality vs random UUID and checkout uncovered | security |
| R-65 | Doctors see every doctor's appointments and agenda in the clinic | §3 (updated), multi-doctor rules | not found — `staff:166` filters agenda to the caller's own appointments | t_staff::test_agenda_shows_only_my_booked_visits_of_the_day asserts the opposite (old rule) | security |
| R-66 | Appointment / agenda responses carry no clinical fields (notes, meds, addictions, AI flags) | §3 | `staff:40-51` `AgendaItem` (phone, times, status, payment only) | uncovered | security |
| R-67 | A doctor sees clinical data only for own patients (plus shared / transferred); another doctor's patient is refused | §3 | partial — `backend/app/routers/medications.py:110-124` grants access to any doctor the patient has *booked with*, not primary/shared; with clinic-wide booking this needs checking | uncovered | security |
| R-68 | Patient token on staff routes refused; doctor token on patient routes refused; no / garbage / expired token 401 | §3 | `deps.py:16-38`, `staff:88-94` | t_staff::test_patient_cannot_use_staff_login_or_routes, test_doctor_cannot_use_patient_routes, test_agenda_needs_a_login; t_chk::test_check_in_needs_a_doctor; expired token uncovered | security |
| R-69 | Clinic staff (not doctors) approve or reject ID declarations | §3, §4.2 Approval, §7 | not found — `staff:352-398` approve/reject use `current_doctor` | t_staff::test_signups_list_and_approve, test_reject_signup (test doctors doing it) | security |
| R-70 | Super admin also holds the Doctor role (can use doctor booking screens) | §3 | not found — `staff:89` requires `Role.doctor`; `Role.super_admin` is separate (`models.py:33`) | uncovered | security |

## Localisation (PRD §8.6)

| ID | Rule (short) | PRD | Enforced at | Covered by | Area |
|----|--------------|-----|-------------|------------|------|
| R-71 | Every booking screen in Arabic (RTL) and French | §8.6, CLAUDE.md | mobile l10n `.arb`; dashboard `i18n.tsx` | m_book French tests for doctor screen and follow-up; d_dash "is in Arabic and right-to-left by default", check-in Arabic; confirm/done/my-appointments in AR+FR partial | ux |
| R-72 | Every booking error code maps to a human message (no raw code) | §8.6 | `apps/mobile/lib/features/booking/api_booking_repository.dart:132-141` (`not_verified`, `payment_method_unavailable`, `payments_unavailable`, `not_cancellable` fall back to a generic "unavailable") | m_api "a taken slot is SlotUnavailable", "an expired hold on confirm is SlotUnavailable", "cancels, and a refusal inside the notice is TooLateToCancel"; others uncovered | ux |
| R-73 | Large tap targets, readable fonts | §8.6 | not checked in code | uncovered | ux |

## Summary

- Rules: **73**
- Uncovered (no test): **16** — R-05, R-06, R-16, R-34, R-36, R-37, R-38, R-50, R-51, R-54, R-55, R-62, R-66, R-67, R-70, R-73.
- Tested, but the test asserts the opposite of the PRD: **3** — R-08 (profile skip), R-65 (agenda own-only), R-69 (doctors approve IDs). So 19 rules have no test of the PRD behaviour.
- Partial coverage (an edge named in the row is untested): **21** — R-02, R-07, R-09, R-10, R-13, R-14, R-15, R-18, R-24, R-25, R-32, R-39, R-40, R-44, R-46, R-47, R-63, R-64, R-68, R-71, R-72.
- Not found in code: **11** — R-05, R-06, R-34, R-37, R-38, R-54, R-55, R-62, R-65, R-69, R-70. Partial enforcement: R-08, R-47, R-67.
- Postgres-only rules (R-23, R-24) cannot run this time (no Docker).

## PRD gaps (open questions for testers)

1. **Hold timeout**: 15 min is "e.g. … to confirm" in §4.3 but fixed in §12.2. Code uses per-doctor `hold_minutes` (default 15). Which is binding?
2. **"Up to 60 days ahead"**: inclusive of today+60 or not? Code allows clinic days today … today+59.
3. **Notice boundary**: is a slot exactly 24 h away bookable / cancellable? Code says yes for both.
4. **Webhook amount / currency check**: PRD is silent; code does not compare the paid amount or currency with the appointment price.
5. **Paid webhook on an expired hold** (not yet purged): confirm, or release and refund? PRD says unpaid holds are released, but does not say what a late payment does to a still-free slot.
6. **Several checkouts for one appointment**: allowed? Code allows them; a second payment is flagged for refund.
7. **Refunds and cancellation of a paid card appointment**: deadline, refund or credit, no-show rules are "to decide with the clinic" (§4.4, §11).
8. **Clinic staff / secretary role**: not modelled. Which doctors does a secretary serve for check-in (§4.3 says "the doctor's own" appointments)? Can a secretary see the clinic-wide agenda?
9. **Clinic-wide agenda vs check-in**: with doctors now seeing every agenda, may doctor A check in doctor B's patient? §4.3 still says "only for the doctor's own confirmed appointments".
10. **Shared / transferred patients**: how is sharing recorded? No field exists. Primary doctor is not stored at all; recovery alerts go to the last-booked doctor, medications to any booked doctor.
11. **Statuses `requested` and `rescheduled`** (§4.3) do not exist in code (`awaiting_payment`, `confirmed`, `completed`, `cancelled`, `no_show` only). Is rescheduling in scope, and does "requested" mean a doctor-side request (§7 "pending booking requests")?
12. **Follow-up trigger**: "after a visit" — code also suggests from a future confirmed appointment. Intended?
13. **Doctor booking for a patient** (§4.3): payment path, notice and horizon rules for a doctor-made booking are not specified.
14. **Can a patient hold slots with two doctors / overlapping times with different doctors?** PRD silent (open question in §11 about more than one doctor).
15. **Check-in lock length** ("for a while"): code unlocks when the oldest failure leaves the 10-minute window.
16. **Profile skip**: §4.1/§4.2 say no Skip, but the mobile booking gate and tests still describe a "skipped" profile path.
