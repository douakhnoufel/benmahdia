from app.config import get_settings
from app.social import SocialVerifier

from .conftest import Keys, advance, bearer, last_code, proof


def google(client, token):
    return client.post("/v1/auth/google", json={"id_token": token, "language": "fr"})


def test_google_creates_an_account_without_phone(client, social):
    r = google(client, social.google())
    assert r.status_code == 200
    user = r.json()["user"]
    assert user["phone"] is None
    assert user["providers"] == ["google"]
    assert user["has_password"] is False
    assert user["status"] == "pending_verification"


def test_same_google_account_signs_back_in(client, social):
    a = google(client, social.google()).json()
    b = google(client, social.google()).json()
    assert a["user"]["id"] == b["user"]["id"]


def test_google_token_checks(client, social):
    for token in [
        social.google(aud="someone-elses-app"),
        social.google(iss="https://evil.example.com"),
        social.google(key=Keys().private),
        social.google(expired=True),
        "not-a-jwt",
    ]:
        r = google(client, token)
        assert r.status_code == 401, token
        assert r.json()["detail"]["code"] == "social_token_invalid"


def test_apple(client, social):
    r = client.post("/v1/auth/apple", json={"identity_token": social.apple()})
    assert r.status_code == 200
    assert r.json()["user"]["providers"] == ["apple"]
    # An Apple token is not accepted as a Google one.
    assert google(client, social.apple()).status_code == 401


def test_provider_not_configured(client, social):
    from app.main import app
    from app.social import get_social_verifier

    settings = get_settings().model_copy(update={"google_client_ids": []})
    app.dependency_overrides[get_social_verifier] = lambda: SocialVerifier(
        settings, social.google_keys, social.apple_keys
    )
    r = google(client, social.google())
    assert r.status_code == 503 and r.json()["detail"]["code"] == "social_unavailable"


def test_add_phone_after_google(client, sms, social):
    s = google(client, social.google()).json()
    p = proof(client, sms, phone="0771234567", purpose="attach_phone")
    r = client.put("/v1/me/phone", json={"phone_proof": p}, headers=bearer(s))
    assert r.status_code == 200
    assert r.json()["phone"] == "+213771234567"
    # The number is now taken for sign-up.
    advance(minutes=2)
    r = client.post("/v1/auth/otp/request", json={"phone": "0771234567", "purpose": "sign_up"})
    assert r.status_code == 409


def test_add_phone_needs_its_own_proof(client, sms, social):
    s = google(client, social.google()).json()
    p = proof(client, sms, phone="0771234567", purpose="sign_up")
    r = client.put("/v1/me/phone", json={"phone_proof": p}, headers=bearer(s))
    assert r.status_code == 410


def test_add_phone_needs_login(client, sms):
    p = proof(client, sms, phone="0771234567", purpose="attach_phone")
    assert client.put("/v1/me/phone", json={"phone_proof": p}).status_code == 401
