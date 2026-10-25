"""QA 2026-10-25 — payments specialist (prefix PAY).

Chargily checkout and webhook, the app-side confirm rule, slot release after a
failed or abandoned payment, the return page, front-desk check-in codes and
"no card data stored". The real Chargily is never called: FakeChargily and the
test secret from test_payments are reused. Rules: qa/booking/2026-10-25/rules.md
(Area = payments: R-28, R-41..R-53, R-56..R-61).
"""

import json
import re
import uuid
from datetime import datetime, timedelta

import pytest
from sqlalchemy.orm import Session

from app import checkin
from app.chargily import Chargily, get_chargily
from app.clock import clock
from app.config import get_settings
from app.db import Base, engine
from app.main import app
from app.models import (
    Appointment,
    AppointmentStatus,
    AuditLog,
    Payment,
    PaymentMethod,
    PaymentStatus,
)

from .booking_helpers import add_appointment, expire_holds, headers, make_doctor, user_id, verified_patient
from .conftest import bearer
from .test_appointments import NEXT, SLOT, confirm, hold
from .test_payments import (  # noqa: F401  (chargily is a fixture)
    SECRET,
    appointment,
    chargily,
    checkout,
    event,
    held,
    payment,
    send,
    sign,
)
from .test_staff import doc_headers, doctor_with_password

PHONE_A = "0661234501"
PHONE_B = "0661234502"
PHONE_C = "0661234503"
# Clock: Saturday 2026-10-17 19:00 Algiers (18:00 UTC).
TODAY_EVENING = datetime(2026, 10, 17, 20, 0)   # 21:00 Algiers, same clinic day


def audit_count(action: str) -> int:
    with Session(engine) as db:
        return db.query(AuditLog).filter(AuditLog.action == action).count()


def err(r) -> str:
    return r.json()["detail"]["code"]


def body_with(kind: str, checkout_id: str, **data) -> bytes:
    """A Chargily v2-shaped event with extra fields inside `data`."""
    return json.dumps({"id": "evt_qa", "entity": "event", "type": kind,
                       "data": {"id": checkout_id, "entity": "checkout",
                                "status": kind.split(".")[1], **data}}).encode()


def paid_card_appointment(client, sms, chargily, phone=PHONE_A):
    doctor = make_doctor()
    s = verified_patient(client, sms, phone)
    h = held(client, s, doctor)
    assert checkout(client, s, h["id"]).status_code == 201
    return doctor, s, h


# --- webhook: signature ---------------------------------------------------------------


def test_signature_over_a_different_body_is_refused(client, sms, chargily):
    """R-44: a valid signature for one event cannot be replayed on another."""
    _, _, h = paid_card_appointment(client, sms, chargily)
    failed = event("checkout.failed", "chk_1")
    paid = event("checkout.paid", "chk_1")
    assert send(client, paid, sign(failed)).status_code == 403
    # The same event with one byte changed (whitespace) no longer matches.
    assert send(client, paid + b" ", sign(paid)).status_code == 403
    assert appointment(h["id"]).status == AppointmentStatus.awaiting_payment
    assert payment("chk_1").status == PaymentStatus.pending


def test_signature_in_upper_case_or_padded_is_refused(client, sms, chargily):
    _, _, h = paid_card_appointment(client, sms, chargily)
    paid = event("checkout.paid", "chk_1")
    assert send(client, paid, sign(paid).upper()).status_code == 403
    assert send(client, paid, "").status_code == 403
    assert appointment(h["id"]).status == AppointmentStatus.awaiting_payment


def test_webhook_is_refused_when_no_secret_is_configured(client):
    """Without CHARGILY_SECRET_KEY nothing can be signed correctly, not even
    with an empty key."""
    app.dependency_overrides.pop(get_chargily, None)
    body = event("checkout.paid", "chk_1")
    assert send(client, body, sign(body, "")).status_code == 403
    assert send(client, body, sign(body, SECRET)).status_code == 403


@pytest.mark.parametrize("raw", [
    b"[]",
    b'{"type": "checkout.paid"}',
    b'{"type": "checkout.paid", "data": "chk_1"}',
    b'{"type": "checkout.paid", "data": {}}',
    b'{"data": {"id": "chk_1"}}',
])
def test_signed_but_malformed_events_are_400_and_change_nothing(client, sms, chargily, raw):
    _, _, h = paid_card_appointment(client, sms, chargily)
    r = send(client, raw)
    assert (r.status_code, err(r)) == (400, "bad_event")
    assert appointment(h["id"]).status == AppointmentStatus.awaiting_payment


