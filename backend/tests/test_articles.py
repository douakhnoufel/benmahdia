"""Articles (PRD 5.5, 7): doctors write and publish them from the dashboard;
patients read the published ones, filter them and keep favourites."""

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import engine
from app.models import AuditLog

from .booking_helpers import make_doctor
from .conftest import bearer, register
from .test_medications import staff_session

BODY = "Une envie dure rarement plus de vingt minutes.\n\nRespirez, buvez de l'eau, appelez quelqu'un."


def doctor(client):
    return staff_session(client, make_doctor())


def write(client, doc, **over):
    body = {
        "title": "Gérer une envie",
        "body": BODY,
        "language": "fr",
        "topic": "cravings",
        "addiction_type": None,
        "published": True,
    } | over
    return client.post("/v1/staff/articles", json=body, headers=bearer(doc))


def articles(client, s, **params):
    return client.get("/v1/me/articles", params=params, headers=bearer(s))


# --- Dashboard ----------------------------------------------------------------


def test_only_staff_write_articles(client, sms):
    assert client.post("/v1/staff/articles", json={}).status_code == 401
    s = register(client, sms)
    assert write(client, s).status_code == 403


def test_doctor_writes_edits_and_lists_drafts(client, sms):
    doc = doctor(client)
    r = write(client, doc, published=False)
    assert r.status_code == 201, r.text
    a = r.json()
    assert a["published"] is False and a["published_at"] is None
    assert a["title"] == "Gérer une envie" and a["body"] == BODY

    r = client.put(f"/v1/staff/articles/{a['id']}", headers=bearer(doc), json={
        "title": "Gérer une envie forte", "body": BODY, "language": "fr",
        "topic": "cravings", "addiction_type": "tobacco", "published": True,
    })
    assert r.status_code == 200, r.text
    edited = r.json()
    assert edited["title"] == "Gérer une envie forte" and edited["addiction_type"] == "tobacco"
    assert edited["published"] is True and edited["published_at"] is not None

    listed = client.get("/v1/staff/articles", headers=bearer(doc)).json()
    assert [x["id"] for x in listed] == [a["id"]]
    assert client.get(f"/v1/staff/articles/{a['id']}", headers=bearer(doc)).json()["body"] == BODY


def test_publishing_is_audited(client, sms):
    doc = doctor(client)
    a = write(client, doc).json()
    with Session(engine) as db:
        actions = list(db.scalars(select(AuditLog.action).where(AuditLog.target == a["id"])))
    assert "article.published" in actions


def test_article_input_is_checked(client, sms):
    doc = doctor(client)
    assert write(client, doc, title="  ").status_code == 422
    assert write(client, doc, body="").status_code == 422
    assert write(client, doc, language="en").status_code == 422
    assert write(client, doc, topic="gossip").status_code == 422
    assert write(client, doc, addiction_type="coffee").status_code == 422
    assert write(client, doc, body="x" * 20001).status_code == 422


def test_unknown_article_is_404(client, sms):
    doc = doctor(client)
    missing = "00000000-0000-0000-0000-000000000000"
    assert client.get(f"/v1/staff/articles/{missing}", headers=bearer(doc)).status_code == 404


# --- Patient --------------------------------------------------------------------


def test_patients_need_a_login(client):
    assert client.get("/v1/me/articles").status_code == 401


def test_a_new_patient_reads_published_articles_only(client, sms):
    # Articles can be read at any time (PRD 5.5), even before the first visit.
    doc = doctor(client)
    write(client, doc)
    write(client, doc, title="Brouillon", published=False)
    s = register(client, sms)
    r = articles(client, s)
    assert r.status_code == 200, r.text
    assert [a["title"] for a in r.json()] == ["Gérer une envie"]
    assert "body" not in r.json()[0]


def test_doctors_cannot_use_the_patient_routes(client, sms):
    doc = doctor(client)
    assert articles(client, doc).status_code == 403


def test_filters_by_language_topic_and_addiction(client, sms):
    doc = doctor(client)
    write(client, doc, title="Pour tous")
    write(client, doc, title="Tabac", addiction_type="tobacco")
    write(client, doc, title="Cannabis", addiction_type="cannabis")
    write(client, doc, title="Famille", topic="family")
    write(client, doc, title="الرغبة", language="ar")
    s = register(client, sms)

    titles = lambda **p: sorted(a["title"] for a in articles(client, s, **p).json())  # noqa: E731
    assert titles(language="ar") == ["الرغبة"]
    assert titles(language="fr", topic="family") == ["Famille"]
    # An addiction filter keeps the articles for everyone too.
    assert titles(language="fr", topic="cravings", addiction_type="tobacco") == ["Pour tous", "Tabac"]


def test_reader_gets_the_body_but_not_a_draft(client, sms):
    doc = doctor(client)
    a = write(client, doc).json()
    draft = write(client, doc, published=False).json()
    s = register(client, sms)
    r = client.get(f"/v1/me/articles/{a['id']}", headers=bearer(s))
    assert r.status_code == 200 and r.json()["body"] == BODY
    assert client.get(f"/v1/me/articles/{draft['id']}", headers=bearer(s)).status_code == 404


def test_favourites_are_per_patient(client, sms):
    doc = doctor(client)
    a = write(client, doc).json()
    b = write(client, doc, title="Autre").json()
    s = register(client, sms)
    other = register(client, sms, "0771234567")
    url = f"/v1/me/articles/{a['id']}/favourite"

    assert client.put(url, headers=bearer(s)).status_code == 204
    assert client.put(url, headers=bearer(s)).status_code == 204  # twice changes nothing
    assert [x["id"] for x in articles(client, s, favourites=True).json()] == [a["id"]]
    assert {x["id"]: x["favourite"] for x in articles(client, s).json()} == {a["id"]: True, b["id"]: False}
    assert articles(client, other, favourites=True).json() == []

    assert client.delete(url, headers=bearer(s)).status_code == 204
    assert articles(client, s, favourites=True).json() == []


def test_cannot_favourite_a_draft(client, sms):
    doc = doctor(client)
    draft = write(client, doc, published=False).json()
    s = register(client, sms)
    assert client.put(f"/v1/me/articles/{draft['id']}/favourite", headers=bearer(s)).status_code == 404


def test_unpublishing_hides_it_from_patients(client, sms):
    doc = doctor(client)
    a = write(client, doc).json()
    s = register(client, sms)
    client.put(f"/v1/me/articles/{a['id']}/favourite", headers=bearer(s))
    client.put(f"/v1/staff/articles/{a['id']}", headers=bearer(doc), json=a | {"published": False})
    assert articles(client, s).json() == []
    assert articles(client, s, favourites=True).json() == []
