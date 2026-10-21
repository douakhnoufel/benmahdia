"""The patient's ID declaration (PRD 4.2). The phone reads the ID card and
sends only the three fields the patient confirmed, plus a live selfie for the
doctor. The card image never reaches the server. This route never says the
identity is "verified": the clinic approves what the patient declared."""

import base64
import binascii
import re
from datetime import date, datetime
from typing import Literal

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import audit, idcrypto, scheduling, selfies
from ..clock import clock
from ..config import Settings, get_settings
from ..db import get_db
from ..deps import current_user
from ..errors import ApiError
from ..models import AccountStatus, IdDeclaration, IdStatus, Role, User
from .doctors import utc_iso

router = APIRouter(prefix="/v1/me/identity", tags=["identity"])

_JPEG_START = b"\xff\xd8\xff"
_ID_NUMBER = re.compile(r"^[A-Z0-9]{6,30}$")


class IdentityIn(BaseModel):
    # What the patient confirmed on the review screen.
    id_number: str = Field(min_length=1, max_length=64)
    full_name: str = Field(min_length=1, max_length=160)
    birth_date: date
    # The live selfie for the doctor, JPEG, base64 (about 2 MB at most).
    selfie_jpeg_base64: str = Field(min_length=1, max_length=3_000_000)


class IdentityOut(BaseModel):
    status: Literal["none", "declared", "approved", "rejected"]
    declared_at: str | None = None
    reject_reason: str | None = None
    # How many more times the patient may submit.
    submissions_left: int


def _out(user: User, settings: Settings) -> IdentityOut:
    d = user.id_declaration
    if d is None:
        status = "approved" if user.status == AccountStatus.verified else "none"
        return IdentityOut(status=status, submissions_left=settings.id_max_submissions)
    return IdentityOut(
        status=d.status.value,
        declared_at=utc_iso(d.declared_at),
        reject_reason=d.reject_reason if d.status == IdStatus.rejected else None,
        submissions_left=max(0, settings.id_max_submissions - d.attempts),
    )


def _patient(user: User = Depends(current_user)) -> User:
    if user.role != Role.patient:
        raise ApiError(403, "forbidden")
    return user


def _clean_name(raw: str) -> str:
    name = " ".join(raw.split())
    if len(name) < 2 or len(name) > 120 or not any(ch.isalpha() for ch in name):
        raise ApiError(422, "invalid_name")
    return name


def _clean_birth(value: date) -> date:
    if value < date(1900, 1, 1) or value > scheduling.clinic_today(clock.now()):
        raise ApiError(422, "invalid_birth_date")
    return value


def _selfie_bytes(encoded: str, settings: Settings) -> bytes:
    try:
        data = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError):
        raise ApiError(422, "invalid_selfie")
    if not data.startswith(_JPEG_START) or len(data) > settings.selfie_max_bytes:
        raise ApiError(422, "invalid_selfie")
    return data


@router.get("", response_model=IdentityOut)
def read_status(
    user: User = Depends(_patient), settings: Settings = Depends(get_settings)
) -> IdentityOut:
    return _out(user, settings)


@router.post("", response_model=IdentityOut, status_code=201)
def declare(
    body: IdentityIn,
    request: Request,
    user: User = Depends(_patient),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> IdentityOut:
    """Stores the declared ID fields. The plain ID number is turned into an
    HMAC and dropped; it is never stored, logged or returned."""
    if user.status == AccountStatus.verified:
        raise ApiError(409, "already_approved")
    if user.status != AccountStatus.pending_verification:
        raise ApiError(403, "forbidden")
    existing = user.id_declaration
    if existing is not None:
        if existing.status == IdStatus.declared:
            raise ApiError(409, "already_declared")
        if existing.status == IdStatus.approved:
            raise ApiError(409, "already_approved")
        if existing.attempts >= settings.id_max_submissions:
            raise ApiError(403, "too_many_submissions")

    number = idcrypto.normalize_id_number(body.id_number)
    if not _ID_NUMBER.match(number):
        raise ApiError(422, "invalid_id_number")
    name = _clean_name(body.full_name)
    birth = _clean_birth(body.birth_date)
    jpeg = _selfie_bytes(body.selfie_jpeg_base64, settings)

    digest = idcrypto.id_hmac(number)
    owner = str(user.id)

    def refuse_duplicate() -> ApiError:
        # The clinic sees the attempt on the sign-ups page; the patient is not
        # told whose account holds this ID.
        db.rollback()
        audit.record(db, "identity.duplicate", actor_id=user.id, target=owner, request=request)
        db.commit()
        return ApiError(409, "id_already_linked")

    clash = db.scalar(
        select(IdDeclaration.user_id).where(
            IdDeclaration.id_hmac == digest, IdDeclaration.user_id != user.id
        )
    )
    if clash is not None:
        raise refuse_duplicate()

    new_file = selfies.save(jpeg, user.id)
    old_file = existing.selfie_file if existing else None
    name_enc = idcrypto.encrypt(name.encode(), kind="name", owner=owner)
    birth_enc = idcrypto.encrypt(birth.isoformat().encode(), kind="birth", owner=owner)
    now = clock.now()
    if existing is None:
        db.add(
            IdDeclaration(
                user_id=user.id,
                id_hmac=digest,
                name_enc=name_enc,
                birth_enc=birth_enc,
                selfie_file=new_file,
                status=IdStatus.declared,
                attempts=1,
                declared_at=now,
            )
        )
    else:
        existing.id_hmac = digest
        existing.name_enc = name_enc
        existing.birth_enc = birth_enc
        existing.selfie_file = new_file
        existing.status = IdStatus.declared
        existing.attempts += 1
        existing.reject_reason = None
        existing.declared_at = now
        existing.decided_at = None
        existing.decided_by = None
    audit.record(db, "identity.declared", actor_id=user.id, target=owner, request=request)
    try:
        db.commit()
    except IntegrityError:
        # Another account declared the same ID at the same moment.
        selfies.delete(new_file)
        raise refuse_duplicate()
    except Exception:
        selfies.delete(new_file)
        raise
    selfies.delete(old_file)
    db.refresh(user)
    return _out(user, settings)
