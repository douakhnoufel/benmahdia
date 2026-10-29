"""A patient's appointments as their doctor sees them in the patient file
(PRD 4.3: "doctor sees attendance rate per patient"), and the doctor's
private note after each visit.

Who has a visit when is booking data shared clinic-wide, so every doctor's
visits with this patient are listed; the file itself opens only for the
doctor's own patients. A note is clinical data: only the visit's own doctor
reads or writes it. It is encrypted at rest, never sent to the patient or the
AI, and never logged (the audit keeps the note id only)."""

import uuid

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit, idcrypto
from ..clock import clock
from ..db import get_db
from ..errors import ApiError
from ..models import Appointment, AppointmentNote, AppointmentStatus, DoctorProfile, PaymentMethod
from .doctors import utc_iso
from .medications import _own_patient
from .staff import _own, current_doctor

MAX_NOTE_CHARS = 5000
# A note follows a visit: one that started and was not cancelled.
_NOTABLE = (AppointmentStatus.confirmed, AppointmentStatus.completed, AppointmentStatus.no_show)

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
    # Only ever true on the doctor's own visits.
    has_note: bool = False


class NoteIn(BaseModel):
    # Empty (or only spaces) deletes the note.
    text: str = Field(max_length=MAX_NOTE_CHARS)


class NoteOut(BaseModel):
    text: str | None
    updated_at: str | None


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
    noted = set(
        db.scalars(
            select(AppointmentNote.appointment_id).where(
                AppointmentNote.doctor_id == doctor.user_id,
                AppointmentNote.appointment_id.in_([a.id for a in rows]),
            )
        )
    )
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
                has_note=a.doctor_id == doctor.user_id and a.id in noted,
            )
            for a in rows
        ],
    )


def _note_of(db: Session, a: Appointment) -> AppointmentNote | None:
    return db.scalar(select(AppointmentNote).where(AppointmentNote.appointment_id == a.id))


def _note_out(a: Appointment, note: AppointmentNote | None) -> NoteOut:
    if note is None:
        return NoteOut(text=None, updated_at=None)
    text = idcrypto.decrypt(note.text_enc, kind="note", owner=str(a.id)).decode()
    return NoteOut(text=text, updated_at=utc_iso(note.updated_at))


@router.get("/appointments/{appointment_id}/note", response_model=NoteOut)
def read_note(
    appointment_id: uuid.UUID,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> NoteOut:
    """The note of one of the doctor's own visits. Another doctor's visit
    looks unknown."""
    a = _own(db, doctor, appointment_id)
    return _note_out(a, _note_of(db, a))


@router.put("/appointments/{appointment_id}/note", response_model=NoteOut)
def write_note(
    appointment_id: uuid.UUID,
    body: NoteIn,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> NoteOut:
    """Saves the note after a visit; empty text deletes it."""
    a = _own(db, doctor, appointment_id)
    now = clock.now()
    if a.status not in _NOTABLE:
        raise ApiError(409, "not_notable")
    if a.start_utc > now:
        raise ApiError(409, "not_started")
    note = _note_of(db, a)
    text = body.text.strip()
    if not text:
        if note is not None:
            audit.record(db, "appointment.note_deleted", actor_id=doctor.user_id, target=str(note.id), request=request)
            db.delete(note)
            db.commit()
        return _note_out(a, None)
    if note is None:
        note = AppointmentNote(id=uuid.uuid4(), appointment_id=a.id, doctor_id=doctor.user_id, created_at=now)
        db.add(note)
    note.text_enc = idcrypto.encrypt(text.encode(), kind="note", owner=str(a.id))
    note.updated_at = now
    audit.record(db, "appointment.note_saved", actor_id=doctor.user_id, target=str(note.id), request=request)
    db.commit()
    return _note_out(a, note)
