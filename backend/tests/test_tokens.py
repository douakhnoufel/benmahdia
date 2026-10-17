from .conftest import advance, bearer, register


def refresh(client, token):
    return client.post("/v1/auth/refresh", json={"refresh_token": token})


def test_access_token_lasts_15_minutes(client, sms):
    s = register(client, sms)
    advance(minutes=14)
    assert client.get("/v1/me", headers=bearer(s)).status_code == 200
    advance(minutes=1)
    r = client.get("/v1/me", headers=bearer(s))
    assert r.status_code == 401 and r.json()["detail"]["code"] == "token_invalid"


def test_me_needs_a_token(client):
    r = client.get("/v1/me")
    assert r.status_code == 401 and r.json()["detail"]["code"] == "not_authenticated"
    r = client.get("/v1/me", headers={"Authorization": "Bearer nonsense"})
    assert r.status_code == 401


def test_refresh_rotates(client, sms):
    s1 = register(client, sms)
    r = refresh(client, s1["refresh_token"])
    assert r.status_code == 200
    s2 = r.json()
    assert s2["refresh_token"] != s1["refresh_token"]
    assert client.get("/v1/me", headers=bearer(s2)).status_code == 200


def test_reusing_a_spent_refresh_token_signs_out_that_login(client, sms):
    s1 = register(client, sms)
    s2 = refresh(client, s1["refresh_token"]).json()
    # Someone replays the old token: refused, and the new one dies too.
    assert refresh(client, s1["refresh_token"]).status_code == 401
    assert refresh(client, s2["refresh_token"]).status_code == 401


def test_reuse_only_affects_its_own_login(client, sms):
    s1 = register(client, sms)
    other = client.post("/v1/auth/login",
                        json={"phone": "0661234567", "password": "sobre2026"}).json()
    refresh(client, s1["refresh_token"])
    refresh(client, s1["refresh_token"])
    assert refresh(client, other["refresh_token"]).status_code == 200


def test_refresh_token_expires_after_30_days(client, sms):
    s = register(client, sms)
    advance(days=30)
    assert refresh(client, s["refresh_token"]).status_code == 401


def test_logout(client, sms):
    s = register(client, sms)
    r = client.post("/v1/auth/logout", json={"refresh_token": s["refresh_token"]})
    assert r.status_code == 204
    assert refresh(client, s["refresh_token"]).status_code == 401
    # Logging out twice is harmless.
    r = client.post("/v1/auth/logout", json={"refresh_token": s["refresh_token"]})
    assert r.status_code == 204


def test_access_token_cannot_be_used_as_proof(client, sms):
    s = register(client, sms)
    r = client.post("/v1/auth/register",
                    json={"phone_proof": s["access_token"], "password": "sobre2026"})
    assert r.status_code == 410
