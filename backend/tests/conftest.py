import os
import tempfile

# In-memory SQLite by default. A DATABASE_URL set in the shell wins, so the
# PostgreSQL race tests can run; every test drops and recreates its tables,
# so point it at a throwaway database only.
os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ["ENVIRONMENT"] = "test"
os.environ["SELFIE_DIR"] = tempfile.mkdtemp(prefix="benmahdia-selfies-")
os.environ["GOOGLE_CLIENT_IDS"] = "google-client.apps.googleusercontent.com"
os.environ["APPLE_CLIENT_IDS"] = "dz.benmahdia.app"

from datetime import datetime, timedelta, timezone  # noqa: E402
from pathlib import Path  # noqa: E402

import jwt  # noqa: E402
import pytest  # noqa: E402
from cryptography.hazmat.primitives.asymmetric import rsa  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.clock import clock  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.db import Base, engine  # noqa: E402
from app.main import app  # noqa: E402
from app.sms import ConsoleSmsSender, get_sms_sender  # noqa: E402
from app.social import SocialVerifier, get_social_verifier  # noqa: E402

START = datetime(2026, 10, 17, 18, 0)


class Keys:
    """A stand-in for Google's / Apple's public key endpoint."""

    def __init__(self) -> None:
        self.private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        self.public = jwt.PyJWK.from_dict(
            {**jwt.algorithms.RSAAlgorithm.to_jwk(self.private.public_key(), as_dict=True),
             "alg": "RS256", "kid": "k1"}
        )

    def get_signing_key_from_jwt(self, token: str) -> jwt.PyJWK:
        return self.public


class Social:
    def __init__(self) -> None:
        self.google_keys = Keys()
        self.apple_keys = Keys()
        self.verifier = SocialVerifier(get_settings(), self.google_keys, self.apple_keys)

    def google(self, sub="g-123", aud="google-client.apps.googleusercontent.com",
               iss="https://accounts.google.com", key=None, expired=False) -> str:
        return self._token(key or self.google_keys.private, sub, aud, iss, expired,
                           email="patient@example.com")

    def apple(self, sub="a-456", aud="dz.benmahdia.app", key=None) -> str:
        return self._token(key or self.apple_keys.private, sub, aud,
                           "https://appleid.apple.com", False)

    @staticmethod
    def _token(key, sub, aud, iss, expired, email=None) -> str:
        now = datetime.now(timezone.utc) - (timedelta(hours=2) if expired else timedelta())
        claims = {"iss": iss, "sub": sub, "aud": aud, "iat": now,
                  "exp": now + timedelta(hours=1)}
        if email:
            claims |= {"email": email, "email_verified": True}
        return jwt.encode(claims, key, algorithm="RS256", headers={"kid": "k1"})


@pytest.fixture
def sms() -> ConsoleSmsSender:
    return ConsoleSmsSender()


@pytest.fixture
def social() -> Social:
    return Social()


@pytest.fixture
def client(sms, social):
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    if engine.dialect.name == "postgresql":
        # Fresh connections: psycopg prepares a statement after a few runs,
        # and a plan prepared against the dropped tables (their enum types
        # get new ids) fails with "cached plan must not change result type".
        engine.dispose()
    for leftover in Path(os.environ["SELFIE_DIR"]).glob("*"):
        leftover.unlink()
    clock.frozen = START
    app.dependency_overrides[get_sms_sender] = lambda: sms
    app.dependency_overrides[get_social_verifier] = lambda: social.verifier
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
    clock.frozen = None


def advance(**kwargs) -> None:
    clock.frozen = clock.frozen + timedelta(**kwargs)


def last_code(sms: ConsoleSmsSender, phone: str = "+213661234567") -> str:
    return [code for to, code in sms.sent if to == phone][-1]


def proof(client, sms, phone="0661234567", purpose="sign_up") -> str:
    r = client.post("/v1/auth/otp/request", json={"phone": phone, "purpose": purpose})
    assert r.status_code == 202, r.text
    e164 = "+213" + phone.lstrip("0")
    r = client.post("/v1/auth/otp/verify",
                    json={"phone": phone, "purpose": purpose, "code": last_code(sms, e164)})
    assert r.status_code == 200, r.text
    return r.json()["phone_proof"]


def register(client, sms, phone="0661234567", password="sobre2026") -> dict:
    p = proof(client, sms, phone)
    r = client.post("/v1/auth/register",
                    json={"phone_proof": p, "password": password, "language": "fr"})
    assert r.status_code == 201, r.text
    return r.json()


def bearer(session: dict) -> dict:
    return {"Authorization": f"Bearer {session['access_token']}"}
