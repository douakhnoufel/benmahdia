"""Chargily Pay v2 client (PRD 4.4): creates checkouts and checks the
signature of webhooks. Card numbers never reach us."""

import hashlib
import hmac
from dataclasses import dataclass

import httpx

from .config import Settings, get_settings
from .errors import ApiError


@dataclass(frozen=True)
class Checkout:
    id: str
    url: str


class Chargily:
    def __init__(self, settings: Settings, client: httpx.Client | None = None) -> None:
        self._settings = settings
        self._client = client or httpx.Client(timeout=15)

    @property
    def configured(self) -> bool:
        return bool(self._settings.chargily_secret_key)

    def create_checkout(
        self,
        *,
        amount_dzd: int,
        method: str,
        locale: str,
        appointment_id: str,
        description: str,
    ) -> Checkout:
        if not self.configured:
            raise ApiError(503, "payments_unavailable")
        base = self._settings.public_base_url.rstrip("/")
        try:
            r = self._client.post(
                f"{self._settings.chargily_api_url.rstrip('/')}/checkouts",
                headers={"Authorization": f"Bearer {self._settings.chargily_secret_key}"},
                json={
                    "amount": amount_dzd,
                    "currency": "dzd",
                    "payment_method": method,
                    "locale": locale if locale in ("ar", "fr") else "ar",
                    "success_url": f"{base}/v1/payments/return?result=success",
                    "failure_url": f"{base}/v1/payments/return?result=failure",
                    "webhook_endpoint": f"{base}/v1/payments/chargily/webhook",
                    # No medical content: only our appointment id.
                    "description": description,
                    "metadata": {"appointment_id": appointment_id},
                },
            )
        except httpx.HTTPError:
            raise ApiError(502, "payments_unavailable")
        if r.status_code >= 300:
            raise ApiError(502, "payments_unavailable")
        body = r.json()
        return Checkout(id=str(body["id"]), url=str(body["checkout_url"]))

    def signature_ok(self, raw_body: bytes, signature: str | None) -> bool:
        """Chargily signs the raw body with HMAC-SHA256 and our secret key."""
        if not signature or not self.configured:
            return False
        expected = hmac.new(
            self._settings.chargily_secret_key.encode(), raw_body, hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(expected, signature)


def get_chargily() -> Chargily:
    return Chargily(get_settings())
