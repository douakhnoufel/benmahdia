"""The patient's ID declaration, the doctor's review, and what is (not) stored."""

import base64
import os
import stat
from datetime import datetime
from pathlib import Path

import pytest
from sqlalchemy import text
from sqlalchemy.orm import Session

from app import idcrypto
from app.config import Settings, get_settings
from app.db import SessionLocal, engine
from app.models import AccountStatus, AuditLog, IdDeclaration, IdStatus, User
from app.purge import purge

from .booking_helpers import add_appointment, user_id, verified_patient
from .conftest import advance, bearer, register
from .test_staff import doc_headers, doctor_with_password, other_doctor

ID_NUMBER = "123456789012345678"          # made up
NAME = "Karim Benali"                     # made up
BIRTH = "1990-05-17"
MARKER = b"selfie-pixels-marker"
JPEG = b"\xff\xd8\xff\xe0" + MARKER * 10 + b"\xff\xd9"
IDENTITY = "/v1/me/identity"


def selfie_b64(data: bytes = JPEG) -> str:
    return base64.b64encode(data).decode()


def body(**override) -> dict:
    return {
        "id_number": ID_NUMBER,
        "full_name": NAME,
        "birth_date": BIRTH,
        "selfie_jpeg_base64": selfie_b64(),
    } | override


def declare(client, session, **override):
    return client.post(IDENTITY, json=body(**override), headers=bearer(session))


def files() -> list[Path]:
    return sorted(Path(get_settings().selfie_dir).glob("*.bin"))


def code(r) -> str:
    return r.json()["detail"]["code"]


def actions() -> list[str]:
    with Session(engine) as db:
        return [row.action for row in db.query(AuditLog).order_by(AuditLog.id)]


def reject(client, uid, reason="Photo floue"):
    return client.post(f"/v1/staff/signups/{uid}/reject", json={"reason": reason}, headers=doc_headers(client))


# --- declaring ----------------------------------------------------------------------


def test_a_patient_declares_their_id(client, sms):
    s = register(client, sms)
    assert client.get(IDENTITY, headers=bearer(s)).json() == {
        "status": "none", "declared_at": None, "reject_reason": None, "submissions_left": 4}
    r = declare(client, s)
    assert r.status_code == 201, r.text
    assert r.json() == {"status": "declared", "declared_at": "2026-10-17T18:00:00Z",
                        "reject_reason": None, "submissions_left": 3}
    assert client.get("/v1/me", headers=bearer(s)).json()["id_status"] == "declared"
    assert "identity.declared" in actions()


def test_nothing_readable_is_stored(client, sms):
    s = register(client, sms)
    declare(client, s)
    with Session(engine) as db:
        d = db.get(IdDeclaration, user_id())
        assert len(d.id_hmac) == 64 and d.id_hmac != ID_NUMBER
        stored = d.name_enc + d.birth_enc + d.id_hmac.encode()
        audit_text = " ".join(f"{a.action} {a.target}" for a in db.query(AuditLog))
        dump = " ".join(str(row) for t in ("users", "audit_log")
                        for row in db.execute(text(f"SELECT * FROM {t}")))
    for secret in (ID_NUMBER, NAME, "Benali", BIRTH):
        assert secret.encode() not in stored
        assert secret not in audit_text and secret not in dump
    [selfie_file] = files()
    raw = selfie_file.read_bytes()
    assert MARKER not in raw and not raw.startswith(b"\xff\xd8")     # encrypted, not a JPEG
    assert stat.S_IMODE(os.stat(selfie_file).st_mode) == 0o600


def test_the_same_card_gives_the_same_hmac_however_it_is_typed():
    assert idcrypto.id_hmac(idcrypto.normalize_id_number(" 1234 5678-9012.345678 ")) == \
        idcrypto.id_hmac(idcrypto.normalize_id_number(ID_NUMBER))
    assert idcrypto.normalize_id_number(" ab 12-cd ") == "AB12CD"


