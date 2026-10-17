from app.models import AuditLog

from .conftest import advance, bearer, last_code, proof, register


def login(client, password, phone="0661 23 45 67"):
    return client.post("/v1/auth/login", json={"phone": phone, "password": password})


def test_login(client, sms):
    register(client, sms)
    r = login(client, "sobre2026")
    assert r.status_code == 200
    assert r.json()["user"]["phone"] == "+213661234567"


def test_wrong_password_and_unknown_phone_look_the_same(client, sms):
    register(client, sms)
    a = login(client, "wrong")
    b = login(client, "sobre2026", phone="0771234567")
    assert a.status_code == b.status_code == 401
    assert a.json() == b.json() == {"detail": {"code": "wrong_credentials"}}


def test_five_failures_lock_for_15_minutes(client, sms):
    register(client, sms)
    for _ in range(4):
        assert login(client, "wrong").status_code == 401
    r = login(client, "wrong")
    assert r.status_code == 423
    assert r.json()["detail"] == {"code": "account_locked", "retry_after": 900}
    r = login(client, "sobre2026")
    assert r.status_code == 423
    advance(minutes=15, seconds=1)
    assert login(client, "sobre2026").status_code == 200


def test_logins_are_audited(client, sms):
    register(client, sms)
    login(client, "wrong")
    login(client, "sobre2026")
    from app.db import SessionLocal

    with SessionLocal() as db:
        actions = [r.action for r in db.query(AuditLog).order_by(AuditLog.id)]
    assert actions[-2:] == ["login.failed", "login.succeeded"]


def test_reset_password(client, sms):
    old = register(client, sms)
    advance(minutes=2)
    p = proof(client, sms, purpose="reset_password")
    r = client.post("/v1/auth/password/reset", json={"phone_proof": p, "password": "nouveau2026"})
    assert r.status_code == 200
    assert login(client, "sobre2026").status_code == 401
    assert login(client, "nouveau2026").status_code == 200
    # Other sessions are signed out.
    r = client.post("/v1/auth/refresh", json={"refresh_token": old["refresh_token"]})
    assert r.status_code == 401


def test_reset_unlocks(client, sms):
    register(client, sms)
    for _ in range(5):
        login(client, "wrong")
    advance(minutes=2)
    p = proof(client, sms, purpose="reset_password")
    client.post("/v1/auth/password/reset", json={"phone_proof": p, "password": "nouveau2026"})
    assert login(client, "nouveau2026").status_code == 200


def test_reset_for_unknown_number_sends_nothing(client, sms):
    r = client.post("/v1/auth/otp/request",
                    json={"phone": "0771234567", "purpose": "reset_password"})
    assert r.status_code == 202
    assert sms.sent == []
    r = client.post("/v1/auth/otp/verify",
                    json={"phone": "0771234567", "purpose": "reset_password", "code": "123456"})
    assert r.status_code == 410


def test_reset_weak_password(client, sms):
    register(client, sms)
    advance(minutes=2)
    p = proof(client, sms, purpose="reset_password")
    r = client.post("/v1/auth/password/reset", json={"phone_proof": p, "password": "abc"})
    assert r.status_code == 422
