"""Paid / unpaid status per appointment and receipts, for the clinic (PRD 4.4,
7: "Payments"). A doctor sees their own appointments; the super admin sees
every doctor's. Booking and money data only, no clinical content."""

import uuid
from datetime import date, timedelta

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import scheduling
from ..db import get_db
from ..errors import ApiError
from ..models import Appointment, AppointmentStatus, DoctorProfile, PaymentMethod, Role, User
from .appointments import ReceiptOut, build_receipt
from .doctors import utc_iso
from .staff import current_doctor

router = APIRouter(prefix="/v1/staff", tags=["staff"])

# About a quarter: enough for a monthly or quarterly check, small enough to stay fast.
MAX_RANGE_DAYS = 92
# Visits a patient owes money for while unpaid; a cancelled one owes nothing.
_OWED = (AppointmentStatus.confirmed, AppointmentStatus.completed, AppointmentStatus.no_show)


class PaymentRow(BaseModel):
    id: uuid.UUID
    start: str
    doctor_name_ar: str
    doctor_name_fr: str
    mine: bool
    patient_phone: str | None
    status: AppointmentStatus
    method: PaymentMethod | None
    price_dzd: int
    paid: bool
    paid_at: str | None


class Totals(BaseModel):
    paid_count: int
    paid_dzd: int
    unpaid_count: int
    unpaid_dzd: int


class PaymentsOut(BaseModel):
    rows: list[PaymentRow]
    totals: Totals


def _is_super_admin(db: Session, doctor: DoctorProfile) -> bool:
    return db.get(User, doctor.user_id).role == Role.super_admin


@router.get("/payments", response_model=PaymentsOut)
def payments(
    first: date = Query(alias="from"),
    last: date = Query(alias="to"),
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> PaymentsOut:
    """Appointments from [first] to [last] (clinic days, both included), oldest
    first, with what was paid and what is still owed."""
    if last < first:
        raise ApiError(400, "bad_range")
    if (last - first).days >= MAX_RANGE_DAYS:
        raise ApiError(400, "range_too_long")
    query = select(Appointment).where(
        Appointment.start_utc >= scheduling.to_utc(first, 0),
        Appointment.start_utc < scheduling.to_utc(last + timedelta(days=1), 0),
        Appointment.status != AppointmentStatus.awaiting_payment,
    )
    if not _is_super_admin(db, doctor):
        query = query.where(Appointment.doctor_id == doctor.user_id)
    found = db.scalars(query.order_by(Appointment.start_utc)).all()
    doctors = {d.user_id: d for d in db.scalars(select(DoctorProfile))}
    rows = []
    for a in found:
        patient = db.get(User, a.patient_id)
        rows.append(
            PaymentRow(
                id=a.id,
                start=utc_iso(a.start_utc),
                doctor_name_ar=doctors[a.doctor_id].name_ar,
                doctor_name_fr=doctors[a.doctor_id].name_fr,
                mine=a.doctor_id == doctor.user_id,
                patient_phone=patient.phone if patient else None,
                status=a.status,
                method=a.method,
                price_dzd=a.price_dzd,
                paid=a.paid_at is not None,
                paid_at=utc_iso(a.paid_at) if a.paid_at else None,
            )
        )
    paid = [r for r in rows if r.paid]
    owed = [r for r in rows if not r.paid and r.status in _OWED]
    return PaymentsOut(
        rows=rows,
        totals=Totals(
            paid_count=len(paid),
            paid_dzd=sum(r.price_dzd for r in paid),
            unpaid_count=len(owed),
            unpaid_dzd=sum(r.price_dzd for r in owed),
        ),
    )


@router.get("/appointments/{appointment_id}/receipt", response_model=ReceiptOut)
def receipt(
    appointment_id: uuid.UUID,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> ReceiptOut:
    """The receipt of a paid appointment: the doctor's own, or any for the
    super admin. Anything else looks unknown."""
    a = db.get(Appointment, appointment_id)
    if a is None or (a.doctor_id != doctor.user_id and not _is_super_admin(db, doctor)):
        raise ApiError(404, "appointment_not_found")
    return build_receipt(db, a)