def test_ciphertext_cannot_be_moved_to_another_field_or_patient():
    blob = idcrypto.encrypt(b"Karim", kind="name", owner="u1")
    assert idcrypto.decrypt(blob, kind="name", owner="u1") == b"Karim"
    for kind, owner in (("birth", "u1"), ("name", "u2")):
        with pytest.raises(idcrypto.CryptoError):
            idcrypto.decrypt(blob, kind=kind, owner=owner)


@pytest.mark.parametrize("override,expected", [
    ({"id_number": "12"}, "invalid_id_number"),
    ({"id_number": "12 34 !!"}, "invalid_id_number"),
    ({"full_name": "1234"}, "invalid_name"),
    ({"full_name": "K"}, "invalid_name"),
    ({"birth_date": "2030-01-01"}, "invalid_birth_date"),
    ({"birth_date": "1800-01-01"}, "invalid_birth_date"),
    ({"selfie_jpeg_base64": "not base64!!"}, "invalid_selfie"),
    ({"selfie_jpeg_base64": selfie_b64(b"GIF89a-not-a-jpeg")}, "invalid_selfie"),
    ({"selfie_jpeg_base64": selfie_b64(b"\xff\xd8\xff" + b"x" * 2_100_000)}, "invalid_selfie"),
])
def test_bad_input_is_refused_and_nothing_is_kept(client, sms, override, expected):
    s = register(client, sms)
    r = declare(client, s, **override)
    assert (r.status_code, code(r)) == (422, expected)
    assert files() == []
    assert client.get(IDENTITY, headers=bearer(s)).json()["status"] == "none"


# --- who may declare ------------------------------------------------------------------


def test_only_a_signed_in_patient_who_is_not_approved_yet(client, sms):
    assert client.post(IDENTITY, json=body()).status_code == 401
    doctor_with_password()
    assert client.post(IDENTITY, json=body(), headers=doc_headers(client)).status_code == 403
    s = verified_patient(client, sms)
    r = declare(client, s)
    assert (r.status_code, code(r)) == (409, "already_approved")
    assert client.get(IDENTITY, headers=bearer(s)).json()["status"] == "approved"


def test_a_pending_declaration_cannot_be_replaced(client, sms):
    s = register(client, sms)
    declare(client, s)
    r = declare(client, s, full_name="Someone Else")
    assert (r.status_code, code(r)) == (409, "already_declared")
    assert len(files()) == 1


# --- duplicates -------------------------------------------------------------------------


def test_an_id_linked_to_another_account_is_refused_neutrally(client, sms):
    first = register(client, sms, "0661111111")
    second = register(client, sms, "0662222222")
    assert declare(client, first).status_code == 201
    r = declare(client, second, id_number=" 1234-5678 9012.345678 ")
    assert (r.status_code, code(r)) == (409, "id_already_linked")
    assert "Benali" not in r.text and "0661111111" not in r.text      # no hint about whose
    assert client.get(IDENTITY, headers=bearer(second)).json()["status"] == "none"
    assert len(files()) == 1                                             # no second selfie kept
    assert "identity.duplicate" in actions()
    # the clinic sees the attempt on the sign-ups page
    doctor_with_password()
    queue = {s["phone"]: s for s in client.get("/v1/staff/signups", headers=doc_headers(client)).json()}
    assert queue["+213662222222"]["duplicate_attempt"] is True
    assert queue["+213662222222"]["id_status"] == "none"
    assert queue["+213661111111"]["duplicate_attempt"] is False
    assert queue["+213661111111"]["id_status"] == "declared"


# --- passports -----------------------------------------------------------------------------

PASSPORT = "AB1234567"                    # made up


