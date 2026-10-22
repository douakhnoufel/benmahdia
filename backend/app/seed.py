"""Creates the pilot clinic's doctor with sample consultation hours.

    SEED_DOCTOR_PASSWORD=... python -m app.seed

Signs in to the dashboard as dr.benmahdia@example.invalid.

Safe to run twice. No real patient data: only the doctor shown in the app
(PRD 4.3) and his weekly hours; change them in the database or, later, the
dashboard."""

import os

from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import engine
from . import security
from .quotes_seed import seed_quotes
from .models import Availability, DoctorProfile, Role, User

# Closed on Fridays (weekday 4), 09:00-12:00 and 14:00-16:00 otherwise.
HOURS = [(9 * 60, 12 * 60), (14 * 60, 16 * 60)]
WEEKDAYS = [0, 1, 2, 3, 5, 6]


def seed(db: Session) -> DoctorProfile:
    email = "dr.benmahdia@example.invalid"
    user = db.scalar(select(User).where(User.email == email))
    if user is None:
        user = User(role=Role.doctor, email=email, language="ar")
        db.add(user)
        db.flush()
    # Dashboard sign-in: set SEED_DOCTOR_PASSWORD to (re)set it. Never commit it.
    password = os.environ.get("SEED_DOCTOR_PASSWORD")
    if password:
        user.password_hash = security.hash_password(password)
    profile = db.get(DoctorProfile, user.id)
    if profile is None:
        profile = DoctorProfile(
            user_id=user.id,
            name_ar="د. بن مهدية حسين",
            name_fr="Dr Benmahdia Hocine",
            slot_minutes=15,
            price_dzd=2000,
        )
        db.add(profile)
        db.flush()
        for weekday in WEEKDAYS:
            for start, end in HOURS:
                db.add(Availability(doctor_id=user.id, weekday=weekday, start_minute=start, end_minute=end))
    db.commit()
    seed_quotes(db)
    return profile


if __name__ == "__main__":
    with Session(engine) as session:
        print("doctor id:", seed(session).user_id)
