"""Spreadsheet exports for the super admin: the patient roster and the
appointments, as CSV that Excel opens directly (UTF-8 with a byte-order mark
so Arabic shows correctly).

Only administrative data leaves: no clinical data (addictions, medications,
daily checks, alerts, visit notes, AI chats), no ID numbers, no selfies.
Every export is written to the audit log (who and which sheet, no rows)."""

import csv
import io
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import audit, scheduling, tokens
from ..clock import clock
from ..db import get_db
from ..models import Appointment, AppointmentStatus, DoctorProfile, PrimaryDoctor, Role, User
from .admin import current_super_admin

router = APIRouter(prefix="/v1/admin/export", tags=["admin"])

PATIENT_COLUMNS = [
    "patient_id", "phone", "email", "language", "account_status", "id_status",
    "sign_in", "primary_doctor", "signed_up", "deleted",
]
APPOINTMENT_COLUMNS = [
    "appointment_id", "patient_id", "patient_phone", "doctor", "day", "time",
    "status", "price_dzd", "method", "paid", "checked_in", "next_follow_up_days",
]


def _local(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value.replace(tzinfo=timezone.utc).astimezone(scheduling.CLINIC_TZ)


def _stamp(value: datetime | None) -> str:
    local = _local(value)
    return local.strftime("%Y-%m-%d %H:%M") if local else ""


def _csv(name: str, header: list[str], rows: list[list[object]]) -> Response:
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\r\n")
    writer.writerow(header)
    writer.writerows([["" if v is None else v for v in row] for row in rows])
    day = scheduling.clinic_today(clock.now()).isoformat()
    return Response(
        content="﻿" + buffer.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={
            "Content-Disposition": f'attachment; filename="benmahdia-{name}-{day}.csv"',
            "Cache-Control": "no-store",
        },
    )


def _doctor_names(db: Session) -> dict:
    return {d.user_id: d.name_fr for d in db.scalars(select(DoctorProfile))}


@router.get("/patients.csv")
def export_patients(
    request: Request,
    admin: User = Depends(current_super_admin),
    db: Session = Depends(get_db),
) -> Response:
    """Every patient account, one row each."""
    doctors = _doctor_names(db)
    primary = {p.patient_id: p.doctor_id for p in db.scalars(select(PrimaryDoctor))}
    patients = db.scalars(select(User).where(User.role == Role.patient).order_by(User.created_at)).all()
    rows = [
        [
            str(u.id),
            u.phone,
            u.email,
            u.language,
            u.status.value,
            tokens.id_status(u),
            " ".join(sorted(({"password"} if u.password_hash else set()) | {i.provider.value for i in u.identities})),
            doctors.get(primary.get(u.id)),
            _stamp(u.created_at),
            _stamp(u.deleted_at),
        ]
        for u in patients
    ]
    audit.record(db, "export.patients", actor_id=admin.id, request=request)
    db.commit()
    return _csv("patients", PATIENT_COLUMNS, rows)


@router.get("/appointments.csv")
def export_appointments(
    request: Request,
    admin: User = Depends(current_super_admin),
    db: Session = Depends(get_db),
) -> Response:
    """Every appointment (open payment holds left out), oldest first."""
    doctors = _doctor_names(db)
    phones = dict(db.execute(select(User.id, User.phone).where(User.role == Role.patient)).all())
    appointments = db.scalars(
        select(Appointment)
        .where(Appointment.status != AppointmentStatus.awaiting_payment)
        .order_by(Appointment.start_utc)
    ).all()
    rows = []
    for a in appointments:
        start = _local(a.start_utc)
        rows.append([
            str(a.id),
            str(a.patient_id),
            phones.get(a.patient_id),
            doctors.get(a.doctor_id),
            start.strftime("%Y-%m-%d") if start else "",
            start.strftime("%H:%M") if start else "",
            a.status.value,
            a.price_dzd,
            a.method.value if a.method else None,
            "yes" if a.paid_at else "no",
            "yes" if a.checked_in_at else "no",
            a.next_follow_up_days,
        ])
    audit.record(db, "export.appointments", actor_id=admin.id, request=request)
    db.commit()
    return _csv("appointments", APPOINTMENT_COLUMNS, rows)