@pytest.mark.parametrize("kind", ["checkout.pending", "checkout.refunded", "something.else"])
def test_unknown_event_type_on_a_known_checkout_changes_nothing(client, sms, chargily, kind):
    """R-49."""
    _, _, h = paid_card_appointment(client, sms, chargily)
    assert send(client, event(kind, "chk_1")).status_code == 200
    assert payment("chk_1").status == PaymentStatus.pending
    assert appointment(h["id"]).status == AppointmentStatus.awaiting_payment


def test_unknown_checkout_id_changes_nothing(client, sms, chargily):
    _, _, h = paid_card_appointment(client, sms, chargily)
    assert send(client, event("checkout.paid", "chk_not_ours")).status_code == 200
    assert send(client, event("checkout.failed", "chk_not_ours")).status_code == 200
    assert appointment(h["id"]).status == AppointmentStatus.awaiting_payment
    with Session(engine) as db:
        assert db.query(Payment).count() == 1


def test_paid_event_amount_and_currency_are_not_compared(client, sms, chargily):
    """QUESTION PAY-Q1: the PRD is silent. Today a signed `checkout.paid`
    carrying 1 EUR still confirms a 2000 DZD appointment. Documents current
    behaviour only (passes)."""
    _, _, h = paid_card_appointment(client, sms, chargily)
    body = body_with("checkout.paid", "chk_1", amount=1, currency="eur")
    assert send(client, body).status_code == 200
    assert appointment(h["id"]).status == AppointmentStatus.confirmed


# --- webhook: expired holds (R-47) ------------------------------------------------


@pytest.mark.xfail(strict=True, reason="QA PAY-01: paid webhook confirms a hold that already expired (payments.py:110 ignores hold_expires_at)")
def test_paid_webhook_after_the_hold_expired_does_not_confirm(client, sms, chargily):
    """R-47. The hold ran out (the calendar already shows the slot as free and
    /confirm and /checkout both answer hold_expired), but nobody has purged
    the row yet. The late payment must not turn it into an appointment; it
    should be flagged for refund like any payment that lost its slot."""
    _, _, h = paid_card_appointment(client, sms, chargily)
    expire_holds()
    assert send(client, event("checkout.paid", "chk_1")).status_code == 200
    a = appointment(h["id"])
    assert a is None or a.status != AppointmentStatus.confirmed
    assert audit_count("payment.needs_refund") == 1


def test_late_payment_outcome_depends_on_unrelated_cleanup(client, sms, chargily):
    """Evidence for PAY-01: the same late payment is refunded instead of
    confirmed as soon as *any* patient makes *any* hold (here: another slot),
    because every hold purges every expired hold."""
    doctor, _, h = paid_card_appointment(client, sms, chargily)
    expire_holds()
    other = verified_patient(client, sms, PHONE_C)
    assert hold(client, other, doctor, NEXT).status_code == 201   # a different slot
    assert send(client, event("checkout.paid", "chk_1")).status_code == 200
    assert appointment(h["id"]) is None
    assert payment("chk_1").status == PaymentStatus.paid
    assert audit_count("payment.needs_refund") == 1


def test_expired_hold_shows_free_while_a_late_payment_can_still_confirm_it(client, sms, chargily):
    """Evidence for PAY-01: between expiry and the webhook, the calendar
    offers the slot to everybody, yet the paid webhook confirms it."""
    doctor, _, h = paid_card_appointment(client, sms, chargily)
    expire_holds()
    other = verified_patient(client, sms, PHONE_B)
    cal = client.get(f"/v1/doctors/{doctor.user_id}/calendar", headers=headers(other))
    assert cal.status_code == 200, cal.text
    slots = [s for d in cal.json()["days"] for s in d["slots"] if s["start"] == SLOT]
    assert slots and slots[0]["free"] is True
    assert send(client, event("checkout.paid", "chk_1")).status_code == 200
    assert appointment(h["id"]).status == AppointmentStatus.confirmed


