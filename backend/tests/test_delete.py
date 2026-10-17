from app.db import SessionLocal
from app.models import User
from app.purge import purge

from .conftest import advance, bearer, register


def delete(client, session, password=None):
    return client.request("DELETE", "/v1/me", json={"password": password}, headers=bearer(session))


def test_delete_needs_the_password(client, sms):
    s = register(client, sms)
    assert delete(client, s).status_code == 401
    assert delete(client, s, "wrong").status_code == 401
    assert client.get("/v1/me", headers=bearer(s)).status_code == 200


def test_delete_disables_at_once(client, sms):
    s = register(client, sms)
    assert delete(client, s, "sobre2026").status_code == 204
    assert client.get("/v1/me", headers=bearer(s)).status_code == 401
    r = client.post("/v1/auth/refresh", json={"refresh_token": s["refresh_token"]})
    assert r.status_code == 401
    r = client.post("/v1/auth/login", json={"phone": "0661234567", "password": "sobre2026"})
    assert r.status_code == 401


def test_social_account_deletes_without_password(client, social):
    s = client.post("/v1/auth/google", json={"id_token": social.google()}).json()
    assert delete(client, s).status_code == 204
    r = client.post("/v1/auth/google", json={"id_token": social.google()})
    assert r.status_code == 403 and r.json()["detail"]["code"] == "account_deleted"


def test_purge_after_grace_period(client, sms):
    s = register(client, sms)
    delete(client, s, "sobre2026")
    with SessionLocal() as db:
        advance(days=29)
        assert purge(db) == 0
        advance(days=1)
        assert purge(db) == 1
        assert db.query(User).count() == 0
