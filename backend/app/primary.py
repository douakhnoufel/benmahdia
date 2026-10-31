"""The patient's primary doctor: a label set once, at the first confirmed
booking. It never limits who reads a file or receives an alert."""

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .models import Appointment, PrimaryDoctor


def link(db: Session, appointment: Appointment) -> None:
    """Makes the appointment's doctor the patient's primary doctor, unless the
    patient already has one. Call it where an appointment becomes confirmed;
    the caller commits."""
    if db.get(PrimaryDoctor, appointment.patient_id) is not None:
        return
    try:
        # A savepoint, so a second confirmation racing this one cannot undo
        # the booking being confirmed.
        with db.begin_nested():
            db.add(PrimaryDoctor(patient_id=appointment.patient_id, doctor_id=appointment.doctor_id))
    except IntegrityError:
        pass