def test_failed_webhook_after_the_slot_was_retaken_leaves_the_new_hold(client, sms, chargily):
    """A late `checkout.failed` for patient A must never delete patient B's hold."""
    doctor, _, h = paid_card_appointment(client, sms, chargily)
    expire_holds()
    b = verified_patient(client, sms, PHONE_B)
    taken = held(client, b, doctor)
    assert send(client, event("checkout.failed", "chk_1")).status_code == 200
    assert appointment(taken["id"]).status == AppointmentStatus.awaiting_payment
    assert payment("chk_1").status == PaymentStatus.failed


# --- webhook: cancelled / confirmed appointments (R-50) ------------------------------


def test_paid_webhook_for_a_cancelled_appointment_does_not_revive_it(client, sms, chargily):
    _, s, h = paid_card_appointment(client, sms, chargily)
    assert checkout(client, s, h["id"]).status_code == 201          # chk_2, left open
    assert send(client, event("checkout.paid", "chk_1")).status_code == 200
    r = client.post(f"/v1/appointments/{h['id']}/cancel", headers=headers(s))
    assert r.status_code == 200, r.text
    assert send(client, event("checkout.paid", "chk_2")).status_code == 200
    a = appointment(h["id"])
    assert a.status == AppointmentStatus.cancelled
    assert payment("chk_2").status == PaymentStatus.paid
    assert audit_count("payment.needs_refund") == 1
    [mine] = client.get("/v1/appointments", headers=headers(s)).json()
    assert (mine["status"], mine["checkin_code"]) == ("cancelled", None)


def test_failed_webhook_never_deletes_a_confirmed_appointment(client, sms, chargily):
    _, s, h = paid_card_appointment(client, sms, chargily)
    assert checkout(client, s, h["id"]).status_code == 201          # chk_2
    assert send(client, event("checkout.paid", "chk_1")).status_code == 200
    code = appointment(h["id"]).checkin_code
    for kind in ("checkout.failed", "checkout.canceled", "checkout.expired"):
        assert send(client, event(kind, "chk_2")).status_code == 200
    a = appointment(h["id"])
    assert (a.status, a.checkin_code) == (AppointmentStatus.confirmed, code)


def test_paid_webhook_for_a_clinic_confirmed_appointment_is_flagged(client, sms, chargily):
    """The patient opened a card checkout, then confirmed "pay at the clinic";
    the card payment that arrives later is kept and flagged, not applied."""
    _, s, h = paid_card_appointment(client, sms, chargily)
    assert confirm(client, s, h["id"]).status_code == 200
    assert send(client, event("checkout.paid", "chk_1")).status_code == 200
    a = appointment(h["id"])
    assert (a.status, a.method, a.paid_at) == (AppointmentStatus.confirmed, PaymentMethod.clinic, None)
    assert audit_count("payment.needs_refund") == 1


# --- idempotency (R-45) ---------------------------------------------------------------


def test_same_paid_webhook_twice_confirms_once(client, sms, chargily):
    _, _, h = paid_card_appointment(client, sms, chargily)
    body = event("checkout.paid", "chk_1")
    assert send(client, body).status_code == 200
    first = appointment(h["id"])
    assert send(client, body).status_code == 200
    again = appointment(h["id"])
    assert (again.checkin_code, again.paid_at) == (first.checkin_code, first.paid_at)
    assert audit_count("appointment.confirmed") == 1
    assert audit_count("payment.paid") == 1
    assert audit_count("payment.needs_refund") == 0


def test_failed_after_paid_on_the_same_checkout_is_ignored(client, sms, chargily):
    _, _, h = paid_card_appointment(client, sms, chargily)
    assert send(client, event("checkout.paid", "chk_1")).status_code == 200
    assert send(client, event("checkout.failed", "chk_1")).status_code == 200
    assert payment("chk_1").status == PaymentStatus.paid
    assert appointment(h["id"]).status == AppointmentStatus.confirmed


def test_two_checkouts_both_paid_confirm_once_and_flag_the_second(client, sms, chargily):
    """QUESTION PAY-Q2 (PRD gap 6): a second checkout for the same hold is
    allowed. When both are paid, one confirms, the other is kept as paid and
    flagged for refund."""
    _, s, h = paid_card_appointment(client, sms, chargily)
    assert checkout(client, s, h["id"]).status_code == 201
    assert send(client, event("checkout.paid", "chk_1")).status_code == 200
    code = appointment(h["id"]).checkin_code
    assert send(client, event("checkout.paid", "chk_2")).status_code == 200
    a = appointment(h["id"])
    assert (a.status, a.checkin_code) == (AppointmentStatus.confirmed, code)
    assert audit_count("appointment.confirmed") == 1
    assert audit_count("payment.needs_refund") == 1
    with Session(engine) as db:
        assert db.query(Payment).filter(Payment.status == PaymentStatus.paid).count() == 2


