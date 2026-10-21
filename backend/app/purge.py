"""Erases accounts deleted more than DELETION_GRACE_DAYS ago (PRD 12.5).
Run daily: `python -m app.purge`. Records the clinic must keep by law will
follow the retention policy agreed with the clinic once they exist."""

from datetime import timedelta

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from . import audit, selfies
from .clock import clock
from .config import get_settings
from .db import SessionLocal
from .models import OtpCode, RefreshToken, User


def purge(db: Session) -> int:
    cutoff = clock.now() - timedelta(days=get_settings().deletion_grace_days)
    users = db.scalars(
        select(User).where(User.deleted_at.is_not(None), User.deleted_at <= cutoff)
    ).all()
    for user in users:
        if user.phone:
            db.execute(delete(OtpCode).where(OtpCode.phone == user.phone))
        db.execute(delete(RefreshToken).where(RefreshToken.user_id == user.id))
        if user.id_declaration is not None:
            selfies.delete(user.id_declaration.selfie_file)
        audit.record(db, "account.purged", actor_id=user.id)
        db.delete(user)
    db.commit()
    return len(users)


if __name__ == "__main__":
    with SessionLocal() as session:
        print(f"Purged {purge(session)} account(s).")
