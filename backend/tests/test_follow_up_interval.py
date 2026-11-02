"""The doctor picks when the next visit should be (15, 30 or 60 days after the
last one) and the patient can book it only within two days of that day, so
never twice in the same week."""

from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.clock import clock
from app.db import engine
from app.models import Appointment, AppointmentStatus, AuditLog

from .booking_helpers import add_appointment, headers, user_id, verified_patient
from .conftest import bearer
from .test_appointments import hold
from .test_staff import doc_headers, doctor_with_password, other_doctor

# The last visit: Monday 2026-10-19, 09:00 in Algiers.
VISIT = datetime(2026, 10, 19, 8, 0)


def follow_up_url(appointment_id):
    return f"/v1/staff/appointments/{appointment_id}/follow-up"


def setup(client, sms):
    doc = doctor_with_password()
    session = verified_patient(client, sms)
    visit = add_appointment(doc.user_id, user_id(), VISIT)
    return doc, session, visit


def set_days(client, visit, days):
    return client.put(follow_up_url(visit.id), json={"days": days}, headers=doc_headers(client))


def code(r):
    return r.json()["detail"]["code"]


# --- Booking window ------------------------------------------------------------


def test_the_first_booking_is_free(client, sms):
    doc = doctor_with_password()
    session = verified_patient(client, sms)
    assert hold(client, session, doc).status_code == 201


def test_default_follow_up_is_bookable_two_days_around_day_30(client, sms):
    doc, session, _ = setup(client, sms)
    # Target Wed 2026-11-18; Mon 11-16 is two days early.
    assert hold(client, session, doc, "2026-11-16T08:00:00Z").status_code == 201


def test_a_second_visit_in_the_same_week_is_refused(client, sms):
    doc, session, _ = setup(client, sms)
    r = hold(client, session, doc, "2026-10-21T08:00:00Z")
    assert (r.status_code, code(r)) == (409, "outside_follow_up_window")
    assert r.json()["detail"]["day"] == "2026-11-18"
    assert r.json()["detail"]["window_days"] == 2


def test_three_days_off_the_target_is_refused(client, sms):
    doc, session, _ = setup(client, sms)
    r = hold(client, session, doc, "2026-11-21T08:00:00Z")  # Sat, target + 3
    assert (r.status_code, code(r)) == (409, "outside_follow_up_window")


def test_high_risk_15_days_moves_the_window(client, sms):
    doc, session, visit = setup(client, sms)
    assert set_days(client, visit, 15).status_code == 200
    # Target Tue 2026-11-03.
    assert hold(client, session, doc, "2026-10-31T08:00:00Z").status_code == 409  # target - 3
    assert hold(client, session, doc, "2026-11-05T08:00:00Z").status_code == 201  # target + 2


def test_window_follows_the_latest_booked_visit(client, sms):
    doc, session, _ = setup(client, sms)
    later = add_appointment(doc.user_id, user_id(), datetime(2026, 10, 26, 8, 0))
    assert later is not None
    # 30 days after Mon 10-26 is Wed 11-25; 11-18 is now too early.
    assert hold(client, session, doc, "2026-11-18T08:00:00Z").status_code == 409
    assert hold(client, session, doc, "2026-11-25T08:00:00Z").status_code == 201


def test_a_missed_window_reopens_booking(client, sms):
    doc = doctor_with_password()
    session = verified_patient(client, sms)
    # Visit 40 days ago: target was 10 days ago, window long gone.
    add_appointment(doc.user_id, user_id(), clock.now() - timedelta(days=40))
    assert hold(client, session, doc).status_code == 201


def test_cancelled_visits_do_not_count(client, sms):
    doc = doctor_with_password()
    session = verified_patient(client, sms)
    add_appointment(doc.user_id, user_id(), VISIT, status=AppointmentStatus.cancelled)
    assert hold(client, session, doc, "2026-10-21T08:00:00Z").status_code == 201


# --- GET /v1/appointments/follow-up ----------------------------------------------


def test_follow_up_reports_the_doctors_interval_and_window(client, sms):
    _, session, visit = setup(client, sms)
    r = client.get("/v1/appointments/follow-up", headers=headers(session)).json()
    assert (r["day"], r["days"], r["window_days"]) == ("2026-11-18", 30, 2)
    assert set_days(client, visit, 60).status_code == 200
    r = client.get("/v1/appointments/follow-up", headers=headers(session)).json()
    assert (r["day"], r["days"]) == ("2026-12-18", 60)


# --- PUT /v1/staff/appointments/{id}/follow-up -------------------------------------


def test_doctor_sets_the_interval_and_it_is_audited(client, sms):
    _, _, visit = setup(client, sms)
    r = set_days(client, visit, 15)
    assert r.status_code == 200
    assert r.json() == {"appointment_id": str(visit.id), "next_follow_up_days": 15}
    with Session(engine) as db:
        assert db.get(Appointment, visit.id).next_follow_up_days == 15
        assert db.query(AuditLog).filter(AuditLog.action == "appointment.follow_up_set").count() == 1


def test_only_15_30_or_60_days(client, sms):
    _, _, visit = setup(client, sms)
    for days in (0, 7, 20, 45, 90):
        assert set_days(client, visit, days).status_code == 422


def test_an_open_hold_has_no_follow_up(client, sms):
    doc = doctor_with_password()
    verified_patient(client, sms)
    h = add_appointment(doc.user_id, user_id(), VISIT, status=AppointmentStatus.awaiting_payment,
                        hold_expires_at=clock.now() + timedelta(minutes=10), method=None)
    r = set_days(client, h, 15)
    assert (r.status_code, code(r)) == (409, "not_followable")


def test_only_the_visits_own_doctor_sets_it(client, sms):
    _, _, visit = setup(client, sms)
    other_doctor()
    r = client.put(follow_up_url(visit.id), json={"days": 15},
                   headers=doc_headers(client, "other@example.invalid"))
    assert r.status_code == 404
    with Session(engine) as db:
        assert db.get(Appointment, visit.id).next_follow_up_days is None


def test_a_patient_cannot_set_it(client, sms):
    _, session, visit = setup(client, sms)
    assert client.put(follow_up_url(visit.id), json={"days": 15}).status_code == 401
    r = client.put(follow_up_url(visit.id), json={"days": 15}, headers=bearer(session))
    assert r.status_code == 403