def test_first_checkout_failing_drops_the_hold_while_a_retry_is_open(client, sms, chargily):
    """QUESTION PAY-Q3: the patient's first card is declined and they retry
    with a second checkout. Chargily's `failed` for the first one deletes the
    hold, so the successful retry is refunded and the slot is lost. Matches
    the literal PRD 4.4 AC ("a failed payment releases the slot"); documents
    current behaviour (passes)."""
    _, s, h = paid_card_appointment(client, sms, chargily)
    assert checkout(client, s, h["id"], "edahabia").status_code == 201   # chk_2
    assert send(client, event("checkout.failed", "chk_1")).status_code == 200
    assert appointment(h["id"]) is None
    assert send(client, event("checkout.paid", "chk_2")).status_code == 200
    assert payment("chk_2").status == PaymentStatus.paid
    assert audit_count("payment.needs_refund") == 1


# --- the app can never confirm a card payment (R-28, R-44) ---------------------------


@pytest.mark.parametrize("payload,status", [
    ({"method": "cib"}, 400),
    ({"method": "edahabia"}, 400),
    ({"method": "cib", "paid": True, "status": "confirmed"}, 400),
    ({"method": "card"}, 422),
    ({}, 422),
])
def test_app_cannot_confirm_a_card_payment_with_any_body(client, sms, chargily, payload, status):
    _, s, h = paid_card_appointment(client, sms, chargily)
    r = client.post(f"/v1/appointments/{h['id']}/confirm", json=payload, headers=headers(s))
    assert r.status_code == status
    a = appointment(h["id"])
    assert (a.status, a.checkin_code) == (AppointmentStatus.awaiting_payment, None)


def test_return_page_and_patient_tokens_on_staff_routes_confirm_nothing(client, sms, chargily):
    _, s, h = paid_card_appointment(client, sms, chargily)
    assert client.get("/v1/payments/return?result=success&checkout_id=chk_1").status_code == 200
    r = client.post(f"/v1/staff/appointments/{h['id']}/paid", json={"paid": True}, headers=headers(s))
    assert r.status_code in (401, 403)
    r = client.post(f"/v1/staff/appointments/{h['id']}/status", json={"status": "completed"},
                    headers=headers(s))
    assert r.status_code in (401, 403)
    # An unsigned call to the webhook from the app is refused too.
    assert send(client, event("checkout.paid", "chk_1"), False).status_code == 403
    a = appointment(h["id"])
    assert (a.status, a.paid_at) == (AppointmentStatus.awaiting_payment, None)
    assert payment("chk_1").status == PaymentStatus.pending


def test_doctor_cannot_confirm_a_hold_or_mark_it_paid(client, sms, chargily):
    doctor_with_password()
    s = verified_patient(client, sms, PHONE_A)
    doctor = make_doctor()
    h = held(client, s, doctor)
    dh = doc_headers(client)
    r = client.post(f"/v1/staff/appointments/{h['id']}/status", json={"status": "confirmed"}, headers=dh)
    assert r.status_code == 422
    r = client.post(f"/v1/staff/appointments/{h['id']}/paid", json={"paid": True}, headers=dh)
    assert r.status_code == 409
    assert appointment(h["id"]).status == AppointmentStatus.awaiting_payment


def test_pay_at_the_clinic_path(client, sms):
    """R-28 pilot rule: "pay at the clinic" is confirmed from the app, stays
    unpaid until the doctor records it, and gets a check-in code."""
    doctor = make_doctor()
    s = verified_patient(client, sms, PHONE_A)
    h = hold(client, s, doctor).json()
    r = confirm(client, s, h["id"])
    assert r.status_code == 200, r.text
    a = appointment(h["id"])
    assert (a.status, a.method, a.paid_at) == (AppointmentStatus.confirmed, PaymentMethod.clinic, None)
    assert a.checkin_code and len(a.checkin_code) == checkin.LENGTH
    with Session(engine) as db:
        assert db.query(Payment).count() == 0       # no fake card payment recorded


# --- checkout (R-41, R-42) ---------------------------------------------------------------


