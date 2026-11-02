"""Spreadsheet exports for the super admin: administrative data only, never
clinical data, always audited."""

import csv
import io
from datetime import datetime

from sqlalchemy.orm import Session

from app.db import engine
from app.models import AppointmentStatus, AuditLog

from .booking_helpers import add_appointment, user_id, verified_patient
from .conftest import bearer
from .test_staff import doc_headers, doctor_with_password, make_super_admin

ADMIN = "admin@example.invalid"
PATIENTS = "/v1/admin/export/patients.csv"
APPOINTMENTS = "/v1/admin/export/appointments.csv"


def rows(r):
    assert r.content.startswith("﻿".encode())  # Excel reads Arabic as UTF-8
    return list(csv.reader(io.StringIO(r.content.decode("utf-8-sig"))))


def test_patients_sheet(client, sms):
    doctor_with_password()
    make_super_admin()
    verified_patient(client, sms)
    r = client.get(PATIENTS, headers=doc_headers(client, ADMIN))
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/csv")
    assert "attachment" in r.headers["content-disposition"]
    assert r.headers["cache-control"] == "no-store"
    header, *body = rows(r)
    assert header[:3] == ["patient_id", "phone", "email"]
    assert len(body) == 1
    assert body[0][0] == str(user_id())
    assert body[0][1] == "+213661234567"
    assert "password" in body[0][6]


def test_appointments_sheet_in_clinic_time(client, sms):
    doc = doctor_with_password()
    make_super_admin()
    verified_patient(client, sms)
    add_appointment(doc.user_id, user_id(), datetime(2026, 10, 19, 8, 0))
    add_appointment(doc.user_id, user_id(), datetime(2026, 10, 20, 8, 0),
                    status=AppointmentStatus.awaiting_payment, method=None)
    header, *body = rows(client.get(APPOINTMENTS, headers=doc_headers(client, ADMIN)))
    assert len(body) == 1  # the open hold is left out
    row = dict(zip(header, body[0]))
    assert (row["day"], row["time"]) == ("2026-10-19", "09:00")
    assert row["doctor"] == "Dr Benmahdia Hocine"
    assert row["status"] == "confirmed"


def test_no_clinical_columns():
    from app.routers.admin_export import APPOINTMENT_COLUMNS, PATIENT_COLUMNS

    clinical = ("addiction", "medication", "note", "alert", "chat", "craving", "relapse", "id_number", "selfie")
    for column in PATIENT_COLUMNS + APPOINTMENT_COLUMNS:
        assert not any(word in column for word in clinical), column


def test_every_export_is_audited(client, sms):
    doctor_with_password()
    admin = make_super_admin()
    h = doc_headers(client, ADMIN)
    client.get(PATIENTS, headers=h)
    client.get(APPOINTMENTS, headers=h)
    with Session(engine) as db:
        actions = [a.action for a in db.query(AuditLog).filter(AuditLog.actor_id == admin)]
    assert "export.patients" in actions
    assert "export.appointments" in actions


def test_only_the_super_admin(client, sms):
    doctor_with_password()
    for url in (PATIENTS, APPOINTMENTS):
        assert client.get(url).status_code == 401
        assert client.get(url, headers=doc_headers(client)).status_code == 403
    patient = verified_patient(client, sms)
    assert client.get(PATIENTS, headers=bearer(patient)).status_code == 403
