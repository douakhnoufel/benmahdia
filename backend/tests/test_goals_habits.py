"""Small goals and good habits (PRD 5.6)."""

from app.substances import current_goal, next_goal

from .conftest import bearer, register
from .test_medications import unlocked
from .test_staff import login, other_doctor
from .test_substance_tracking import TODAY, add, later, setup

# The tracking helper's addiction is clean since 2026-10-07: a 10-day streak.


def goal(client, s, a, days):
    return client.put(f"/v1/me/addictions/{a['id']}/goal", json={"days": days}, headers=bearer(s))


def habit(client, s, **body):
    return client.post("/v1/me/habits", json={"kind": "sport"} | body, headers=bearer(s))


def habits(client, s):
    return client.get("/v1/me/habits", headers=bearer(s)).json()


# --- Small goals ----------------------------------------------------------


def test_goal_ladder():
    assert [next_goal(d) for d in (0, 1, 2, 3, 6, 7, 13, 14, 27, 28)] == [1, 3, 3, 7, 7, 14, 14, 28, 28, 60]
    assert [next_goal(d) for d in (59, 60, 179, 364, 365, 800)] == [60, 90, 180, 365, 730, 1095]
    assert current_goal(10, 28) == 28  # chosen, still ahead
    assert current_goal(28, 28) == 60  # reached: the next step
    assert current_goal(10, None) == 14


def test_automatic_goal_is_the_next_step(client, sms):
    _, s = setup(client, sms)
    body = add(client, s).json()
    assert body["goal_days"] is None and body["goal"] == 14


def test_patient_picks_a_higher_or_lower_goal(client, sms):
    _, s = setup(client, sms)
    a = add(client, s, clean_since=f"{TODAY}T10:00:00Z").json()  # day 0
    assert a["goal"] == 1
    r = goal(client, s, a, 7)
    assert r.status_code == 200 and r.json()["goal_days"] == 7 and r.json()["goal"] == 7
    assert goal(client, s, a, 3).json()["goal"] == 3
    r = goal(client, s, a, None)
    assert r.json()["goal_days"] is None and r.json()["goal"] == 1