def test_checkout_on_someone_elses_hold_looks_like_a_random_id(client, sms, chargily):
    doctor = make_doctor()
    a = verified_patient(client, sms, PHONE_A)
    b = verified_patient(client, sms, PHONE_B)
    h = held(client, a, doctor)
    theirs = checkout(client, b, h["id"])
    random = checkout(client, b, str(uuid.uuid4()))
    assert (theirs.status_code, theirs.json()) == (random.status_code, random.json())
    assert theirs.status_code == 404
    assert chargily.created == []


def test_checkout_refuses_a_confirmed_or_cancelled_appointment(client, sms, chargily):
    doctor = make_doctor()
    s = verified_patient(client, sms, PHONE_A)
    h = hold(client, s, doctor).json()
    assert confirm(client, s, h["id"]).status_code == 200
    r = checkout(client, s, h["id"])
    assert (r.status_code, err(r)) == (409, "not_a_hold")
    assert client.post(f"/v1/appointments/{h['id']}/cancel", headers=headers(s)).status_code == 200
    r = checkout(client, s, h["id"])
    assert (r.status_code, err(r)) == (409, "not_a_hold")
    assert chargily.created == []


def test_checkout_sends_only_the_amount_and_the_appointment_id(client, sms, chargily):
    """R-42 and privacy: Chargily gets the doctor's DZD price and our id,
    never the patient's phone or name."""
    _, _, h = paid_card_appointment(client, sms, chargily)
    [sent] = chargily.created
    assert sent["amount_dzd"] == 2000
    assert set(sent) == {"amount_dzd", "method", "locale", "appointment_id", "description"}
    assert sent["description"] == f"BenMahdia {h['id']}"
    assert "661234501" not in json.dumps(sent)


def test_real_client_asks_chargily_for_dzd():
    """chargily.py hard-codes the currency; check what goes on the wire with a
    stub transport (no network)."""
    import httpx

    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen.update(json.loads(request.content))
        return httpx.Response(200, json={"id": "chk_x", "checkout_url": "https://pay.test/x"})

    settings = get_settings().model_copy(update={"chargily_secret_key": SECRET})
    c = Chargily(settings, client=httpx.Client(transport=httpx.MockTransport(handler)))
    co = c.create_checkout(amount_dzd=2000, method="cib", locale="xx", appointment_id="a1",
                           description="BenMahdia a1")
    assert co.id == "chk_x"
    assert (seen["amount"], seen["currency"], seen["locale"]) == (2000, "dzd", "ar")
    assert seen["metadata"] == {"appointment_id": "a1"}


# --- failed / abandoned payment releases the slot (R-46, R-26) -----------------------


@pytest.mark.parametrize("kind", ["checkout.failed", "checkout.canceled", "checkout.expired"])
def test_every_failure_kind_releases_the_slot_for_another_patient(client, sms, chargily, kind):
    doctor, _, h = paid_card_appointment(client, sms, chargily)
    b = verified_patient(client, sms, PHONE_B)
    assert hold(client, b, doctor).status_code == 409             # still held
    assert send(client, event(kind, "chk_1")).status_code == 200
    assert appointment(h["id"]) is None
    assert payment("chk_1").status == PaymentStatus.failed
    assert held(client, b, doctor)["start"] == SLOT


def test_abandoned_checkout_frees_the_slot_after_the_hold_timeout(client, sms, chargily):
    """No webhook at all (patient closed the page): the slot comes back once
    the hold runs out."""
    doctor, _, _ = paid_card_appointment(client, sms, chargily)
    b = verified_patient(client, sms, PHONE_B)
    assert hold(client, b, doctor).status_code == 409
    expire_holds()
    assert held(client, b, doctor)["start"] == SLOT


# --- return page (R-52) -------------------------------------------------------------------


@pytest.mark.parametrize("result", ["success", "failure", "<script>alert(1)</script>"])
def test_return_page_reveals_nothing_and_reflects_nothing(client, sms, chargily, result):
    _, _, h = paid_card_appointment(client, sms, chargily)
    r = client.get("/v1/payments/return", params={"result": result, "checkout_id": "chk_1"})
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/html")
    text = r.text
    assert "<script" not in text and "chk_1" not in text and h["id"] not in text
    assert "661234501" not in text and "2000" not in text
    assert "dir='rtl'" in text and "lang='fr'" in text
    if result != "success":
        assert "Paiement non abouti" in text


