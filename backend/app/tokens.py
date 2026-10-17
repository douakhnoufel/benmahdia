import uuid
from datetime import timedelta

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from . import schemas, security
from .clock import clock
from .config import get_settings
from .models import RefreshToken, User


def me(user: User) -> schemas.Me:
    return schemas.Me(
        id=user.id,
        role=user.role,
        status=user.status,
        phone=user.phone,
        language=user.language,
        has_password=user.password_hash is not None,
        providers=sorted(i.provider.value for i in user.identities),
    )


def issue(db: Session, user: User, family_id: uuid.UUID | None = None) -> schemas.Session:
    """A new access token and refresh token. [family_id] continues a
    rotation chain; None starts one (a new login)."""
    settings = get_settings()
    now = clock.now()
    token, token_hash = security.new_refresh_token()
    db.add(
        RefreshToken(
            user_id=user.id,
            family_id=family_id or uuid.uuid4(),
            token_hash=token_hash,
            expires_at=now + timedelta(days=settings.refresh_token_days),
        )
    )
    return schemas.Session(
        access_token=security.access_token(user.id, user.role.value, now),
        refresh_token=token,
        expires_in=settings.access_token_minutes * 60,
        user=me(user),
    )


def revoke_all(db: Session, user_id: uuid.UUID) -> None:
    db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=clock.now())
    )


def find(db: Session, token: str) -> RefreshToken | None:
    return db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == security.hash_token(token))
    )
