"""A patient's appointments as their doctor sees them in the patient file
(PRD 4.3: "doctor sees attendance rate per patient"). Who has a visit when is
booking data shared clinic-wide, so every doctor's visits with this patient
are listed; the file itself opens only for the doctor's own patients."""

import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Appointment, AppointmentStatus, DoctorProfile, PaymentMethod
from .doctors import utc_iso
from .medications import _own_patient
from .staff import current_doctor

router = APIRouter(prefix="/v1/staff", tags=["staff"])


class VisitOut(BaseModel):
    id: uuid.UUID
    start: str
    end: str
    status: AppointmentStatus
    doctor_name_ar: str
    doctor_name_fr: str
    mine: bool
    paid: bool
    method: PaymentMethod | None
    price_dzd: int


class AttendanceOut(BaseModel):
    completed: int
    no_show: int
    # completed / (completed + no_show); None before the first past visit.
    rate: float | None


class HistoryOut(BaseModel):
    attendance: AttendanceOut
    # Newest first. Open holds are not appointments yet and are left out.
    appointments: list[VisitOut]


@router.get("/patients/{patient_id}/appointments", response_model=HistoryOut)
def patient_appointments(
    patient_id: uuid.UUID,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> HistoryOut:
    _own_patient(db, doctor, patient_id)
    rows = db.scalars(
        select(Appointment)
        .where(Appointment.patient_id == patient_id, Appointment.status != AppointmentStatus.awaiting_payment)
        .order_by(Appointment.start_utc.desc())
    ).all()
    doctors = {d.user_id: d for d in db.scalars(select(DoctorProfile))}
    completed = sum(a.status == AppointmentStatus.completed for a in rows)
    no_show = sum(a.status == AppointmentStatus.no_show for a in rows)
    return HistoryOut(
        attendance=AttendanceOut(
            completed=completed,
            no_show=no_show,
            rate=completed / (completed + no_show) if completed + no_show else None,
        ),
        appointments=[
            VisitOut(
                id=a.id,
                start=utc_iso(a.start_utc),
                end=utc_iso(a.end_utc),
                status=a.status,
                doctor_name_ar=doctors[a.doctor_id].name_ar,
                doctor_name_fr=doctors[a.doctor_id].name_fr,
                mine=a.doctor_id == doctor.user_id,
                paid=a.paid_at is not None,
                method=a.method,
                price_dzd=a.price_dzd,
            )
            for a in rows
        ],
    )
