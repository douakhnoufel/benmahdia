"""QA booking run 2026-10-25, security-isolation tester.

Checks the PRD 3 role matrix on booking routes: a patient sees only their own
appointments; doctors see every appointment and agenda in the clinic but
clinical data (medications, addictions, alerts) only for their own patients;
appointment responses carry no clinical fields; audit lines carry no medical
content, codes or ID numbers. Fake data only: test phones, seeded doctors,
neutral placeholder names for clinical rows.

A test marked xfail(strict=True) exposes a real bug (see
qa/booking/2026-10-25/security-isolation.md). When the bug is fixed the test
flips to failing; remove the marker then."""

import uuid
from datetime import date, datetime, timedelta, timezone

import jwt
import pytest
from sqlalchemy.orm import Session

from app import security
from app.chargily import Chargily, Checkout, get_chargily
from app.config import get_settings
from app.db import engine
from app.main import app
from app.models import (
    Addiction,
    AddictionType,
    Alert,
    Appointment,
    AppointmentStatus,
    AuditLog,
    DoctorProfile,
    Medication,
    Role,
    User,
)

from .booking_helpers import add_appointment, make_doctor, user_id, verified_patient
from .conftest import advance, bearer, register

PASSWORD = "qa-isolation-2026"
EMAIL_A = "dr.benmahdia@example.invalid"  # the seeded doctor
EMAIL_B = "qa.doctor.b@example.invalid"
EMAIL_ADMIN = "qa.admin@example.invalid"
PHONE_A = "0661234501"
PHONE_B = "0661234502"
SLOT = "2026-10-19T08:00:00Z"  # Monday 09:00 Algiers, outside the 24 h notice
MONDAY_9 = datetime(2026, 10, 19, 8, 0)
MONDAY_930 = datetime(2026, 10, 19, 8, 30)
TODAY_LATE = datetime(2026, 10, 17, 19, 0)  # frozen clinic day, 20:00 Algiers
RANDOM_ID = "6f1c2d3e-4b5a-4c6d-8e7f-0a1b2c3d4e5f"

# What a booking/agenda row may carry. Anything clinical is a leak.
CLINICAL_WORDS = ("note", "medication", "addiction", "relapse", "alert", "flag",
                  "diagnos", "chat", "conversation", "trigger", "severity", "dose")


# --- helpers ------------------------------------------------------------------


class FakeChargily(Chargily):
    def __init__(self) -> None:
        settings = get_settings().model_copy(update={"chargily_secret_key": "test_sk_qa_only"})
        super().__init__(settings, client=None)
        self.created: list[dict] = []

    def create_checkout(self, **kwargs) -> Checkout:
        self.created.append(kwargs)
        return Checkout(id=f"chk_qa_{len(self.created)}", url="https://pay.test/qa")


@pytest.fixture
def chargily(client):
    fake = FakeChargily()
    app.dependency_overrides[get_chargily] = lambda: fake
    return fake


def doctor_a() -> DoctorProfile:
    profile = make_doctor()
    with Session(engine) as db:
        db.get(User, profile.user_id).password_hash = security.hash_password(PASSWORD)
        db.commit()
    return profile


def staff_user(email: str, role: Role, with_profile: bool = True) -> uuid.UUID:
    with Session(engine) as db:
        user = User(role=role, email=email, password_hash=security.hash_password(PASSWORD))
        db.add(user)
        db.flush()
        if with_profile:
            db.add(DoctorProfile(user_id=user.id, name_ar="د. ب", name_fr="Dr QA B", price_dzd=1500))
        db.commit()
        return user.id


