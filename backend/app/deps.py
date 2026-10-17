import uuid

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from . import security
from .clock import clock
from .db import get_db
from .errors import ApiError
from .models import AccountStatus, Role, User

_bearer = HTTPBearer(auto_error=False)


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    """The caller, from a valid access token. Deleted accounts are refused."""
    if credentials is None:
        raise ApiError(401, "not_authenticated")
    claims = security.decode(credentials.credentials, "access", clock.now())
    if claims is None:
        raise ApiError(401, "token_invalid")
    user = db.get(User, uuid.UUID(claims["sub"]))
    if user is None or not user.active:
        raise ApiError(401, "token_invalid")
    return user


def verified_patient(user: User = Depends(current_user)) -> User:
    """A patient whose identity the clinic approved. Pending patients cannot
    book (PRD 4.2); doctors and admins use the dashboard, not this API."""
    if user.role != Role.patient:
        raise ApiError(403, "forbidden")
    if user.status != AccountStatus.verified:
        raise ApiError(403, "not_verified")
    return user
