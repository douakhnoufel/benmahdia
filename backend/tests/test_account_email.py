"""The account's contact email (Profile & Settings). Stored, not verified,
not a sign-in method."""

from .conftest import bearer, register


def test_email_starts_empty_then_is_set_and_cleared(client, sms):
    s = register(client, sms)
    assert client.get("/v1/me", headers=bearer(s)).json()["email"] is None

    r = client.put("/v1/me/email", json={"email": "Karim@Example.COM"}, headers=bearer(s))
    assert r.status_code == 200, r.text
    assert r.json()["email"] == "karim@example.com"              # trimmed + lower-cased
    assert client.get("/v1/me", headers=bearer(s)).json()["email"] == "karim@example.com"

    cleared = client.put("/v1/me/email", json={"email": ""}, headers=bearer(s))
    assert cleared.json()["email"] is None
    assert client.put("/v1/me/email", json={"email": None}, headers=bearer(s)).json()["email"] is None


def test_a_malformed_email_is_refused(client, sms):
    s = register(client, sms)
    for bad in ["nope", "a@b", "a b@c.com", "a@b c.com", "x" * 315 + "@example.com"]:
        r = client.put("/v1/me/email", json={"email": bad}, headers=bearer(s))
        assert r.status_code == 422, bad
    assert client.get("/v1/me", headers=bearer(s)).json()["email"] is None


def test_setting_an_email_needs_a_signed_in_user(client):
    assert client.put("/v1/me/email", json={"email": "a@b.com"}).status_code == 401