def staff_headers(client, email: str) -> dict:
    r = client.post("/v1/staff/login", json={"email": email, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return bearer(r.json())


def reply(r) -> tuple:
    return r.status_code, r.json()


def clinical_keys(obj) -> list[str]:
    """Every key in a JSON value that names clinical data."""
    found = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if any(w in k.lower() for w in CLINICAL_WORDS):
                found.append(k)
            found += clinical_keys(v)
    elif isinstance(obj, list):
        for v in obj:
            found += clinical_keys(v)
    return found


def two_patients(client, sms):
    a = verified_patient(client, sms, PHONE_A)
    b = verified_patient(client, sms, PHONE_B)
    return a, b, user_id(PHONE_A), user_id(PHONE_B)


def appointment_row(appointment_id) -> Appointment:
    with Session(engine) as db:
        a = db.get(Appointment, uuid.UUID(str(appointment_id)))
        db.expunge(a)
        return a


# --- R-64: patient A on patient B's appointment ---------------------------------

PATIENT_ROUTES = [
    ("delete", "/v1/appointments/{id}/hold", None),
    ("post", "/v1/appointments/{id}/confirm", {"method": "clinic"}),
    ("post", "/v1/appointments/{id}/cancel", None),
    ("post", "/v1/appointments/{id}/checkout", {"method": "cib"}),
]


@pytest.mark.parametrize("state", ["hold", "confirmed"])
@pytest.mark.parametrize("method,path,body", PATIENT_ROUTES)
def test_other_patients_appointment_looks_like_a_random_id(client, sms, chargily, method, path, body, state):
    doc = doctor_a()
    a, _, _, b_id = two_patients(client, sms)
    if state == "hold":
        theirs = add_appointment(doc.user_id, b_id, MONDAY_9, status=AppointmentStatus.awaiting_payment,
                                 hold_expires_at=datetime(2026, 10, 17, 18, 10), method=None)
    else:
        theirs = add_appointment(doc.user_id, b_id, MONDAY_9, checkin_code="QAB234")

    def call(appointment_id):
        kwargs = {"headers": bearer(a)}
        if body is not None:
            kwargs["json"] = body
        return getattr(client, method)(path.format(id=appointment_id), **kwargs)

    on_theirs, on_random = call(theirs.id), call(RANDOM_ID)
    assert reply(on_theirs) == reply(on_random) == (404, {"detail": {"code": "appointment_not_found"}})
    after = appointment_row(theirs.id)
    assert (after.status, after.patient_id, after.checkin_code) == (theirs.status, b_id, theirs.checkin_code)
    assert chargily.created == []


def test_patient_lists_never_show_other_patients(client, sms):
    doc = doctor_a()
    a, b, a_id, b_id = two_patients(client, sms)
    mine = add_appointment(doc.user_id, a_id, datetime(2026, 10, 14, 8, 0), status=AppointmentStatus.completed)
    theirs = add_appointment(doc.user_id, b_id, MONDAY_9, checkin_code="QAB234")
    listed = client.get("/v1/appointments", headers=bearer(a)).json()
    assert [x["id"] for x in listed] == [str(mine.id)]
    assert str(theirs.id) not in client.get("/v1/appointments", headers=bearer(a)).text
    follow = client.get("/v1/appointments/follow-up", headers=bearer(a)).json()
    assert follow["after"]["id"] == str(mine.id)
    assert "QAB234" not in str(listed) + str(follow)


# --- R-17: the patient calendar is free/busy only --------------------------------


def test_calendar_shows_free_busy_only(client, sms):
    doc = doctor_a()
    a, _, _, b_id = two_patients(client, sms)
    theirs = add_appointment(doc.user_id, b_id, MONDAY_9, checkin_code="QAB234")
    held = add_appointment(doc.user_id, b_id, datetime(2026, 10, 19, 8, 15),
                           status=AppointmentStatus.awaiting_payment,
                           hold_expires_at=datetime(2026, 10, 17, 18, 10), method=None)
    r = client.get(f"/v1/doctors/{doc.user_id}/calendar", headers=bearer(a))
    assert r.status_code == 200
    slots = {s["start"]: s for d in r.json()["days"] for s in d["slots"]}
    assert slots[SLOT] == {"start": SLOT, "free": False}
    assert slots["2026-10-19T08:15:00Z"]["free"] is False
    for d in r.json()["days"]:
        assert set(d) == {"day", "closure", "slots"}
        for s in d["slots"]:
            assert set(s) == {"start", "free"}
    for secret in (str(b_id), str(theirs.id), str(held.id), "+213661234502", "661234502", "QAB234"):
        assert secret not in r.text


# --- R-68: tokens and roles --------------------------------------------------------

STAFF_ROUTES = [
    ("get", "/v1/staff/agenda", None),
    ("post", "/v1/staff/checkin", {"code": "QAB234"}),
    ("post", f"/v1/staff/appointments/{RANDOM_ID}/status", {"status": "completed"}),
    ("post", f"/v1/staff/appointments/{RANDOM_ID}/paid", {"paid": True}),
    ("get", "/v1/staff/patients", None),
    ("get", f"/v1/staff/patients/{RANDOM_ID}/medications", None),
    ("get", f"/v1/staff/patients/{RANDOM_ID}/addictions", None),
    ("get", "/v1/staff/alerts", None),
    ("get", "/v1/staff/signups", None),
]

PATIENT_ONLY_ROUTES = [
    ("get", "/v1/appointments", None),
    ("get", "/v1/appointments/follow-up", None),
    ("post", "/v1/appointments/holds", {"doctor_id": RANDOM_ID, "start": SLOT}),
    ("post", f"/v1/appointments/{RANDOM_ID}/confirm", {"method": "clinic"}),
    ("post", f"/v1/appointments/{RANDOM_ID}/cancel", None),
    ("delete", f"/v1/appointments/{RANDOM_ID}/hold", None),
    ("post", f"/v1/appointments/{RANDOM_ID}/checkout", {"method": "cib"}),
    ("get", "/v1/doctors", None),
    ("get", f"/v1/doctors/{RANDOM_ID}/calendar", None),
]


def _call(client, method, path, body, headers):
    kwargs = {"headers": headers}
    if body is not None:
        kwargs["json"] = body
    return getattr(client, method)(path, **kwargs)


@pytest.mark.parametrize("method,path,body", STAFF_ROUTES)
def test_patient_token_is_refused_on_staff_routes(client, sms, method, path, body):
    doctor_a()
    a = verified_patient(client, sms, PHONE_A)
    r = _call(client, method, path, body, bearer(a))
    assert reply(r) == (403, {"detail": {"code": "forbidden"}})


@pytest.mark.parametrize("method,path,body", PATIENT_ONLY_ROUTES)
def test_doctor_token_is_refused_on_patient_routes(client, chargily, method, path, body):
    doctor_a()
    r = _call(client, method, path, body, staff_headers(client, EMAIL_A))
    assert reply(r) == (403, {"detail": {"code": "forbidden"}})


def _forged(secret: str = "not-the-server-secret-0000000000000000000000") -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode({"sub": str(uuid.uuid4()), "typ": "access", "iat": now,
                       "exp": now + timedelta(hours=1)}, secret, algorithm="HS256")


@pytest.mark.parametrize("method,path,body", STAFF_ROUTES + PATIENT_ONLY_ROUTES)
@pytest.mark.parametrize("token", [None, "garbage", "forged"])
def test_missing_garbage_or_forged_token_is_401(client, chargily, method, path, body, token):
    if token is None:
        headers = {}
    elif token == "garbage":
        headers = {"Authorization": "Bearer not.a.jwt"}
    else:
        headers = {"Authorization": f"Bearer {_forged()}"}
    r = _call(client, method, path, body, headers)
    assert r.status_code == 401
    assert r.json()["detail"]["code"] in ("not_authenticated", "token_invalid")


def test_expired_or_refresh_token_is_401(client, sms):
    doctor_a()
    a = verified_patient(client, sms, PHONE_A)
    doc = client.post("/v1/staff/login", json={"email": EMAIL_A, "password": PASSWORD}).json()
    # A refresh token is not an access token.
    r = client.get("/v1/appointments", headers={"Authorization": f"Bearer {a['refresh_token']}"})
    assert reply(r) == (401, {"detail": {"code": "token_invalid"}})
    advance(minutes=get_settings().access_token_minutes + 1)
    assert reply(client.get("/v1/appointments", headers=bearer(a))) == (401, {"detail": {"code": "token_invalid"}})
    assert reply(client.get("/v1/staff/agenda", headers=bearer(doc))) == (401, {"detail": {"code": "token_invalid"}})


# --- R-65 / R-66: doctors see clinic-wide booking data, never clinical fields --------


def test_doctor_sees_another_doctors_agenda(client, sms):
    doc = doctor_a()
    other = staff_user(EMAIL_B, Role.doctor)
    _, _, a_id, b_id = two_patients(client, sms)
    mine = add_appointment(doc.user_id, a_id, MONDAY_9)
    theirs = add_appointment(other, b_id, MONDAY_930)
    r = client.get("/v1/staff/agenda?day=2026-10-19", headers=staff_headers(client, EMAIL_A))
    assert r.status_code == 200
    assert {x["id"] for x in r.json()} == {str(mine.id), str(theirs.id)}


def test_agenda_and_checkin_replies_carry_no_clinical_fields(client, sms):
    doc = doctor_a()
    _, _, a_id, _ = two_patients(client, sms)
    with Session(engine) as db:
        db.add(Medication(patient_id=a_id, prescribed_by=doc.user_id, name="QA-ITEM", amount="1",
                          times=["08:00"], start_date=date(2026, 10, 1)))
        db.add(Addiction(patient_id=a_id, type=AddictionType.other, sobriety_start=datetime(2026, 9, 1)))
        db.add(Alert(doctor_id=doc.user_id, patient_id=a_id, type="relapse"))
        db.commit()
    add_appointment(doc.user_id, a_id, TODAY_LATE, checkin_code="QAC234")
    h = staff_headers(client, EMAIL_A)
    agenda = client.get("/v1/staff/agenda", headers=h)
    checked = client.post("/v1/staff/checkin", json={"code": "QAC234"}, headers=h)
    assert agenda.status_code == 200 and len(agenda.json()) == 1
    assert checked.status_code == 200
    # Whose visit it is (name and "mine") is booking data, shared clinic-wide.
    allowed = {"id", "patient_id", "patient_phone", "start", "end", "status", "method",
               "price_dzd", "paid", "checked_in_at", "doctor_name_ar", "doctor_name_fr", "mine"}
    assert set(agenda.json()[0]) <= allowed
    assert set(checked.json()) <= allowed
    assert clinical_keys(agenda.json()) == clinical_keys(checked.json()) == []
    assert "QA-ITEM" not in agenda.text + checked.text
    # The check-in code itself is not echoed back to the desk.
    assert "QAC234" not in agenda.text + checked.text


def test_patient_appointment_replies_carry_no_clinical_fields(client, sms):
    doc = doctor_a()
    a, _, a_id, _ = two_patients(client, sms)
    add_appointment(doc.user_id, a_id, MONDAY_9, checkin_code="QAA234")
    listed = client.get("/v1/appointments", headers=bearer(a)).json()
    assert listed and clinical_keys(listed) == []


# --- R-67: clinical data stays with the patient's own doctor ------------------------


def _clinical_rows(doctor_id, patient_id):
    with Session(engine) as db:
        med = Medication(patient_id=patient_id, prescribed_by=doctor_id, name="QA-ITEM", amount="1",
                         times=["08:00"], start_date=date(2026, 10, 1))
        add = Addiction(patient_id=patient_id, type=AddictionType.other, sobriety_start=datetime(2026, 9, 1))
        alert = Alert(doctor_id=doctor_id, patient_id=patient_id, type="relapse")
        db.add_all([med, add, alert])
        db.commit()
        return med.id, add.id, alert.id


def test_unrelated_doctor_cannot_reach_clinical_data(client, sms):
    """Doctor B has never seen patient A (A belongs to doctor A): every clinical
    route refuses, and the refusal equals the one for a random id."""
    doc = doctor_a()
    staff_user(EMAIL_B, Role.doctor)
    _, _, a_id, _ = two_patients(client, sms)
    add_appointment(doc.user_id, a_id, datetime(2026, 10, 14, 8, 0), status=AppointmentStatus.completed)
    med_id, add_id, alert_id = _clinical_rows(doc.user_id, a_id)
    hb = staff_headers(client, EMAIL_B)
    base = f"/v1/staff/patients/{a_id}"
    rand = f"/v1/staff/patients/{RANDOM_ID}"
    pairs = [
        (client.get(f"{base}/medications", headers=hb), client.get(f"{rand}/medications", headers=hb)),
        (client.post(f"{base}/medications", headers=hb,
                     json={"name": "QA-ITEM", "amount": "1", "times": ["08:00"], "start_date": "2026-10-17"}),
         client.post(f"{rand}/medications", headers=hb,
                     json={"name": "QA-ITEM", "amount": "1", "times": ["08:00"], "start_date": "2026-10-17"})),
        (client.delete(f"{base}/medications/{med_id}", headers=hb),
         client.delete(f"{rand}/medications/{med_id}", headers=hb)),
        (client.get(f"{base}/addictions", headers=hb), client.get(f"{rand}/addictions", headers=hb)),
        (client.post(f"{base}/addictions/{add_id}/confirm", headers=hb),
         client.post(f"{rand}/addictions/{add_id}/confirm", headers=hb)),
    ]
    for theirs, random in pairs:
        assert theirs.status_code == 404, theirs.text
        assert reply(theirs) == reply(random)
    r = client.post(f"/v1/staff/alerts/{alert_id}/read", headers=hb)
    assert r.status_code == 404
    assert reply(r) == reply(client.post(f"/v1/staff/alerts/{RANDOM_ID}/read", headers=hb))
    assert client.get("/v1/staff/alerts", headers=hb).json() == []
    assert str(a_id) not in client.get("/v1/staff/patients", headers=hb).text
    with Session(engine) as db:
        assert db.get(Medication, med_id).active is True


@pytest.mark.xfail(strict=True, reason="QA SEC-02: any doctor the patient booked once gets clinical access; PRD 3 has one primary doctor")
def test_one_booking_with_another_doctor_does_not_open_clinical_data(client, sms):
    """Booking data is clinic-wide, so a patient may book any doctor. With no
    sharing or transfer recorded, at most one doctor (the primary) may read the
    patient's medications and addictions — not every doctor they booked."""
    doc = doctor_a()
    other = staff_user(EMAIL_B, Role.doctor)
    _, _, a_id, _ = two_patients(client, sms)
    add_appointment(doc.user_id, a_id, datetime(2026, 10, 14, 8, 0), status=AppointmentStatus.completed)
    add_appointment(other, a_id, MONDAY_930)
    _clinical_rows(doc.user_id, a_id)
    readers = 0
    for email in (EMAIL_A, EMAIL_B):
        h = staff_headers(client, email)
        meds = client.get(f"/v1/staff/patients/{a_id}/medications", headers=h)
        adds = client.get(f"/v1/staff/patients/{a_id}/addictions", headers=h)
        readers += meds.status_code == 200 or adds.status_code == 200
    assert readers <= 1


# --- R-70: super admin ---------------------------------------------------------------


def test_super_admin_can_use_doctor_booking_screens(client, sms):
    doctor_a()
    staff_user(EMAIL_ADMIN, Role.super_admin)
    h = staff_headers(client, EMAIL_ADMIN)
    assert client.get("/v1/staff/agenda", headers=h).status_code == 200


def test_super_admin_cannot_read_another_doctors_patients_clinical_data(client, sms):
    doc = doctor_a()
    staff_user(EMAIL_ADMIN, Role.super_admin)
    _, _, a_id, _ = two_patients(client, sms)
    add_appointment(doc.user_id, a_id, datetime(2026, 10, 14, 8, 0), status=AppointmentStatus.completed)
    _clinical_rows(doc.user_id, a_id)
    h = staff_headers(client, EMAIL_ADMIN)
    for path in (f"/v1/staff/patients/{a_id}/medications", f"/v1/staff/patients/{a_id}/addictions"):
        r = client.get(path, headers=h)
        assert r.status_code in (403, 404)
        assert "QA-ITEM" not in r.text
    # The super admin is also a doctor (PRD §3): their own alert list, never the other doctor's.
    r = client.get("/v1/staff/alerts", headers=h)
    assert r.status_code in (200, 403, 404)
    assert r.status_code != 200 or r.json() == []


# --- R-62 / R-69: clinic staff -----------------------------------------------------------


@pytest.mark.xfail(strict=True, reason="QA SEC-04: no clinic-staff role exists; PRD 3 and 4.3 need one for ID review and front-desk check-in")
def test_a_clinic_staff_role_exists():
    staff_like = {"clinic_staff", "staff", "secretary", "receptionist", "front_desk"}
    assert staff_like & {r.value for r in Role}


@pytest.mark.xfail(strict=True, reason="QA SEC-05: a plain doctor approves ID declarations; PRD 3 gives that to clinic staff and super admin")
def test_a_plain_doctor_cannot_approve_an_id(client, sms):
    doctor_a()

    register(client, sms, PHONE_A)
    r = client.post(f"/v1/staff/signups/{user_id(PHONE_A)}/approve", headers=staff_headers(client, EMAIL_A))
    assert r.status_code == 403


# --- R-40: audit lines -------------------------------------------------------------------


def test_hold_confirm_cancel_checkin_are_audited_with_ids_only(client, sms):
    doc = doctor_a()
    a, _, a_id, _ = two_patients(client, sms)
    held = client.post("/v1/appointments/holds", headers=bearer(a),
                       json={"doctor_id": str(doc.user_id), "start": SLOT})
    assert held.status_code == 201, held.text
    appt = held.json()["id"]
    done = client.post(f"/v1/appointments/{appt}/confirm", json={"method": "clinic"}, headers=bearer(a))
    assert done.status_code == 200
    code = done.json()["checkin_code"]
    assert client.post(f"/v1/appointments/{appt}/cancel", headers=bearer(a)).status_code == 200
    today = add_appointment(doc.user_id, a_id, TODAY_LATE, checkin_code="QAC234")
    h = staff_headers(client, EMAIL_A)
    assert client.post("/v1/staff/checkin", json={"code": "QAWRNG"}, headers=h).status_code == 404
    assert client.post("/v1/staff/checkin", json={"code": "QAC234"}, headers=h).status_code == 200

    with Session(engine) as db:
        lines = db.query(AuditLog).all()
    by_action = {}
    for line in lines:
        by_action.setdefault(line.action, []).append(line.target)
    assert by_action["appointment.held"] == [appt]
    assert by_action["appointment.confirmed"] == [appt]
    assert by_action["appointment.cancelled"] == [appt]
    assert by_action["appointment.checked_in"] == [str(today.id)]
    assert by_action["checkin.failed"] == [None]
    for line in lines:
        # Booking lines target an id or nothing (auth lines use a method label
        # such as "phone"). Nowhere a code, phone, ID number or medical word.
        if line.action.startswith(("appointment.", "checkin.", "payment.")) and line.target is not None:
            uuid.UUID(line.target)
        text = f"{line.action} {line.target}"
        for secret in (code, "QAC234", "QAWRNG", "661234501", "QA-ITEM"):
            assert secret not in text
