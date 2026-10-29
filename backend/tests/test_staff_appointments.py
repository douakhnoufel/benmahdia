from datetime import datetime, timedelta

import pytest

from app.clock import clock
from app.models import AppointmentStatus, PaymentMethod

from .booking_helpers import add_appointment, user_id, verified_patient
from .conftest import bearer
from .test_staff import doc_headers, doctor_with_password, other_doctor

OTHER = "other@example.invalid"


def url(patient_id):
    return f"/v1/staff/patients/{patient_id}/appointments"


@pytest.fixture
def patient(client, sms):
    session = verified_patient(client, sms)
    return session, user_id()


def test_lists_every_visit_newest_first_with_attendance(client, patient):
    doc = doctor_with_password()
    other = other_doctor()
    _, pid = patient
    add_appointment(doc.user_id, pid, datetime(2026, 9, 1, 8, 0), status=AppointmentStatus.completed)
    add_appointment(doc.user_id, pid, datetime(2026, 9, 15, 8, 0), status=AppointmentStatus.no_show)
    add_appointment(other, pid, datetime(2026, 10, 1, 8, 0), status=AppointmentStatus.completed,
                    method=PaymentMethod.cib)
    add_appointment(doc.user_id, pid, datetime(2026, 10, 5, 8, 0), status=AppointmentStatus.cancelled)
    upcoming = add_appointment(doc.user_id, pid, datetime(2026, 10, 20, 8, 0))
    # An open hold is not an appointment yet.
    add_appointment(doc.user_id, pid, datetime(2026, 10, 21, 8, 0), status=AppointmentStatus.awaiting_payment,
                    hold_expires_at=clock.now() + timedelta(minutes=10), method=None)
    r = client.get(url(pid), headers=doc_headers(client))
    assert r.status_code == 200
    body = r.json()
    assert body["attendance"] == {"completed": 2, "no_show": 1, "rate": pytest.approx(2 / 3)}
    visits = body["appointments"]
    assert [v["start"][:10] for v in visits] == ["2026-10-20", "2026-10-05", "2026-10-01", "2026-09-15", "2026-09-01"]
    assert visits[0] == {
        "id": str(upcoming.id), "start": "2026-10-20T08:00:00Z", "end": "2026-10-20T08:15:00Z",
        "status": "confirmed", "doctor_name_ar": "د. بن مهدية حسين", "doctor_name_fr": "Dr Benmahdia Hocine",
        "mine": True, "paid": False, "method": "clinic", "price_dzd": 2000, "has_note": False,
        "note_shared": False,
    }
    assert (visits[2]["mine"], visits[2]["doctor_name_fr"], visits[2]["method"]) == (False, "Dr Autre", "cib")


def test_no_rate_before_the_first_past_visit(client, patient):
    doc = doctor_with_password()
    _, pid = patient
    add_appointment(doc.user_id, pid, datetime(2026, 10, 20, 8, 0))
    body = client.get(url(pid), headers=doc_headers(client)).json()
    assert body["attendance"] == {"completed": 0, "no_show": 0, "rate": None}
    assert len(body["appointments"]) == 1


def test_open_to_every_doctor_for_a_clinic_patient(client, patient):
    doctor_with_password()
    other = other_doctor()
    _, pid = patient
    add_appointment(other, pid, datetime(2026, 10, 20, 8, 0))
    assert client.get(url(pid), headers=doc_headers(client)).status_code == 200
    assert client.get(url(pid), headers=doc_headers(client, OTHER)).status_code == 200
    r = client.get(url("00000000-0000-0000-0000-000000000000"), headers=doc_headers(client))
    assert r.status_code == 404


def test_needs_a_doctor(client, patient):
    doc = doctor_with_password()
    session, pid = patient
    add_appointment(doc.user_id, pid, datetime(2026, 10, 20, 8, 0))
    assert client.get(url(pid)).status_code == 401
    assert client.get(url(pid), headers=bearer(session)).status_code == 403
