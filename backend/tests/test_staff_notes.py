from datetime import datetime

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings
from app.db import engine
from app.models import AppointmentNote, AppointmentStatus, AuditLog

from .booking_helpers import add_appointment, user_id, verified_patient
from .conftest import bearer
from .test_staff import doc_headers, doctor_with_password, other_doctor

# Clock: Saturday 2026-10-17 18:00 UTC.
LAST_MONDAY = datetime(2026, 10, 12, 8, 0)
NEXT_TUESDAY = datetime(2026, 10, 20, 8, 0)
TEXT = "Sevrage bien toléré, revoir le sommeil."


def note_url(appointment_id):
    return f"/v1/staff/appointments/{appointment_id}/note"


@pytest.fixture
def visit(client, sms):
    """A doctor, a patient and a visit that took place last Monday."""
    doc = doctor_with_password()
    session = verified_patient(client, sms)
    a = add_appointment(doc.user_id, user_id(), LAST_MONDAY, status=AppointmentStatus.completed)
    return doc, session, a


def history(client, headers=None):
    r = client.get(f"/v1/staff/patients/{user_id()}/appointments", headers=headers or doc_headers(client))
    return r.json()["appointments"]


def test_write_and_read_a_note(client, visit):
    _, _, a = visit
    h = doc_headers(client)
    assert client.get(note_url(a.id), headers=h).json() == {"text": None, "updated_at": None, "shared": False, "mine": True}
    r = client.put(note_url(a.id), json={"text": f"  {TEXT}  "}, headers=h)
    assert r.status_code == 200, r.text
    assert r.json() == {"text": TEXT, "updated_at": "2026-10-17T18:00:00Z", "shared": False, "mine": True}
    assert client.get(note_url(a.id), headers=h).json()["text"] == TEXT
    assert history(client, h)[0]["has_note"] is True


def test_the_note_is_encrypted_at_rest(client, visit):
    _, _, a = visit
    client.put(note_url(a.id), json={"text": TEXT}, headers=doc_headers(client))
    with Session(engine) as db:
        [note] = db.scalars(select(AppointmentNote)).all()
    assert TEXT.encode() not in note.text_enc
    assert b"Sevrage" not in note.text_enc


def test_update_then_delete_with_empty_text(client, visit):
    _, _, a = visit
    h = doc_headers(client)
    client.put(note_url(a.id), json={"text": "Premier jet"}, headers=h)
    assert client.put(note_url(a.id), json={"text": TEXT}, headers=h).json()["text"] == TEXT
    with Session(engine) as db:
        assert db.query(AppointmentNote).count() == 1
    assert client.put(note_url(a.id), json={"text": "   "}, headers=h).json() == {"text": None, "updated_at": None, "shared": False, "mine": True}
    with Session(engine) as db:
        assert db.query(AppointmentNote).count() == 0
    assert history(client, h)[0]["has_note"] is False
    # Deleting what is not there is fine.
    assert client.put(note_url(a.id), json={"text": ""}, headers=h).status_code == 200


def test_a_private_note_is_only_for_the_visits_own_doctor(client, visit):
    _, _, a = visit
    other = other_doctor()
    client.put(note_url(a.id), json={"text": TEXT}, headers=doc_headers(client))
    # The other doctor also sees this patient, yet not the note of a visit that is not theirs.
    add_appointment(other, user_id(), datetime(2026, 10, 13, 8, 0), status=AppointmentStatus.completed)
    theirs = doc_headers(client, "other@example.invalid")
    for r in (client.get(note_url(a.id), headers=theirs),
              client.put(note_url(a.id), json={"text": "x"}, headers=theirs)):
        assert (r.status_code, r.json()["detail"]["code"]) == (404, "appointment_not_found")
    assert TEXT not in str(history(client, theirs))
    assert [v["has_note"] for v in history(client, theirs)] == [False, False]
    assert client.get(note_url(a.id), headers=doc_headers(client)).json()["text"] == TEXT


