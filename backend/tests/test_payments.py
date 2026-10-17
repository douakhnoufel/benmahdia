import hashlib
import hmac
import json
import uuid

import pytest
from sqlalchemy.orm import Session

from app.chargily import Chargily, Checkout, get_chargily
from app.config import get_settings
from app.db import engine
from app.errors import ApiError
from app.main import app
from app.models import Appointment, AppointmentStatus, Payment, PaymentStatus

from .booking_helpers import expire_holds, headers, make_doctor, verified_patient
from .conftest import bearer, register

SECRET = "test_sk_unit_tests_only"
SLOT = "2026-10-19T08:00:00Z"


class FakeChargily(Chargily):
    """Records checkouts instead of calling Chargily."""

    def __init__(self) -> None:
        settings = get_settings().model_copy(update={"chargily_secret_key": SECRET})
        super().__init__(settings, client=None)
        self.created: list[dict] = []
        self.fail = False

    def create_checkout(self, **kwargs) -> Checkout:
        if self.fail:
            raise ApiError(502, "payments_unavailable")
        self.created.append(kwargs)
        return Checkout(id=f"chk_{len(self.created)}", url=f"https://pay.test/chk_{len(self.created)}")


@pytest.fixture
def chargily(client):
    fake = FakeChargily()
    app.dependency_overrides[get_chargily] = lambda: fake
    return fake


def sign(body: bytes, secret: str = SECRET) -> str:
    return hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


def event(kind: str, checkout_id: str) -> bytes:
    return json.dumps({"id": "evt_1", "entity": "event", "type": kind,
                       "data": {"id": checkout_id, "entity": "checkout", "status": kind.split(".")[1]}}).encode()


def send(client, body: bytes, signature: str | None = None):
    h = {"content-type": "application/json"}
    if signature is not False:
        h["signature"] = signature if signature is not None else sign(body)
    return client.post("/v1/payments/chargily/webhook", content=body, headers=h)


def held(client, session, doctor) -> dict:
    r = client.post("/v1/appointments/holds", headers=headers(session),
                    json={"doctor_id": str(doctor.user_id), "start": SLOT})
    assert r.status_code == 201, r.text
    return r.json()


def checkout(client, session, appointment_id, method="cib"):
    return client.post(f"/v1/appointments/{appointment_id}/checkout",
                       json={"method": method}, headers=headers(session))


def appointment(appointment_id) -> Appointment | None:
    with Session(engine) as db:
        return db.get(Appointment, uuid.UUID(appointment_id))


def payment(chargily_id) -> Payment:
    with Session(engine) as db:
        return db.query(Payment).filter(Payment.chargily_id == chargily_id).one()


# --- POST /v1/appointments/{id}/checkout ---------------------------------------


def test_checkout_opens_a_chargily_payment(client, sms, chargily):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    h = held(client, s, doctor)
    r = checkout(client, s, h["id"], "edahabia")
    assert r.status_code == 201, r.text
    assert r.json()["checkout_url"] == "https://pay.test/chk_1"
    [sent] = chargily.created
    assert (sent["amount_dzd"], sent["method"], sent["locale"]) == (2000, "edahabia", "fr")
    assert sent["appointment_id"] == h["id"]
    p = payment("chk_1")
    assert (p.status, p.amount_dzd) == (PaymentStatus.pending, 2000)
    # Still only held: nothing is confirmed before the webhook.
    assert appointment(h["id"]).status == AppointmentStatus.awaiting_payment


def test_checkout_refuses_clinic_and_bad_states(client, sms, chargily):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    h = held(client, a, doctor)
    r = checkout(client, a, h["id"], "clinic")
    assert (r.status_code, r.json()["detail"]["code"]) == (400, "payment_method_unavailable")
    assert checkout(client, b, h["id"]).status_code == 404
    expire_holds()
    r = checkout(client, a, h["id"])
    assert (r.status_code, r.json()["detail"]["code"]) == (409, "hold_expired")
    assert chargily.created == []


