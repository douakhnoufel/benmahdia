"""Tells the doctor about a booking change (PRD 4.4: "both sides are
notified"). The patient learns it in the app, which also schedules the 24 h
and 1 h reminders on the phone. An alert names the kind of event and the
patient, never medical content (PRD 9)."""

from sqlalchemy.orm import Session

from .models import Alert, Appointment

CONFIRMED = "booking_confirmed"
CANCELLED = "booking_cancelled"


def booking_alert(db: Session, a: Appointment, kind: str) -> None:
    db.add(Alert(doctor_id=a.doctor_id, patient_id=a.patient_id, type=kind))
