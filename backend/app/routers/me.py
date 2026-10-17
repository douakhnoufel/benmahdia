from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit, schemas, security, tokens
from ..clock import clock
from ..db import get_db
from ..deps import current_user
from ..errors import ApiError
from ..models import AccountStatus, OtpPurpose, Provider, User
from ..social import AppleTokens, get_apple_tokens
from .auth import spend_proof

router = APIRouter(prefix="/v1/me", tags=["me"])


@router.get("", response_model=schemas.Me)
def read_me(user: User = Depends(current_user)) -> schemas.Me:
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
    # TODO(dashboard): notify the patient's doctor once doctors are linked.
    audit.record(db, "account.deleted", actor_id=user.id, request=request)
    db.commit()
    return Response(status_code=204)
