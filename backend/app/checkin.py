"""Front-desk check-in codes.

A confirmed appointment carries a short code. The patient shows it at the
clinic (as text or a QR code) and the doctor's dashboard accepts it to mark
the patient as arrived. The code identifies one appointment and nothing else:
it holds no personal or medical data. It does not replace looking at the
patient's physical ID at the desk."""

import secrets

from sqlalchemy import select
from sqlalchemy.orm import Session

from .models import Appointment

# No 0, O, 1, I or L: easy to read aloud and to type from a phone screen.
ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
LENGTH = 6


def normalize(raw: str) -> str:
    """What the doctor typed, as stored: upper case, no spaces or dashes."""
    return "".join(ch for ch in raw.upper() if ch.isalnum())


def new_code(db: Session) -> str:
    """A fresh code nobody else has (31^6 possibilities, so a clash is
    practically impossible; it is still checked)."""
    for _ in range(20):
        code = "".join(secrets.choice(ALPHABET) for _ in range(LENGTH))
        if db.scalar(select(Appointment.id).where(Appointment.checkin_code == code)) is None:
            return code
    raise RuntimeError("could not generate a unique check-in code")


def issue(db: Session, appointment: Appointment) -> None:
    """Gives a newly confirmed appointment its code, once."""
    if appointment.checkin_code is None:
        appointment.checkin_code = new_code(db)