def test_a_patient_can_declare_a_passport_and_the_doctor_sees_which(client, sms):
    s = register(client, sms)
    r = declare(client, s, id_type="passport", id_number=" ab 1234567 ")
    assert r.status_code == 201, r.text
    with Session(engine) as db:
        d = db.query(IdDeclaration).one()
        assert d.id_type == "passport"
        assert d.id_hmac == idcrypto.id_hmac(PASSPORT, "passport")
        assert PASSPORT.encode() not in d.name_enc + d.birth_enc
    doctor_with_password()
    v = client.get(f"/v1/staff/signups/{user_id()}/identity", headers=doc_headers(client))
    assert v.json()["id_type"] == "passport"
    assert PASSPORT not in v.text


def test_the_same_passport_cannot_be_used_twice(client, sms):
    first = register(client, sms, "0661111111")
    second = register(client, sms, "0662222222")
    assert declare(client, first, id_type="passport", id_number=PASSPORT).status_code == 201
    r = declare(client, second, id_type="passport", id_number=PASSPORT.lower())
    assert (r.status_code, code(r)) == (409, "id_already_linked")


def test_a_passport_number_never_collides_with_an_id_card_number():
    assert idcrypto.id_hmac(PASSPORT, "passport") != idcrypto.id_hmac(PASSPORT)
    # national ID cards keep the HMAC of earlier versions
    assert idcrypto.id_hmac(ID_NUMBER, "national_id") == idcrypto.id_hmac(ID_NUMBER)


def test_an_unknown_document_type_is_refused(client, sms):
    s = register(client, sms)
    assert declare(client, s, id_type="driving_licence").status_code == 422


# --- the clinic's review -------------------------------------------------------------------


def test_the_doctor_sees_name_birth_date_and_selfie_and_every_view_is_logged(client, sms):
    s = register(client, sms)
    declare(client, s)
    doctor_with_password()
    h = doc_headers(client)
    uid = user_id()
    v = client.get(f"/v1/staff/signups/{uid}/identity", headers=h)
    assert v.status_code == 200, v.text
    assert v.json() == {"id_type": "national_id", "full_name": NAME, "birth_date": BIRTH,
                        "declared_at": "2026-10-17T18:00:00Z", "submissions": 1, "has_selfie": True}
    assert ID_NUMBER not in v.text
    img = client.get(f"/v1/staff/signups/{uid}/selfie", headers=h)
    assert img.status_code == 200 and img.content == JPEG
    assert img.headers["content-type"] == "image/jpeg" and img.headers["cache-control"] == "no-store"
    log = actions()
    assert log.count("identity.viewed") == 1 and log.count("selfie.viewed") == 1


def test_only_doctors_see_it(client, sms):
    s = register(client, sms)
    declare(client, s)
    uid = user_id()
    for path in (f"/v1/staff/signups/{uid}/identity", f"/v1/staff/signups/{uid}/selfie"):
        assert client.get(path).status_code == 401
        assert client.get(path, headers=bearer(s)).status_code == 403


def test_an_approved_patient_is_visible_only_to_their_own_doctor(client, sms):
    doc = doctor_with_password()
    other = other_doctor()
    s = register(client, sms)
    declare(client, s)
    uid = user_id()
    h = doc_headers(client)
    assert client.post(f"/v1/staff/signups/{uid}/approve", headers=h).status_code == 200
    assert client.get(f"/v1/staff/signups/{uid}/identity", headers=h).status_code == 404   # not their patient
    add_appointment(doc.user_id, uid, datetime(2026, 10, 19, 8, 0))
    assert client.get(f"/v1/staff/signups/{uid}/identity", headers=h).status_code == 200
    from .test_staff import PASSWORD, login
    h2 = bearer(login(client, "other@example.invalid", PASSWORD).json())
    assert client.get(f"/v1/staff/signups/{uid}/identity", headers=h2).status_code == 404
    assert other is not None


def test_unknown_or_undeclared_patients_are_not_found(client, sms):
    register(client, sms)
    doctor_with_password()
    h = doc_headers(client)
    assert client.get(f"/v1/staff/signups/{user_id()}/identity", headers=h).status_code == 404
    assert client.get("/v1/staff/signups/00000000-0000-0000-0000-000000000000/selfie", headers=h).status_code == 404


