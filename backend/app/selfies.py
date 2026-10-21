"""Encrypted selfie files. Plain image bytes never touch the disk: they are
encrypted in memory and only the ciphertext is written, to a private folder
that no route serves directly."""

import os
import uuid
from pathlib import Path

from . import idcrypto
from .config import get_settings


def _dir() -> Path:
    path = Path(get_settings().selfie_dir)
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    return path


def save(jpeg: bytes, owner: uuid.UUID) -> str:
    """Encrypts and stores [jpeg]; returns the file name to keep in the row."""
    name = f"{uuid.uuid4().hex}.bin"
    target = _dir() / name
    temp = target.with_suffix(".tmp")
    blob = idcrypto.encrypt(jpeg, kind="selfie", owner=str(owner))
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(blob)
    os.replace(temp, target)
    return name


def read(name: str, owner: uuid.UUID) -> bytes:
    return idcrypto.decrypt((_dir() / name).read_bytes(), kind="selfie", owner=str(owner))


def delete(name: str | None) -> None:
    """Removes a selfie file. A missing file is fine."""
    if name:
        (_dir() / name).unlink(missing_ok=True)
