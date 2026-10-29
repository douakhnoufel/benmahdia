"""What a doctor sees of a patient's ID declaration (PRD 4.2): the decrypted
name, birth date and selfie. Never the ID number, and no card image exists.
Every view is written to the audit log."""

import uuid
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit, idcrypto, selfies
from ..db import get_db
from ..errors import ApiError
from ..models import (
    AccountStatus,
    Appointment,
    DoctorProfile,
    IdDeclaration,
    Role,
    User,
)
from .doctors import utc_iso
from .staff import current_doctor

router = APIRouter(prefix="/v1/staff/signups", tags=["staff"])


class IdentityView(BaseModel):
    id_type: Literal["national_id", "passport"]
    full_name: str
    birth_date: str
    declared_at: str
    submissions: int
    has_selfie: bool


def reviewable(db: Session, doctor: DoctorProfile, user_id: uuid.UUID) -> IdDeclaration:
    """The declaration of a patient this doctor may look at: someone waiting in
    the sign-up queue, or a clinic patient (a booked visit with any doctor)."""
    user = db.get(User, user_id)
    if user is None or user.role != Role.patient or user.deleted_at is not None:
        raise ApiError(404, "identity_not_found")
    declaration = user.id_declaration
    if declaration is None:
        raise ApiError(404, "identity_not_found")
    if user.status != AccountStatus.pending_verification:
        booked = db.scalar(
            select(Appointment.id)
            .where(Appointment.patient_id == user.id)
            .limit(1)
        )
        if booked is None:
            raise ApiError(404, "identity_not_found")
    return declaration


@router.get("/{user_id}/identity", response_model=IdentityView)
def view_identity(
    user_id: uuid.UUID,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> IdentityView:
    d = reviewable(db, doctor, user_id)
    owner = str(d.user_id)
    try:
        name = idcrypto.decrypt(d.name_enc, kind="name", owner=owner).decode()
        birth = idcrypto.decrypt(d.birth_enc, kind="birth", owner=owner).decode()
    except idcrypto.CryptoError:
        raise ApiError(500, "identity_unreadable")
    audit.record(db, "identity.viewed", actor_id=doctor.user_id, target=owner, request=request)
    db.commit()
    return IdentityView(
        id_type=d.id_type,
        full_name=name,
        birth_date=birth,
        declared_at=utc_iso(d.declared_at),
        submissions=d.attempts,
        has_selfie=d.selfie_file is not None,
    )


@router.get("/{user_id}/selfie")
def view_selfie(
    user_id: uuid.UUID,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> Response:
    d = reviewable(db, doctor, user_id)
    if d.selfie_file is None:
        raise ApiError(404, "selfie_not_found")
    try:
        jpeg = selfies.read(d.selfie_file, d.user_id)
    except (idcrypto.CryptoError, FileNotFoundError):
        raise ApiError(404, "selfie_not_found")
    audit.record(db, "selfie.viewed", actor_id=doctor.user_id, target=str(d.user_id), request=request)
    db.commit()
    return Response(content=jpeg, media_type="image/jpeg", headers={"Cache-Control": "no-store"})
