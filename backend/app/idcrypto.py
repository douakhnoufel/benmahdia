"""Keyed hashing and encryption for the ID declaration (PRD 4.2).

Everything here uses secrets from the server's .env, never from the app or the
database. Each secret is stretched into its own 256-bit key with HKDF, so the
HMAC key, the data key and the selfie key can never be mixed up."""

import hashlib
import hmac
import os
import re
from functools import lru_cache

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

from .config import get_settings

_SEPARATORS = re.compile(r"[\s\-./_]+")


class CryptoError(Exception):
    """A stored value could not be decrypted (wrong key or tampered data)."""


@lru_cache
def _key(secret: str, label: str) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=None, info=label.encode()).derive(
        secret.encode()
    )


def normalize_id_number(raw: str) -> str:
    """Trim, drop spaces and separators, upper case."""
    return _SEPARATORS.sub("", raw.strip()).upper()


def id_hmac(normalized_id: str) -> str:
    """HMAC-SHA256 of the normalized ID number: the same card always gives the
    same value, which cannot be reversed without the server's key."""
    key = _key(get_settings().id_hmac_key, "benmahdia/id-hmac")
    return hmac.new(key, normalized_id.encode(), hashlib.sha256).hexdigest()


def _aead(secret: str, label: str) -> AESGCM:
    return AESGCM(_key(secret, label))


def encrypt(plain: bytes, *, kind: str, owner: str) -> bytes:
    """AES-256-GCM. The result is nonce + ciphertext. [kind] and [owner] are
    authenticated, so a value cannot be moved to another field or patient."""
    nonce = os.urandom(12)
    return nonce + _box(kind).encrypt(nonce, plain, f"{kind}:{owner}".encode())


def decrypt(blob: bytes, *, kind: str, owner: str) -> bytes:
    try:
        return _box(kind).decrypt(blob[:12], blob[12:], f"{kind}:{owner}".encode())
    except (InvalidTag, ValueError) as error:
        raise CryptoError(kind) from error


def _box(kind: str) -> AESGCM:
    settings = get_settings()
    if kind == "selfie":
        return _aead(settings.selfie_key, "benmahdia/selfie")
    return _aead(settings.id_data_key, "benmahdia/id-data")
