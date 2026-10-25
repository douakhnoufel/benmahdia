# Payments — QA 2026-10-25

Specialist: payments (prefix `PAY`). Test file: `backend/tests/test_qa_booking_payments.py`.
Real Chargily never called: `FakeChargily` + `test_sk_unit_tests_only` from `test_payments.py`, and an `httpx.MockTransport` stub for the one wire-format test.

## Result

```
cd backend && .venv/Scripts/python.exe -m pytest tests/test_qa_booking_payments.py -p no:warnings
49 passed, 1 xfailed in 63.13s
```
Together with the existing `test_payments.py` + `test_checkin.py`: 81 passed, 1 xfailed.

## Rules covered (Area = payments)

| Rule | Tests added |
|------|-------------|
| R-28 | test_app_cannot_confirm_a_card_payment_with_any_body (5 bodies), test_return_page_and_patient_tokens_on_staff_routes_confirm_nothing, test_doctor_cannot_confirm_a_hold_or_mark_it_paid, test_pay_at_the_clinic_path |
| R-41 | test_checkout_on_someone_elses_hold_looks_like_a_random_id, test_checkout_refuses_a_confirmed_or_cancelled_appointment |
| R-42 | test_checkout_sends_only_the_amount_and_the_appointment_id, test_real_client_asks_chargily_for_dzd |
| R-43 | already covered (t_pay); not re-tested |
| R-44 | test_signature_over_a_different_body_is_refused, test_signature_in_upper_case_or_padded_is_refused, test_webhook_is_refused_when_no_secret_is_configured |
| R-45 | test_same_paid_webhook_twice_confirms_once, test_failed_after_paid_on_the_same_checkout_is_ignored, test_two_checkouts_both_paid_confirm_once_and_flag_the_second |
| R-46 | test_every_failure_kind_releases_the_slot_for_another_patient (failed / canceled / expired), test_abandoned_checkout_frees_the_slot_after_the_hold_timeout, test_failed_webhook_after_the_slot_was_retaken_leaves_the_new_hold |
| R-47 | test_paid_webhook_after_the_hold_expired_does_not_confirm (**xfail PAY-01**), test_late_payment_outcome_depends_on_unrelated_cleanup, test_expired_hold_shows_free_while_a_late_payment_can_still_confirm_it |
| R-48 | test_paid_webhook_for_a_clinic_confirmed_appointment_is_flagged, test_first_checkout_failing_drops_the_hold_while_a_retry_is_open |
| R-49 | test_signed_but_malformed_events_are_400_and_change_nothing (5 bodies), test_unknown_event_type_on_a_known_checkout_changes_nothing (3 kinds), test_unknown_checkout_id_changes_nothing |
| R-50 | test_paid_webhook_for_a_cancelled_appointment_does_not_revive_it, test_failed_webhook_never_deletes_a_confirmed_appointment |
| R-51 | test_no_table_has_a_card_column, test_webhook_card_details_are_not_stored |
| R-52 | test_return_page_reveals_nothing_and_reflects_nothing (success / failure / script injection) |
| R-53 | test_doctor_cannot_confirm_a_hold_or_mark_it_paid (card side; clinic side already in t_staff) |
| R-56 | test_code_alphabet_has_no_look_alikes_and_codes_are_six_chars, test_card_confirmed_appointment_checks_in_on_the_day |
| R-57 | test_paid_webhook_for_a_cancelled_appointment_does_not_revive_it (code hidden after cancel) |
| R-58 | test_card_confirmed_appointment_checks_in_on_the_day (lower-case code accepted) |
| R-59 | test_cancelled_card_appointment_cannot_check_in (rest already well covered in t_chk) |
| R-60 | already covered (t_chk::test_checking_in_twice_changes_nothing) |
| R-61 | test_nine_wrong_codes_still_let_the_right_one_through (boundary), test_failed_check_in_is_audited_without_the_code |

## Findings

### PAY-01: Paid webhook confirms a hold that has already expired, depending on whether some unrelated hold purged it first
- Severity: medium
- Rule: R-47 (PRD §4.3 Statuses "an unpaid hold is released after a short timeout", §4.4 AC 2 "a failed or abandoned payment releases the slot")
- Where: backend/app/routers/payments.py:110 (checks `a.status == awaiting_payment` only, never `hold_expires_at`)
- Repro: `test_qa_booking_payments.py::test_paid_webhook_after_the_hold_expired_does_not_confirm` (strict xfail). Evidence: `test_late_payment_outcome_depends_on_unrelated_cleanup`, `test_expired_hold_shows_free_while_a_late_payment_can_still_confirm_it`.
- Expected (PRD): once the hold's timeout passes it is released; a payment arriving after that does not turn the released hold into an appointment (the code's own rule elsewhere: `/confirm` and `/checkout` both answer `hold_expired`, and the calendar shows the slot as free — `scheduling.py:188`).
- Actual: if no one has made any hold since the expiry (expired rows are only purged inside `POST /holds`, for every doctor), the late `checkout.paid` confirms the appointment. If any patient held any slot in between, the same payment is instead flagged `payment.needs_refund` and the slot is lost. Same input, two outcomes, decided by unrelated traffic. During the gap the calendar offers the slot to everyone. No double booking results on SQLite (the competing hold purges the expired row first), so not critical.
- Note for verifier: what a late payment *should* do (refund vs. confirm if the slot is still free) is PRD gap 5 in rules.md. The bug is the inconsistency with the PRD's "released after timeout" and with the code's own confirm/checkout/calendar behaviour; if the clinic decides "confirm if still free", the fix is to say so and purge-or-confirm deterministically. Aggravated by Q7 (hold is not extended when the checkout opens).

