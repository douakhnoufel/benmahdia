import uuid

from fastapi import Request
from sqlalchemy.orm import Session

from .models import AuditLog


def record(
    db: Session,
    action: str,
    *,
    actor_id: uuid.UUID | None = None,
    target: str | None = None,
    request: Request | None = None,
) -> None:
    """Adds an audit line to the current transaction. [target] must never be
    medical content, a code, a password or a token."""
    ip = request.client.host if request is not None and request.client else None
    db.add(AuditLog(actor_id=actor_id, action=action, target=target, ip=ip))
