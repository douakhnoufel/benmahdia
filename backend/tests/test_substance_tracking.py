"""Per-substance tracking (PRD 5.6): profiles, per-addiction daily checks,
the doctor's chart and profile correction, and the craving / missed-check
alerts."""

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.alerts_job import craving_alerts, no_checkin_alerts
from app.db import engine
from app.models import AuditLog

from .booking_helpers import make_doctor
from .conftest import advance, bearer, register
from .test_medications import linked_patient, staff_session, unlocked
from .test_staff import login, other_doctor

TODAY = "2026-10-17"  # frozen clock: 2026-10-17 18:00 UTC
CLEAN_SINCE = "2026-10-07T18:00:00Z"
NICOTINE = {"irritability": 3, "restlessness": 2}


def setup(client, sms, phone="0661234567"):
    doctor = make_doctor()
    doc = staff_session(client, doctor) | {"doctor": doctor}
    return doc, linked_patient(client, sms, doctor, phone)


def later(client, s, days=1, doc=None):
    """Moves the clock on; access tokens expire, so the sessions refresh."""
    advance(days=days)
    r = client.post("/v1/auth/refresh", json={"refresh_token": s["refresh_token"]})
    assert r.status_code == 200, r.text
    s.update(r.json())
    if doc is not None:
        doc.update(staff_session(client, doc["doctor"]))


def add(client, s, **over):
    body = {"profile": "nicotine", "clean_since": CLEAN_SINCE} | over
    return client.post("/v1/me/addictions", json=body, headers=bearer(s))


def check(client, s, a, day=TODAY, **over):
    body = {"used": False, "craving": 2, "signals": NICOTINE} | over
    return client.put(f"/v1/me/addictions/{a['id']}/checks/{day}", json=body, headers=bearer(s))


def checks(client, s, **params):
    return client.get("/v1/me/addiction-checks", params=params, headers=bearer(s))


# --- Profiles -------------------------------------------------------------


def test_profiles_need_an_unlocked_patient(client, sms):
    assert client.get("/v1/me/recovery/profiles").status_code == 401
    s = register(client, sms)
    r = client.get("/v1/me/recovery/profiles", headers=bearer(s))
    assert r.status_code == 403 and r.json()["detail"]["code"] == "recovery_locked"


def test_profiles_catalog(client, sms):
    _, s = setup(client, sms)
    r = client.get("/v1/me/recovery/profiles", headers=bearer(s))
    assert r.status_code == 200
    by_key = {p["key"]: p for p in r.json()}
    assert set(by_key) == {"nicotine", "thc", "pregabalin", "buprenorphine", "cocaine", "amphetamines"}
    assert by_key["cocaine"]["type"] == by_key["amphetamines"]["type"] == "stimulants"
    assert by_key["buprenorphine"]["type"] == "opioids"
    assert [x["key"] for x in by_key["nicotine"]["signals"]] == ["irritability", "restlessness"]
    for p in by_key.values():
        assert len(p["signals"]) == 2 and p["notes"]
        assert p["name"]["ar"] and p["name"]["fr"]
        assert all(sig["label"]["ar"] and sig["label"]["fr"] for sig in p["signals"])


def test_doctor_reads_the_catalog_too(client, sms):
    doc, s = setup(client, sms)
    assert len(client.get("/v1/staff/recovery/profiles", headers=bearer(doc)).json()) == 6
    assert client.get("/v1/staff/recovery/profiles", headers=bearer(s)).status_code == 403


# --- Adding with a profile ------------------------------------------------


def test_profile_sets_the_type(client, sms):
    _, s = setup(client, sms)
    r = add(client, s, profile="pregabalin")
    assert r.status_code == 201, r.text
    assert r.json()["profile"] == "pregabalin" and r.json()["type"] == "pills"
    assert add(client, s, profile="cocaine", type="stimulants").json()["type"] == "stimulants"


def test_profile_and_type_must_agree(client, sms):
    _, s = setup(client, sms)
    assert add(client, s, profile="thc", type="tobacco").status_code == 422
    assert add(client, s, profile=None).status_code == 422  # neither
    assert add(client, s, profile="heroin").status_code == 422


def test_generic_addiction_has_no_profile(client, sms):
    _, s = setup(client, sms)
    r = add(client, s, profile=None, type="gambling")
    assert r.status_code == 201 and r.json()["profile"] is None


# --- Daily checks ---------------------------------------------------------