## Questions (PRD silent — not bugs)

- **PAY-Q1 — Webhook amount / currency not compared.** A signed `checkout.paid` with `amount: 1, currency: "eur"` confirms a 2000 DZD appointment (`test_paid_event_amount_and_currency_are_not_compared`, passes, documents behaviour). Signature makes forgery impossible, so risk is only a Chargily-side anomaly. Should the backend check amount and currency against `payments.amount_dzd`? (rules.md gap 4)
- **PAY-Q2 — Several checkouts for one hold.** Allowed; if two are paid, one confirms and the other is kept `paid` + `payment.needs_refund` (`test_two_checkouts_both_paid_confirm_once_and_flag_the_second`). Should a second checkout be refused or should it cancel the first? (gap 6)
- **PAY-Q3 — Retry after a declined card loses the slot.** Patient opens checkout 1, card declined, opens checkout 2; Chargily's `checkout.failed` for 1 deletes the hold (`payments.py:121-125`), so checkout 2's payment is refunded and the slot is gone (`test_first_checkout_failing_drops_the_hold_while_a_retry_is_open`). Literal PRD §4.4 AC 2 is satisfied; is that the intended UX, or should a failure release the slot only when no other checkout for the hold is still pending?
- **PAY-Q4 — "Pay at the clinic" still open while Chargily is wired.** PRD §4.3: "*until* Chargily is wired, the app confirms only pay-at-the-clinic". `/confirm` with `method=clinic` works regardless of whether `CHARGILY_SECRET_KEY` is set (`appointments.py:212`), so once card payment is live a patient can still book unpaid. Should clinic confirmation switch off (or become doctor-only) when Chargily is configured?
- **PAY-Q5 — Cancelling a card-paid appointment.** `/cancel` sets `cancelled` with no refund flag or audit `payment.needs_refund` (`appointments.py:282-291`). PRD §4.4 leaves refunds "to decide with the clinic"; should a paid cancellation at least be flagged for the clinic?
- **PAY-Q6 — Front-desk scope.** Check-in still accepts only the logged-in doctor's own appointments (`staff.py:205-209`), matching §4.3, but §3 now makes agendas clinic-wide and §4.3 mentions a secretary at the desk (no such role exists). May doctor A (or a secretary) check in doctor B's patient? (gaps 8, 9)
- **PAY-Q7 — Hold not extended when checkout opens.** The hold keeps its 15-minute life from the moment of holding (`payments.py:41-78` does not touch `hold_expires_at`); time spent on Chargily's page counts against it, which makes PAY-01 a realistic path. Should opening a checkout extend the hold to Chargily's checkout lifetime?

## Checked and fine (no finding)

- Signature: other key, missing, empty, upper-case hex, signature over a different body, one extra byte, no secret configured → all 403; nothing changes.
- Malformed signed bodies → 400 `bad_event`; unknown event types / unknown checkout ids → 200, nothing changes.
- Same webhook twice → one `appointment.confirmed`, one `payment.paid`, same check-in code and `paid_at`. `failed` after `paid` on the same checkout ignored.
- Cancelled appointment is not revived by a later paid webhook; a confirmed appointment is never deleted by a later failed/canceled/expired webhook; a late failure never deletes another patient's new hold.
- The app cannot confirm a card method with any body (cib, edahabia, extra fields, unknown method, empty); the return page, staff routes with a patient token, and unsigned webhook calls confirm nothing; doctors cannot set `confirmed` or mark a card appointment paid.
- Checkout on another patient's hold answers exactly like a random UUID (same status and body). Chargily receives only amount, method, locale, our appointment id and `BenMahdia <id>` — no phone or name; currency on the wire is `dzd`; unknown locale falls back to `ar`.
- Return page: AR (RTL) + FR, no ids, phone, price or reflected input.
- No card-like column in any table; card hints inside a webhook body are not persisted anywhere.
- Check-in: alphabet has no 0/O/1/I/L, 6 chars; a code issued by the card webhook works on the day (typed lower-case); 9 wrong codes do not lock, the 10th does (existing test); failed attempts are audited without the code; cancelled card appointment → `not_checkable`.
