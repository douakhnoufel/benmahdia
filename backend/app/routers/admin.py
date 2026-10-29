"""Super-admin dashboard routes (PRD 7). For now: the appointment price of
each doctor (PRD 4.4: "set per doctor by the super admin"). A plain doctor
gets 403 here, whatever the dashboard shows."""

import uuid

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit
from ..db import get_db
from ..deps import current_user
from ..errors import ApiError
from ..models import DoctorProfile, Role, User

router = APIRouter(prefix="/v1/admin", tags=["admin"])

MAX_PRICE_DZD = 100_000


class AdminDoctorOut(BaseModel):
    id: uuid.UUID
    name_ar: str
    name_fr: str
    price_dzd: int
    slot_minutes: int


class PriceIn(BaseModel):
    price_dzd: int = Field(ge=0, le=MAX_PRICE_DZD)


def current_super_admin(user: User = Depends(current_user)) -> User:
    if user.role != Role.super_admin:
        raise ApiError(403, "forbidden")
    return user


def _out(p: DoctorProfile) -> AdminDoctorOut:
    return AdminDoctorOut(
        id=p.user_id, name_ar=p.name_ar, name_fr=p.name_fr, price_dzd=p.price_dzd, slot_minutes=p.slot_minutes
    )


@router.get("/doctors", response_model=list[AdminDoctorOut])
def doctors(_: User = Depends(current_super_admin), db: Session = Depends(get_db)) -> list[AdminDoctorOut]:
    return [_out(p) for p in db.scalars(select(DoctorProfile).order_by(DoctorProfile.name_fr))]


@router.put("/doctors/{doctor_id}/price", response_model=AdminDoctorOut)
def set_price(
    doctor_id: uuid.UUID,
    body: PriceIn,
    request: Request,
    admin: User = Depends(current_super_admin),
    db: Session = Depends(get_db),
) -> AdminDoctorOut:
    """The price of new bookings with this doctor. A booked appointment keeps
    the price it was booked at."""
    # Locked like a hold locks it, so a hold sees either the old or the new price.
    profile = db.scalar(select(DoctorProfile).where(DoctorProfile.user_id == doctor_id).with_for_update())
    if profile is None:
        raise ApiError(404, "doctor_not_found")
    profile.price_dzd = body.price_dzd
    audit.record(db, "doctor.price", actor_id=admin.id, target=str(doctor_id), request=request)
    db.commit()
    return _out(profile)
