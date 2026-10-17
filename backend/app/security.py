import hashlib
import hmac
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

from .config import get_settings

_hasher = PasswordHasher()
# Checked when the phone is unknown, so a miss takes as long as a hit.
_DUMMY_HASH = _hasher.hash("not-a-real-password-0")

PASSWORD_MIN = 8
PASSWORD_MAX = 128


def password_problems(password: str) -> list[str]:
    """The same rules as the app's checklist (PRD 4.1)."""
    problems = []
    if len(password) < PASSWORD_MIN:
        problems.append("length")
    if len(password) > PASSWORD_MAX:
        problems.append("too_long")
    if not any(c.isalpha() for c in password):
        problems.append("letter")
    if not any(c.isdigit() for c in password):
        problems.append("digit")
    return problems


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str | None) -> bool:
    try:
        return _hasher.verify(password_hash or _DUMMY_HASH, password) and (
            password_hash is not None
        )
    except (VerificationError, InvalidHashError):
        return False


def new_code(length: int) -> str:
    return "".join(str(secrets.randbelow(10)) for _ in range(length))


def hash_code(phone: str, purpose: str, code: str) -> str:
    key = get_settings().otp_secret.encode()
    return hmac.new(key, f"{phone}|{purpose}|{code}".encode(), hashlib.sha256).hexdigest()


def codes_match(a: str, b: str) -> bool:
    return hmac.compare_digest(a, b)


def new_refresh_token() -> tuple[str, str]:
    """(token for the client, hash for the database)."""
    token = secrets.token_urlsafe(32)
    return token, hash_token(token)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


_ALGORITHM = "HS256"


def encode(claims: dict, now: datetime, lifetime: timedelta) -> str:
    payload = {**claims, "iat": now, "exp": now + lifetime}
    return jwt.encode(payload, get_settings().jwt_secret, algorithm=_ALGORITHM)


def decode(token: str, typ: str, now: datetime) -> dict | None:
    """Claims of a valid token of type [typ], or None."""
    try:
        claims = jwt.decode(
            token,
            get_settings().jwt_secret,
            algorithms=[_ALGORITHM],
            options={"verify_exp": False, "require": ["exp", "iat", "typ"]},
        )
    except jwt.PyJWTError:
        return None
    if claims.get("typ") != typ:
        return None
    # Expiry is checked against our clock so tests can move time.
    expires = datetime.fromtimestamp(claims["exp"], timezone.utc).replace(tzinfo=None)
    if expires <= now:
        return None
    return claims


def access_token(user_id: uuid.UUID, role: str, now: datetime) -> str:
    minutes = get_settings().access_token_minutes
    return encode(
        {"sub": str(user_id), "role": role, "typ": "access"},
        now,
        timedelta(minutes=minutes),
    )


def phone_proof(otp_id: uuid.UUID, phone: str, purpose: str, now: datetime) -> str:
    minutes = get_settings().proof_minutes
    return encode(
        {"jti": str(otp_id), "phone": phone, "purpose": purpose, "typ": "phone_proof"},
        now,
        timedelta(minutes=minutes),
    )
