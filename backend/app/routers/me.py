import re
import uuid

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit, schemas, security, tokens
from ..clock import clock
from ..db import get_db
from ..deps import current_user
from ..errors import ApiError
from ..models import AccountStatus, Alert, DoctorProfile, OtpPurpose, PrimaryDoctor, Provider, User
from ..social import AppleTokens, get_apple_tokens
from .auth import spend_proof
from .recovery import _doctor_of

router = APIRouter(prefix="/v1/me", tags=["me"])


@router.get("", response_model=schemas.Me)
def read_me(user: User = Depends(current_user)) -> schemas.Me:
    return tokens.me(user)


class MyDoctorOut(BaseModel):
    id: uuid.UUID
    name_ar: str
    name_fr: str


@router.get("/doctor", response_model=MyDoctorOut | None)
def my_doctor(
    user: User = Depends(current_user), db: Session = Depends(get_db)
) -> MyDoctorOut | None:
    """"My doctor": the doctor of the patient's first confirmed booking, or
    null before any booking. A label only (PRD 4.3)."""
    row = db.get(PrimaryDoctor, user.id)
    profile = db.get(DoctorProfile, row.doctor_id) if row is not None else None
    if profile is None:
        return None
    return MyDoctorOut(id=profile.user_id, name_ar=profile.name_ar, name_fr=profile.name_fr)


class EmailIn(BaseModel):
    # None or empty clears the address.
    email: str | None = None


# A contact address only: the account is not identified or recovered by email,
# so it is stored without a confirmation step (there is no email sender).
_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


@router.put("/email", response_model=schemas.Me)
def set_email(
    body: EmailIn,
    request: Request,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> schemas.Me:
    """Sets or clears the account's contact email. Not verified and not a
    sign-in method."""
    raw = (body.email or "").strip()
    if raw == "":
        user.email = None
    else:
        if len(raw) > 320 or not _EMAIL.fullmatch(raw):
            raise ApiError(422, "invalid_email")
        user.email = raw.lower()
    audit.record(db, "email.set", actor_id=user.id, request=request)
    db.commit()
    db.refresh(user)
    return tokens.me(user)


@router.put("/phone", response_model=schemas.Me)
def attach_phone(
    body: schemas.PhoneProof,
    request: Request,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> schemas.Me:
    """Adds a confirmed number to a Google / Apple account."""
    phone = spend_proof(db, body.phone_proof, OtpPurpose.attach_phone)
    other = db.scalar(select(User).where(User.phone == phone))
    if other is not None and other.id != user.id:
        raise ApiError(409, "phone_taken")
    user.phone = phone
    user.phone_verified_at = clock.now()
    audit.record(db, "phone.attached", actor_id=user.id, request=request)
    db.commit()
    db.refresh(user)
    return tokens.me(user)


@router.delete("", status_code=204)
def delete_account(
    body: schemas.DeleteAccount,
    request: Request,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
    apple_tokens: AppleTokens = Depends(get_apple_tokens),
) -> Response:
    """Disables the account at once and signs it out everywhere (PRD 12.5).
    Personal data is erased after the grace period by `python -m app.purge`.
    Accounts with a password must confirm it."""
    if user.password_hash is not None and not security.verify_password(
        body.password or "", user.password_hash
    ):
        raise ApiError(401, "wrong_credentials")
    now = clock.now()
    user.deleted_at = now
    user.status = AccountStatus.deleted
    tokens.revoke_all(db, user.id)
    for identity in user.identities:
        if identity.provider is Provider.apple and identity.apple_refresh_token:
            apple_tokens.revoke(identity.apple_refresh_token)
            identity.apple_refresh_token = None
    # PRD 12.5 step 2: the clinic is told. The alert names the event only;
    # without a booked visit the patient is not a clinic patient, so no alert.
    doctor_id = _doctor_of(db, user.id)
    if doctor_id is not None:
        db.add(Alert(doctor_id=doctor_id, patient_id=user.id, type="account_deleted", priority="normal"))
    audit.record(db, "account.deleted", actor_id=user.id, request=request)
    db.commit()
    return Response(status_code=204)