def test_checkout_needs_a_verified_patient(client, sms, chargily):
    pending = register(client, sms)
    r = client.post(f"/v1/appointments/{uuid.uuid4()}/checkout", json={"method": "cib"},
                    headers=bearer(pending))
    assert r.status_code == 403


def test_checkout_when_chargily_is_down(client, sms, chargily):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    h = held(client, s, doctor)
    chargily.fail = True
    r = checkout(client, s, h["id"])
    assert (r.status_code, r.json()["detail"]["code"]) == (502, "payments_unavailable")


def test_checkout_without_a_key_is_unavailable(client, sms):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    h = held(client, s, doctor)
    r = checkout(client, s, h["id"])   # real client, no CHARGILY_SECRET_KEY set
    assert (r.status_code, r.json()["detail"]["code"]) == (503, "payments_unavailable")


# --- POST /v1/payments/chargily/webhook ----------------------------------------


def test_paid_webhook_confirms_the_appointment(client, sms, chargily):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    h = held(client, s, doctor)
    checkout(client, s, h["id"], "cib")
    assert send(client, event("checkout.paid", "chk_1")).status_code == 200
    a = appointment(h["id"])
    assert (a.status, a.method, a.hold_expires_at) == (AppointmentStatus.confirmed, "cib", None)
    assert payment("chk_1").status == PaymentStatus.paid
    mine = client.get("/v1/appointments", headers=headers(s)).json()
    assert [(x["status"], x["method"]) for x in mine] == [("confirmed", "cib")]


def test_same_webhook_twice_records_one_payment(client, sms, chargily):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    h = held(client, s, doctor)
    checkout(client, s, h["id"])
    body = event("checkout.paid", "chk_1")
    assert send(client, body).status_code == 200
    first = payment("chk_1").paid_at
    assert send(client, body).status_code == 200
    with Session(engine) as db:
        assert db.query(Payment).count() == 1
    assert payment("chk_1").paid_at == first


def test_bad_or_missing_signature_is_refused(client, sms, chargily):
    doctor = make_doctor()
    s = verified_patient(client, sms)
    h = held(client, s, doctor)
    checkout(client, s, h["id"])
    body = event("checkout.paid", "chk_1")
    assert send(client, body, sign(body, "test_sk_someone_else")).status_code == 403
    assert send(client, body, False).status_code == 403
    assert appointment(h["id"]).status == AppointmentStatus.awaiting_payment


def test_failed_payment_releases_the_slot(client, sms, chargily):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    h = held(client, a, doctor)
    checkout(client, a, h["id"])
    assert send(client, event("checkout.failed", "chk_1")).status_code == 200
    assert payment("chk_1").status == PaymentStatus.failed
    assert appointment(h["id"]) is None
    assert held(client, b, doctor)["start"] == SLOT


def test_payment_after_the_slot_was_lost_is_flagged_for_refund(client, sms, chargily):
    doctor = make_doctor()
    a = verified_patient(client, sms, "0661111111")
    b = verified_patient(client, sms, "0662222222")
    h = held(client, a, doctor)
    checkout(client, a, h["id"])
    expire_holds()
    held(client, b, doctor)            # someone else takes the freed slot
    assert send(client, event("checkout.paid", "chk_1")).status_code == 200
    assert payment("chk_1").status == PaymentStatus.paid
    with Session(engine) as db:
        from app.models import AuditLog
        assert db.query(AuditLog).filter(AuditLog.action == "payment.needs_refund").count() == 1


def test_unknown_checkout_and_event_are_acknowledged(client, chargily):
    assert send(client, event("checkout.paid", "chk_unknown")).status_code == 200
    body = b"not json"
    assert send(client, body).status_code == 400


# --- GET /v1/payments/return ---------------------------------------------------------


def test_return_page_in_both_languages(client):
    r = client.get("/v1/payments/return?result=success")
    assert r.status_code == 200
    assert "dir='rtl'" in r.text and "Paiement reçu" in r.text
