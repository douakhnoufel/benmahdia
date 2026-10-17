"""Google and Apple sign-in: the app sends the provider's ID token; we check
its signature against the provider's public keys, its issuer, audience and
expiry, and key the account on the provider's stable subject id. Only
identity tokens cross the border, no health data (PRD 6, risks)."""

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol

import httpx
import jwt

from .config import Settings, get_settings
from .models import Provider

log = logging.getLogger("benmahdia.social")

GOOGLE_KEYS = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = ("accounts.google.com", "https://accounts.google.com")
APPLE_KEYS = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"


class SocialTokenInvalid(Exception):
    pass


class SocialNotConfigured(Exception):
    pass


@dataclass(frozen=True)
class SocialIdentity:
    provider: Provider
    subject: str
    email: str | None


class KeySource(Protocol):
    def get_signing_key_from_jwt(self, token: str) -> jwt.PyJWK: ...


class SocialVerifier:
    def __init__(
        self,
        settings: Settings,
        google_keys: KeySource | None = None,
        apple_keys: KeySource | None = None,
    ) -> None:
        self._settings = settings
        self._google_keys = google_keys or jwt.PyJWKClient(GOOGLE_KEYS)
        self._apple_keys = apple_keys or jwt.PyJWKClient(APPLE_KEYS)

    def verify(self, provider: Provider, token: str) -> SocialIdentity:
        if provider is Provider.google:
            audiences, keys, issuers = (
                self._settings.google_client_ids,
                self._google_keys,
                GOOGLE_ISSUERS,
            )
        else:
            audiences, keys, issuers = (
                self._settings.apple_client_ids,
                self._apple_keys,
                (APPLE_ISSUER,),
            )
        if not audiences:
            raise SocialNotConfigured(provider.value)
        try:
            key = keys.get_signing_key_from_jwt(token)
            claims = jwt.decode(
                token,
                key.key,
                algorithms=["RS256"],
                audience=audiences,
                options={"require": ["iss", "sub", "aud", "exp", "iat"]},
            )
        except (jwt.PyJWTError, jwt.PyJWKClientError) as error:
            raise SocialTokenInvalid(str(error)) from error
        if claims["iss"] not in issuers:
            raise SocialTokenInvalid("issuer")
        email = claims.get("email")
        verified = claims.get("email_verified") in (True, "true")
        return SocialIdentity(provider, str(claims["sub"]), email if verified else None)


_verifier: SocialVerifier | None = None


def get_social_verifier() -> SocialVerifier:
    global _verifier
    if _verifier is None:
        _verifier = SocialVerifier(get_settings())
    return _verifier


class AppleTokens:
    """Exchanges Apple's one-time authorization code for a refresh token and
    revokes it when the account is deleted (required by Apple). Needs the
    APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY from the developer
    account; without them it does nothing."""

    def __init__(self, settings: Settings) -> None:
        self._s = settings

    @property
    def configured(self) -> bool:
        s = self._s
        return bool(s.apple_team_id and s.apple_key_id and s.apple_private_key and s.apple_client_ids)

    def _client_secret(self, client_id: str) -> str:
        now = datetime.now(timezone.utc)
        return jwt.encode(
            {
                "iss": self._s.apple_team_id,
                "iat": now,
                "exp": now + timedelta(minutes=5),
                "aud": APPLE_ISSUER,
                "sub": client_id,
            },
            self._s.apple_private_key.replace("\\n", "\n"),
            algorithm="ES256",
            headers={"kid": self._s.apple_key_id},
        )

    def exchange(self, code: str) -> str | None:
        if not self.configured:
            return None
        client_id = self._s.apple_client_ids[0]
        try:
            response = httpx.post(
                f"{APPLE_ISSUER}/auth/token",
                data={
                    "client_id": client_id,
                    "client_secret": self._client_secret(client_id),
                    "code": code,
                    "grant_type": "authorization_code",
                },
                timeout=10,
            )
            response.raise_for_status()
            return response.json().get("refresh_token")
        except httpx.HTTPError:
            log.warning("Apple code exchange failed")
            return None

    def revoke(self, refresh_token: str) -> None:
        if not self.configured:
            return
        client_id = self._s.apple_client_ids[0]
        try:
            httpx.post(
                f"{APPLE_ISSUER}/auth/revoke",
                data={
                    "client_id": client_id,
                    "client_secret": self._client_secret(client_id),
                    "token": refresh_token,
                    "token_type_hint": "refresh_token",
                },
                timeout=10,
            ).raise_for_status()
        except httpx.HTTPError:
            log.warning("Apple token revocation failed")


def get_apple_tokens() -> AppleTokens:
    return AppleTokens(get_settings())