def test_goal_must_be_a_step_not_reached_yet(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()  # 10-day streak
    for days in (3, 7, 10, 5, 60, 0):
        r = goal(client, s, a, days)
        assert r.status_code == 422 and r.json()["detail"]["code"] == "goal_invalid", days
    assert goal(client, s, a, 28).status_code == 200


def test_reached_goal_moves_to_the_next_step(client, sms):
    _, s = setup(client, sms)
    a = add(client, s, clean_since=f"{TODAY}T10:00:00Z").json()
    goal(client, s, a, 1)
    later(client, s, days=1)
    [now] = client.get("/v1/me/addictions", headers=bearer(s)).json()
    assert now["goal_days"] == 1 and now["goal"] == 3


def test_relapse_resets_the_goal_to_one_day(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    goal(client, s, a, 28)
    r = client.post(f"/v1/me/addictions/{a['id']}/relapses", json={}, headers=bearer(s))
    assert r.json()["goal_days"] is None and r.json()["goal"] == 1


def test_goal_is_own_and_locked(client, sms):
    _, s = setup(client, sms)
    a = add(client, s).json()
    _, other = setup(client, sms, "0771234567")
    assert goal(client, other, a, 28).status_code == 404
    locked = register(client, sms, "0551234567")
    assert goal(client, locked, a, 28).json()["detail"]["code"] == "recovery_locked"


def test_doctor_sees_the_current_goal(client, sms):
    doc, s = setup(client, sms)
    a = add(client, s).json()
    goal(client, s, a, 28)
    [row] = client.get(f"/v1/staff/patients/{s['user']['id']}/addictions", headers=bearer(doc)).json()
    assert row["goal_days"] == 28 and row["goal"] == 28


# --- Habits ---------------------------------------------------------------


def test_catalog(client, sms):
    _, s = setup(client, sms)
    items = client.get("/v1/me/habits/catalog", headers=bearer(s)).json()
    assert [i["kind"] for i in items] == ["sport", "brush_teeth", "water", "reading", "call_family", "sleep"]
    assert all(i["label"]["ar"] and i["label"]["fr"] for i in items)


def test_add_list_and_remove(client, sms):
    _, s = setup(client, sms)
    r = habit(client, s, reminder_time="18:30")
    assert r.status_code == 201, r.text
    h = r.json()
    assert h["kind"] == "sport" and h["text"] is None and h["reminder_time"] == "18:30" and h["days"] == []
    assert [x["id"] for x in habits(client, s)] == [h["id"]]
    assert client.delete(f"/v1/me/habits/{h['id']}", headers=bearer(s)).status_code == 204
    assert habits(client, s) == []


def test_custom_habit_needs_own_words(client, sms):
    _, s = setup(client, sms)
    assert habit(client, s, kind="custom").status_code == 422
    assert habit(client, s, kind="custom", text="  ").status_code == 422
    assert habit(client, s, kind="water", text="beaucoup").status_code == 422
    r = habit(client, s, kind="custom", text=" Jardiner ")
    assert r.status_code == 201 and r.json()["text"] == "Jardiner"
    assert habit(client, s, kind="custom", text="x" * 61).status_code == 422


def test_habit_limits(client, sms):
    _, s = setup(client, sms)
    habit(client, s)
    r = habit(client, s)
    assert r.status_code == 409 and r.json()["detail"]["code"] == "habit_exists"
    for kind in ("water", "reading", "sleep", "call_family"):
        assert habit(client, s, kind=kind).status_code == 201
    r = habit(client, s, kind="custom", text="Marcher")
    assert r.status_code == 409 and r.json()["detail"]["code"] == "too_many_habits"


def test_reminder_set_clear_and_validate(client, sms):
    _, s = setup(client, sms)
    h = habit(client, s).json()
    url = f"/v1/me/habits/{h['id']}/reminder"
    assert client.put(url, json={"time": "07:15"}, headers=bearer(s)).json()["reminder_time"] == "07:15"
    assert client.put(url, json={"time": None}, headers=bearer(s)).json()["reminder_time"] is None
    for bad in ("7:15", "24:00", "noon"):
        assert client.put(url, json={"time": bad}, headers=bearer(s)).status_code == 422
    assert habit(client, s, kind="water", reminder_time="25:00").status_code == 422


def test_tick_untick_and_day_range(client, sms):
    _, s = setup(client, sms)
    h = habit(client, s).json()
    url = f"/v1/me/habits/{h['id']}/days"
    assert client.put(f"{url}/{TODAY}", headers=bearer(s)).status_code == 204
    assert client.put(f"{url}/{TODAY}", headers=bearer(s)).status_code == 204  # twice is fine
    assert client.put(f"{url}/2026-10-16", headers=bearer(s)).status_code == 204
    assert habits(client, s)[0]["days"] == ["2026-10-16", TODAY]
    assert client.delete(f"{url}/2026-10-16", headers=bearer(s)).status_code == 204
    assert habits(client, s)[0]["days"] == [TODAY]
    for day in ("2026-10-14", "2026-10-19"):
        r = client.put(f"{url}/{day}", headers=bearer(s))
        assert r.status_code == 422 and r.json()["detail"]["code"] == "checkin_day_out_of_range"


def test_patient_reaches_only_own_habits(client, sms):
    _, s = setup(client, sms)
    h = habit(client, s).json()
    _, other = setup(client, sms, "0771234567")
    assert habits(client, other) == []
    assert client.put(f"/v1/me/habits/{h['id']}/days/{TODAY}", headers=bearer(other)).status_code == 404
    assert client.put(f"/v1/me/habits/{h['id']}/reminder", json={"time": None},
                      headers=bearer(other)).status_code == 404
    assert client.delete(f"/v1/me/habits/{h['id']}", headers=bearer(other)).status_code == 404


def test_habits_are_locked_and_patient_only(client, sms):
    locked = register(client, sms)
    for r in (
        client.get("/v1/me/habits", headers=bearer(locked)),
        client.get("/v1/me/habits/catalog", headers=bearer(locked)),
        habit(client, locked),
    ):
        assert r.status_code == 403 and r.json()["detail"]["code"] == "recovery_locked"
    doc, _ = setup(client, sms, "0771234567")
    assert client.get("/v1/me/habits", headers=bearer(doc)).status_code == 403
    assert client.get("/v1/me/habits").status_code == 401


def test_doctor_sees_days_done_out_of_30(client, sms):
    doc, s = setup(client, sms)
    sport = habit(client, s).json()
    own = habit(client, s, kind="custom", text="Jardiner").json()
    for day in ("2026-10-15", "2026-10-16", TODAY):
        client.put(f"/v1/me/habits/{sport['id']}/days/{day}", headers=bearer(s))
    rows = client.get(f"/v1/staff/patients/{s['user']['id']}/habits", headers=bearer(doc)).json()
    assert rows == [
        {"id": sport["id"], "kind": "sport", "text": None, "days": 30, "done_days": 3},
        {"id": own["id"], "kind": "custom", "text": "Jardiner", "days": 30, "done_days": 0},
    ]


def test_other_doctor_cannot_see_habits(client, sms):
    _, s = setup(client, sms)
    habit(client, s)
    other_doctor()
    other = login(client, "other@example.invalid").json()
    url = f"/v1/staff/patients/{s['user']['id']}/habits"
    assert client.get(url, headers=bearer(other)).status_code == 404
    assert client.get(url, headers=bearer(s)).status_code == 403
    assert client.get(url).status_code == 401


def test_unknown_patient_habits_not_found(client, sms):
    doc, _ = setup(client, sms)
    stranger = unlocked(client, sms, "0771234567")  # booked with another doctor
    r = client.get(f"/v1/staff/patients/{stranger['user']['id']}/habits", headers=bearer(doc))
    assert r.status_code == 404
