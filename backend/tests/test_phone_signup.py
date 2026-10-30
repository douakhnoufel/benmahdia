from app.phone import normalize_phone
from app.models import AuditLog

from .conftest import advance, bearer, last_code, proof, register


def test_normalize_phone():
    for raw in ["0550123456", "0550 12 34 56", "+213 550 12 34 56", "00213550123456",
                "550123456", "٠٥٥٠١٢٣٤٥٦", "05-50-12-34-56"]:
        assert normalize_phone(raw) == "+213550123456", raw
    for raw in ["021234567", "0450123456", "055012345", "abc", "", "+33612345678"]:
        assert normalize_phone(raw) is None, raw


def test_sign_up_by_phone(client, sms):
    r = client.post("/v1/auth/otp/request", json={"phone": "0661 23 45 67", "purpose": "sign_up"})
    assert r.status_code == 202
    assert r.json() == {"resend_after": 60, "expires_in": 300}
    code = last_code(sms)
    assert len(code) == 6 and code.isdigit()

    r = client.post("/v1/auth/otp/verify",
                    json={"phone": "0661234567", "purpose": "sign_up", "code": code})
    assert r.status_code == 200
    r = client.post("/v1/auth/register", json={"phone_proof": r.json()["phone_proof"],
                                               "password": "sobre2026", "language": "fr"})
    assert r.status_code == 201
    body = r.json()
    assert body["token_type"] == "bearer" and body["expires_in"] == 900
    assert body["user"]["phone"] == "+213661234567"
    assert body["user"]["status"] == "pending_verification"
    assert body["user"]["role"] == "patient"
    assert body["user"]["language"] == "fr"
    assert body["user"]["has_password"] is True

    me = client.get("/v1/me", headers=bearer(body))
    assert me.status_code == 200 and me.json()["id"] == body["user"]["id"]


def test_invalid_phone(client):
    r = client.post("/v1/auth/otp/request", json={"phone": "021 23 45 67", "purpose": "sign_up"})
    assert r.status_code == 422 and r.json()["detail"]["code"] == "phone_invalid"


def test_taken_phone(client, sms):
    register(client, sms)
    advance(minutes=2)
    r = client.post("/v1/auth/otp/request", json={"phone": "0661234567", "purpose": "sign_up"})
    assert r.status_code == 409 and r.json()["detail"]["code"] == "phone_taken"


def test_resend_waits_60_seconds(client, sms):
    body = {"phone": "0661234567", "purpose": "sign_up"}
    assert client.post("/v1/auth/otp/request", json=body).status_code == 202
    advance(seconds=20)
    r = client.post("/v1/auth/otp/request", json=body)
    assert r.status_code == 429
    assert r.json()["detail"] == {"code": "rate_limited", "retry_after": 40}
    assert r.headers["Retry-After"] == "40"
    advance(seconds=40)
    assert client.post("/v1/auth/otp/request", json=body).status_code == 202
    assert len(sms.sent) == 2


def test_new_code_replaces_old_one(client, sms):
    body = {"phone": "0661234567", "purpose": "sign_up"}
    client.post("/v1/auth/otp/request", json=body)
    old = last_code(sms)
    advance(seconds=61)
    client.post("/v1/auth/otp/request", json=body)
    new = last_code(sms)
    if old != new:
        r = client.post("/v1/auth/otp/verify", json={**body, "code": old})
        assert r.status_code == 400
    r = client.post("/v1/auth/otp/verify", json={**body, "code": new})
    assert r.status_code == 200


def test_five_codes_per_hour(client):
    body = {"phone": "0661234567", "purpose": "sign_up"}
    for _ in range(5):
        assert client.post("/v1/auth/otp/request", json=body).status_code == 202
        advance(seconds=61)
    r = client.post("/v1/auth/otp/request", json=body)
    assert r.status_code == 429 and r.json()["detail"]["code"] == "rate_limited"


def test_wrong_codes(client, sms):
    body = {"phone": "0661234567", "purpose": "sign_up"}
    client.post("/v1/auth/otp/request", json=body)
    right = last_code(sms)
    wrong = "000000" if right != "000000" else "111111"
    r = client.post("/v1/auth/otp/verify", json={**body, "code": wrong})
    assert r.status_code == 400
    assert r.json()["detail"] == {"code": "code_wrong", "attempts_left": 4}
    for _ in range(3):
        client.post("/v1/auth/otp/verify", json={**body, "code": wrong})
    r = client.post("/v1/auth/otp/verify", json={**body, "code": wrong})
    assert r.status_code == 429 and r.json()["detail"]["code"] == "too_many_attempts"
    # Even the right code is refused now.
    r = client.post("/v1/auth/otp/verify", json={**body, "code": right})
    assert r.status_code == 429


def test_code_expires_after_5_minutes(client, sms):
    body = {"phone": "0661234567", "purpose": "sign_up"}
    client.post("/v1/auth/otp/request", json=body)
    advance(minutes=5, seconds=1)
    r = client.post("/v1/auth/otp/verify", json={**body, "code": last_code(sms)})
    assert r.status_code == 410 and r.json()["detail"]["code"] == "code_expired"


def test_code_for_another_purpose_is_refused(client, sms):
    client.post("/v1/auth/otp/request", json={"phone": "0661234567", "purpose": "sign_up"})
    r = client.post("/v1/auth/otp/verify", json={"phone": "0661234567",
                                                 "purpose": "attach_phone", "code": last_code(sms)})
    assert r.status_code == 410


def test_proof_works_once(client, sms):
    p = proof(client, sms)
    r1 = client.post("/v1/auth/register", json={"phone_proof": p, "password": "sobre2026"})
    r2 = client.post("/v1/auth/register", json={"phone_proof": p, "password": "sobre2026"})
    assert r1.status_code == 201
    assert r2.status_code == 410


def test_proof_expires(client, sms):
    p = proof(client, sms)
    advance(minutes=11)
    r = client.post("/v1/auth/register", json={"phone_proof": p, "password": "sobre2026"})
    assert r.status_code == 410


def test_reset_proof_cannot_register(client, sms):
    register(client, sms, phone="0550123456")
    advance(minutes=2)
    p = proof(client, sms, phone="0550123456", purpose="reset_password")
    r = client.post("/v1/auth/register", json={"phone_proof": p, "password": "sobre2026"})
    assert r.status_code == 410


def test_weak_password(client, sms):
    p = proof(client, sms)
    r = client.post("/v1/auth/register", json={"phone_proof": p, "password": "short"})
    assert r.status_code == 422
    assert r.json()["detail"] == {"code": "password_weak", "rules": ["length", "digit"]}


def test_audit_has_no_secrets(client, sms):
    register(client, sms)
    from app.db import SessionLocal

    with SessionLocal() as db:
        rows = db.query(AuditLog).all()
    actions = [r.action for r in rows]
    assert actions == ["otp.requested", "account.created"]
    for row in rows:
        assert "sobre2026" not in (row.target or "")
        assert last_code(sms) not in (row.target or "")


def test_only_ascii_or_arabic_indic_digits_make_a_phone_number():
    from app.phone import normalize_phone
    assert normalize_phone("٠٥٥٠١٢٣٤٥٦") == "+213550123456"
    assert normalize_phone("०५५०१२३४५६") is None  # Devanagari digits