# --- check-in codes (R-56..R-61) ---------------------------------------------------------


def test_code_alphabet_has_no_look_alikes_and_codes_are_six_chars():
    assert not set("0O1IL") & set(checkin.ALPHABET)
    assert checkin.LENGTH == 6
    assert re.fullmatch(r"[A-Z0-9]+", checkin.ALPHABET)


def test_card_confirmed_appointment_checks_in_on_the_day(client, sms, chargily):
    """R-56 + R-58: the code issued by the webhook works at the front desk."""
    doc = doctor_with_password()
    verified_patient(client, sms, PHONE_A)
    pid = user_id(PHONE_A)
    a = add_appointment(doc.user_id, pid, TODAY_EVENING, status=AppointmentStatus.awaiting_payment,
                        method=None, hold_expires_at=clock.now() + timedelta(minutes=10))
    with Session(engine) as db:
        db.add(Payment(appointment_id=a.id, patient_id=pid, amount_dzd=2000,
                       method=PaymentMethod.cib, chargily_id="chk_today"))
        db.commit()
    assert send(client, event("checkout.paid", "chk_today")).status_code == 200
    code = appointment(str(a.id)).checkin_code
    assert code and set(code) <= set(checkin.ALPHABET)
    r = client.post("/v1/staff/checkin", json={"code": code.lower()}, headers=doc_headers(client))
    assert r.status_code == 200, r.text
    assert r.json()["checked_in_at"] is not None


def test_nine_wrong_codes_still_let_the_right_one_through(client, sms):
    """R-61 boundary: the lock starts at the 10th failure, not before."""
    doc = doctor_with_password()
    verified_patient(client, sms, PHONE_A)
    add_appointment(doc.user_id, user_id(PHONE_A), TODAY_EVENING, checkin_code="K7M4PX")
    h = doc_headers(client)
    for i in range(9):
        assert client.post("/v1/staff/checkin", json={"code": f"WRONG{i}"}, headers=h).status_code == 404
    assert client.post("/v1/staff/checkin", json={"code": "K7M4PX"}, headers=h).status_code == 200


def test_failed_check_in_is_audited_without_the_code(client, sms):
    doctor_with_password()
    h = doc_headers(client)
    client.post("/v1/staff/checkin", json={"code": "QWERTY"}, headers=h)
    with Session(engine) as db:
        rows = db.query(AuditLog).filter(AuditLog.action == "checkin.failed").all()
    assert len(rows) == 1 and rows[0].target is None
    assert all("QWERTY" not in (r.target or "") for r in rows)


def test_cancelled_card_appointment_cannot_check_in(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms, PHONE_A)
    add_appointment(doc.user_id, user_id(PHONE_A), TODAY_EVENING, status=AppointmentStatus.cancelled,
                    method=PaymentMethod.cib, checkin_code="K7M4PX")
    r = client.post("/v1/staff/checkin", json={"code": "K7M4PX"}, headers=doc_headers(client))
    assert (r.status_code, err(r)) == (409, "not_checkable")


# --- no card data stored (R-51) ---------------------------------------------------------


def test_no_table_has_a_card_column():
    suspicious = re.compile(r"card|pan$|^pan_|cvv|cvc|expiry|exp_month|exp_year|iban|(^|_)rib($|_)|(^|_)bin$")
    offenders = [
        f"{t.name}.{c.name}"
        for t in Base.metadata.sorted_tables
        for c in t.columns
        if suspicious.search(c.name.lower())
    ]
    assert offenders == []
    assert {c.name for c in Payment.__table__.columns} == {
        "id", "appointment_id", "patient_id", "amount_dzd", "method", "chargily_id",
        "status", "paid_at", "created_at",
    }


def test_webhook_card_details_are_not_stored(client, sms, chargily):
    """Even if Chargily's event carried card hints, nothing of it lands in the
    database or the audit log."""
    _, _, h = paid_card_appointment(client, sms, chargily)
    body = body_with("checkout.paid", "chk_1", card_last4="9187", pan="6280000000009187")
    assert send(client, body).status_code == 200
    with engine.connect() as conn:
        dump = []
        for t in Base.metadata.sorted_tables:
            for row in conn.execute(t.select()):
                dump.append(" ".join(str(v) for v in row))
    blob = "\n".join(dump)
    assert "9187" not in blob