def test_save_and_list_a_check(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    assert check(client, s, a, craving=4).status_code == 204
    body = checks(client, s).json()
    assert body["checks"] == [{"addiction_id": a["id"], "day": TODAY, "used": False,
                               "craving": 4, "signals": NICOTINE}]
    assert body["done_days"] == [TODAY]


def test_signals_must_match_the_profile(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    bad = [
        {},  # missing
        {"irritability": 3},  # one missing
        {"irritability": 3, "restlessness": 2, "sleep": 1},  # extra
        {"irritability": 6, "restlessness": 2},  # out of range
        {"sleep": 3, "anxiety": 2},  # another profile's
    ]
    for signals in bad:
        r = check(client, s, a, signals=signals)
        assert r.status_code == 422 and r.json()["detail"]["code"] == "signals_mismatch", signals
    assert check(client, s, a, craving=0).status_code == 422
    assert check(client, s, a, craving=6).status_code == 422


def test_generic_check_rates_craving_only(client, sms):
    _, s = setup(client, sms)
    a = add(client, s, profile=None, type="alcohol").json()
    assert check(client, s, a, signals={"irritability": 2}).status_code == 422
    assert check(client, s, a, signals={}).status_code == 204


def test_day_must_be_recent(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    assert check(client, s, a, day="2026-10-15").status_code == 204  # two days back
    for day in ("2026-10-14", "2026-10-19"):
        r = check(client, s, a, day=day)
        assert r.status_code == 422 and r.json()["detail"]["code"] == "checkin_day_out_of_range"


def test_editable_the_same_day_only(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    check(client, s, a, craving=2)
    assert check(client, s, a, craving=5).status_code == 204
    assert checks(client, s).json()["checks"][0]["craving"] == 5
    later(client, s)
    r = check(client, s, a, day=TODAY, craving=1)
    assert r.status_code == 409 and r.json()["detail"]["code"] == "check_locked"


def test_used_does_not_restart_the_counter_by_itself(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    assert check(client, s, a, used=True).status_code == 204
    [after] = client.get("/v1/me/addictions", headers=bearer(s)).json()
    assert after["clean_since"] == CLEAN_SINCE and after["past_days"] == 0


def test_day_is_done_when_every_addiction_was_checked(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    b = add(client, s, profile="thc").json()
    check(client, s, a)
    assert checks(client, s).json()["done_days"] == []
    check(client, s, b, signals={"sleep": 2, "irritability": 1})
    assert checks(client, s).json()["done_days"] == [TODAY]


def test_rejected_addiction_cannot_be_checked(client, sms):
    doc, s = setup(client, sms)
    a = add(client, s).json()
    client.post(f"/v1/staff/patients/{s['user']['id']}/addictions/{a['id']}/reject", headers=bearer(doc))
    assert check(client, s, a).status_code == 404
    assert checks(client, s).json() == {"checks": [], "done_days": []}


def test_patient_reaches_only_own_addictions(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    check(client, s, a)
    _, other = setup(client, sms, "0771234567")
    assert check(client, other, a).status_code == 404
    assert checks(client, other).json()["checks"] == []


def test_staff_cannot_use_patient_routes(client, sms):
    doc, s = setup(client, sms)
    a = add(client, s).json()
    assert check(client, doc, a).status_code == 403
    assert checks(client, doc).status_code == 403


def test_answers_never_reach_the_audit_log(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    check(client, s, a, craving=5)
    with Session(engine) as db:
        rows = db.scalars(select(AuditLog)).all()
    text = " ".join(f"{r.action} {r.target}" for r in rows)
    assert "craving" not in text and "irritability" not in text and "nicotine" not in text


# --- Doctor ---------------------------------------------------------------


def test_doctor_sees_the_chart(client, sms):
    doc, s = setup(client, sms)
    a = add(client, s).json()
    check(client, s, a, day="2026-10-16", craving=3)
    check(client, s, a, craving=4)
    url = f"/v1/staff/patients/{s['user']['id']}/addictions/{a['id']}/checks"
    body = client.get(url, headers=bearer(doc)).json()
    assert body["days"] == 30 and body["checked_days"] == 2
    assert [c["craving"] for c in body["checks"]] == [3, 4]
    assert client.get(url, params={"days": 1}, headers=bearer(doc)).json()["checked_days"] == 1
    assert client.get(url, params={"days": 0}, headers=bearer(doc)).status_code == 422
    assert client.get(url, params={"days": 91}, headers=bearer(doc)).status_code == 422


def test_doctor_corrects_the_profile(client, sms):
    doc, s = setup(client, sms)
    a = add(client, s, profile="thc").json()
    url = f"/v1/staff/patients/{s['user']['id']}/addictions/{a['id']}/profile"
    r = client.put(url, json={"profile": "cocaine"}, headers=bearer(doc))
    assert r.status_code == 200, r.text
    assert r.json()["profile"] == "cocaine" and r.json()["type"] == "stimulants"
    # The patient's next check asks the new profile's signals.
    assert check(client, s, a, signals={"low_mood": 2, "low_energy": 3}).status_code == 204
    # Back to generic: the type stays.
    r = client.put(url, json={"profile": None}, headers=bearer(doc))
    assert r.json()["profile"] is None and r.json()["type"] == "stimulants"
    with Session(engine) as db:
        [row] = db.scalars(select(AuditLog).where(AuditLog.action == "addiction.profile_set").limit(1))
    assert row.target == a["id"]


def test_profile_list_includes_profile_for_doctor(client, sms):
    doc, s = setup(client, sms)
    add(client, s, profile="buprenorphine")
    [row] = client.get(f"/v1/staff/patients/{s['user']['id']}/addictions", headers=bearer(doc)).json()
    assert row["profile"] == "buprenorphine"


def test_other_doctor_reaches_neither_chart_nor_profile(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    other_doctor()
    other = login(client, "other@example.invalid").json()
    base = f"/v1/staff/patients/{s['user']['id']}/addictions/{a['id']}"
    assert client.get(f"{base}/checks", headers=bearer(other)).status_code == 404
    assert client.put(f"{base}/profile", json={"profile": "thc"}, headers=bearer(other)).status_code == 404


def test_doctor_routes_need_a_doctor(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    base = f"/v1/staff/patients/{s['user']['id']}/addictions/{a['id']}"
    assert client.get(f"{base}/checks").status_code == 401
    assert client.get(f"{base}/checks", headers=bearer(s)).status_code == 403
    assert client.put(f"{base}/profile", json={"profile": "thc"}, headers=bearer(s)).status_code == 403


def test_another_patients_addiction_is_not_found(client, sms):
    doc, s = setup(client, sms)
    a = add(client, s).json()
    other = unlocked(client, sms, "0771234567")  # booked with another doctor
    b = add(client, other).json()
    # Another doctor's patient, and this patient's addiction under the wrong patient.
    url = f"/v1/staff/patients/{other['user']['id']}/addictions/{b['id']}/checks"
    assert client.get(url, headers=bearer(doc)).status_code == 404
    url = f"/v1/staff/patients/{s['user']['id']}/addictions/{b['id']}/checks"
    assert client.get(url, headers=bearer(doc)).status_code == 404


# --- Alerts ---------------------------------------------------------------


def _alerts(client, doc):
    return [a["type"] for a in client.get("/v1/staff/alerts", headers=bearer(doc)).json()]


def test_three_high_craving_days_alert_the_doctor_once(client, sms):
    doc, s = setup(client, sms)
    a = add(client, s).json()
    for day in ("2026-10-17", "2026-10-18", "2026-10-19"):
        assert check(client, s, a, day=day, craving=4).status_code == 204
        later(client, s, doc=doc)
    with Session(engine) as db:
        assert craving_alerts(db) == 1
        assert craving_alerts(db) == 0
    assert _alerts(client, doc) == ["craving_high"]
    [alert] = client.get("/v1/staff/alerts", headers=bearer(doc)).json()
    assert set(alert) == {"id", "patient_id", "patient_phone", "type", "priority", "read", "created_at"}


def test_a_lower_craving_day_breaks_the_run(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    for day, craving in (("2026-10-17", 5), ("2026-10-18", 3), ("2026-10-19", 5)):
        check(client, s, a, day=day, craving=craving)
        later(client, s)
    with Session(engine) as db:
        assert craving_alerts(db) == 0


def test_three_days_without_a_check_alert_the_doctor(client, sms):
    doc, s = setup(client, sms)
    add(client, s)
    later(client, s, days=4, doc=doc)
    with Session(engine) as db:
        assert no_checkin_alerts(db) == 1
        assert no_checkin_alerts(db) == 0
    assert _alerts(client, doc) == ["no_checkin"]


def test_no_missed_check_alert_for_a_new_addiction_or_a_checked_day(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    with Session(engine) as db:
        assert no_checkin_alerts(db) == 0  # added today
    check(client, s, a)
    advance(days=3)  # window 10-17 .. 10-19 holds one check
    with Session(engine) as db:
        assert no_checkin_alerts(db) == 0


def test_every_patient_recovery_route_is_locked_before_a_paid_visit(client, sms):
    s = register(client, sms)
    h = bearer(s)
    calls = [
        client.get("/v1/me/doses", headers=h),
        client.put("/v1/me/doses", headers=h, json={"medication_id": "00000000-0000-0000-0000-000000000000",
                                                     "day": TODAY, "time": "08:00", "status": "taken"}),
        client.get("/v1/me/quote", headers=h),
        client.get("/v1/me/checkins", headers=h),
        client.put(f"/v1/me/checkins/{TODAY}", headers=h),
        client.get("/v1/me/reminder", headers=h),
        client.put("/v1/me/reminder", headers=h, json={"time": "21:00"}),
        client.get("/v1/me/addiction-checks", headers=h),
        client.put(f"/v1/me/addictions/00000000-0000-0000-0000-000000000000/checks/{TODAY}",
                   headers=h, json={"used": False, "craving": 1, "signals": {}}),
    ]
    for r in calls:
        assert r.status_code == 403 and r.json()["detail"]["code"] == "recovery_locked", r.request.url