def test_a_shared_note_is_read_only_for_the_other_doctors(client, visit):
    _, _, a = visit
    other = other_doctor()
    mine = doc_headers(client)
    add_appointment(other, user_id(), datetime(2026, 10, 13, 8, 0), status=AppointmentStatus.completed)
    theirs = doc_headers(client, "other@example.invalid")
    r = client.put(note_url(a.id), json={"text": TEXT, "shared": True}, headers=mine)
    assert r.json()["shared"] is True
    seen = client.get(note_url(a.id), headers=theirs).json()
    assert (seen["text"], seen["shared"], seen["mine"]) == (TEXT, True, False)
    assert client.put(note_url(a.id), json={"text": "x"}, headers=theirs).status_code == 404
    flags = {v["id"]: (v["has_note"], v["note_shared"]) for v in history(client, theirs)}
    assert flags[str(a.id)] == (True, True)
    with Session(engine) as db:
        assert db.scalar(select(AuditLog).where(AuditLog.action == "appointment.note_read")) is not None
    # Taking the share back makes it private again.
    client.put(note_url(a.id), json={"text": TEXT, "shared": False}, headers=mine)
    assert client.get(note_url(a.id), headers=theirs).status_code == 404


def test_opening_a_colleagues_patient_file_is_audited_by_id_only(client, visit):
    _, _, a = visit
    other = other_doctor()
    client.get(f"/v1/staff/patients/{user_id()}/medications", headers=doc_headers(client, "other@example.invalid"))
    client.get(f"/v1/staff/patients/{user_id()}/medications", headers=doc_headers(client))
    with Session(engine) as db:
        rows = db.scalars(select(AuditLog).where(AuditLog.action == "patient_file.opened")).all()
    assert [str(r.target) for r in rows] == [str(user_id())]
    assert str(rows[0].actor_id) == str(other)


def test_needs_a_doctor(client, visit):
    _, session, a = visit
    assert client.get(note_url(a.id)).status_code == 401
    assert client.get(note_url(a.id), headers=bearer(session)).status_code == 403
    assert client.put(note_url(a.id), json={"text": TEXT}, headers=bearer(session)).status_code == 403


def test_only_after_a_visit_that_took_place(client, visit):
    doc, _, _ = visit
    h = doc_headers(client)
    future = add_appointment(doc.user_id, user_id(), NEXT_TUESDAY)
    cancelled = add_appointment(doc.user_id, user_id(), datetime(2026, 10, 13, 8, 0), status=AppointmentStatus.cancelled)
    r = client.put(note_url(future.id), json={"text": TEXT}, headers=h)
    assert (r.status_code, r.json()["detail"]["code"]) == (409, "not_started")
    r = client.put(note_url(cancelled.id), json={"text": TEXT}, headers=h)
    assert (r.status_code, r.json()["detail"]["code"]) == (409, "not_notable")
    # A no-show can still get a note.
    no_show = add_appointment(doc.user_id, user_id(), datetime(2026, 10, 14, 8, 0), status=AppointmentStatus.no_show)
    assert client.put(note_url(no_show.id), json={"text": TEXT}, headers=h).status_code == 200


def test_length_limit(client, visit):
    _, _, a = visit
    h = doc_headers(client)
    assert client.put(note_url(a.id), json={"text": "x" * 5001}, headers=h).status_code == 422
    assert client.put(note_url(a.id), json={"text": "x" * 5000}, headers=h).status_code == 200


def test_the_patient_never_sees_the_note(client, visit):
    _, session, a = visit
    client.put(note_url(a.id), json={"text": TEXT}, headers=doc_headers(client))
    for path in ("/v1/appointments", "/v1/appointments/follow-up", "/v1/me"):
        r = client.get(path, headers=bearer(session))
        assert r.status_code == 200, path
        assert "Sevrage" not in r.text and "note" not in r.text.lower(), path


def test_audit_keeps_the_note_id_only(client, visit):
    doc, _, a = visit
    h = doc_headers(client)
    client.put(note_url(a.id), json={"text": TEXT}, headers=h)
    client.put(note_url(a.id), json={"text": ""}, headers=h)
    with Session(engine) as db:
        rows = db.scalars(select(AuditLog).where(AuditLog.action.like("appointment.note%"))).all()
    assert [r.action for r in rows] == ["appointment.note_saved", "appointment.note_deleted"]
    assert rows[0].target == rows[1].target
    assert all(r.actor_id == doc.user_id and "Sevrage" not in (r.target or "") for r in rows)


def test_production_refuses_the_development_notes_key():
    live = dict(_env_file=None, environment="production", sms_provider="gateway",
                chargily_api_url="https://pay.chargily.net/api/v2", chargily_secret_key="live_sk_x",
                jwt_secret="j" * 40, otp_secret="o" * 40, id_hmac_key="h" * 40, id_data_key="d" * 40,
                selfie_key="s" * 40)
    with pytest.raises(ValueError, match="NOTES_KEY"):
        Settings(**live)
    assert Settings(**live, notes_key="n" * 40).production