def test_approving_unlocks_booking(client, sms):
    s = register(client, sms)
    declare(client, s)
    assert client.get("/v1/doctors", headers=bearer(s)).status_code == 403          # locked until approved
    doctor_with_password()
    uid = user_id()
    assert client.post(f"/v1/staff/signups/{uid}/approve", headers=doc_headers(client)).status_code == 200
    with Session(engine) as db:
        d = db.get(IdDeclaration, uid)
        assert (d.status, db.get(User, uid).status) == (IdStatus.approved, AccountStatus.verified)
        assert d.decided_at is not None and d.decided_by is not None
    assert client.get("/v1/doctors", headers=bearer(s)).status_code == 200
    assert client.get("/v1/me", headers=bearer(s)).json()["id_status"] == "approved"
    assert len(files()) == 1                                                         # the doctor keeps the selfie


# --- rejecting and resubmitting -----------------------------------------------------------------


def test_rejecting_deletes_the_selfie_and_lets_the_patient_resubmit(client, sms):
    s = register(client, sms)
    declare(client, s)
    doctor_with_password()
    uid = user_id()
    r = reject(client, uid)
    assert r.status_code == 200 and r.json()["id_status"] == "rejected"
    assert files() == []
    mine = client.get(IDENTITY, headers=bearer(s)).json()
    assert (mine["status"], mine["reject_reason"], mine["submissions_left"]) == ("rejected", "Photo floue", 3)
    with Session(engine) as db:
        assert db.get(User, uid).status == AccountStatus.pending_verification         # not locked out
    assert client.get("/v1/staff/signups", headers=doc_headers(client)).json() == []   # waits for the patient
    again = declare(client, s, full_name="Karim Ben Ali")
    assert again.status_code == 201 and again.json()["status"] == "declared"
    assert again.json()["reject_reason"] is None and again.json()["submissions_left"] == 2
    assert len(files()) == 1
    v = client.get(f"/v1/staff/signups/{uid}/identity", headers=doc_headers(client)).json()
    assert (v["full_name"], v["submissions"]) == ("Karim Ben Ali", 2)


def test_a_patient_may_submit_four_times_in_all(client, sms):
    s = register(client, sms)
    doctor_with_password()
    uid = user_id()
    for _ in range(4):
        assert declare(client, s).status_code == 201
        assert reject(client, uid).status_code == 200
    r = declare(client, s)
    assert (r.status_code, code(r)) == (403, "too_many_submissions")
    assert client.get(IDENTITY, headers=bearer(s)).json()["submissions_left"] == 0


def test_a_reason_is_optional_but_not_endless(client, sms):
    register(client, sms)
    doctor_with_password()
    uid = user_id()
    h = doc_headers(client)
    assert client.post(f"/v1/staff/signups/{uid}/reject", json={"reason": "x" * 201}, headers=h).status_code == 422
    assert client.post(f"/v1/staff/signups/{uid}/reject", headers=h).status_code == 200   # no declaration: as before


# --- erasing ---------------------------------------------------------------------------------------


def test_purging_an_account_removes_its_selfie_file(client, sms):
    s = register(client, sms)
    declare(client, s)
    assert len(files()) == 1
    client.request("DELETE", "/v1/me", json={"password": "sobre2026"}, headers=bearer(s))
    advance(days=31)
    with SessionLocal() as db:
        assert purge(db) == 1
        assert db.query(IdDeclaration).count() == 0
    assert files() == []


# --- configuration -----------------------------------------------------------------------------------


def test_production_refuses_the_development_id_keys():
    with pytest.raises(ValueError, match="ID_HMAC_KEY"):
        Settings(_env_file=None, environment="production", sms_provider="gateway",
                 chargily_api_url="https://pay.chargily.net/api/v2", chargily_secret_key="live_sk_x",
                 jwt_secret="j" * 40, otp_secret="o" * 40)
