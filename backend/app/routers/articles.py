"""Articles (PRD 5.5, 7): the clinic's doctors write, edit and publish them
from the dashboard; patients read the published ones at any time, filter
them by language, topic and addiction, and keep favourites. Articles are
clinic content, not patient data, so any doctor may edit any article."""

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from .. import audit
from ..clock import clock
from ..db import get_db, insert_once
from ..deps import current_user
from ..errors import ApiError
from ..models import (
    AddictionType,
    Article,
    ArticleFavourite,
    ArticleTopic,
    DoctorProfile,
    Role,
    User,
)
from .doctors import utc_iso
from .staff import current_doctor

router = APIRouter(prefix="/v1/me/articles", tags=["articles"])
staff_router = APIRouter(prefix="/v1/staff/articles", tags=["staff"])

LANGUAGES = ("ar", "fr")
MAX_BODY = 20000


def any_patient(user: User = Depends(current_user)) -> User:
    """Any signed-in patient: articles can be read at any time (PRD 5.5),
    before the identity check or the first visit."""
    if user.role != Role.patient:
        raise ApiError(403, "forbidden")
    return user


class ArticleIn(BaseModel):
    title: str = Field(max_length=160)
    body: str = Field(max_length=MAX_BODY)
    language: str
    topic: ArticleTopic
    addiction_type: AddictionType | None = None
    published: bool = False

    @field_validator("title", "body")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be empty")
        return v

    @field_validator("language")
    @classmethod
    def _language(cls, v: str) -> str:
        if v not in LANGUAGES:
            raise ValueError("language must be ar or fr")
        return v


class ArticleSummary(BaseModel):
    id: uuid.UUID
    title: str
    language: str
    topic: ArticleTopic
    addiction_type: str | None
    published_at: str | None


class PatientArticle(ArticleSummary):
    favourite: bool


class PatientArticleFull(PatientArticle):
    body: str


class StaffArticle(ArticleSummary):
    published: bool
    updated_at: str


class StaffArticleFull(StaffArticle):
    body: str


def _iso(at: datetime | None) -> str | None:
    return None if at is None else utc_iso(at)


def _summary(a: Article) -> dict:
    return {
        "id": a.id,
        "title": a.title,
        "language": a.language,
        "topic": a.topic,
        "addiction_type": a.addiction_type,
        "published_at": _iso(a.published_at),
    }


def _staff(a: Article, full: bool = False):
    fields = _summary(a) | {"published": a.published, "updated_at": utc_iso(a.updated_at)}
    return StaffArticleFull(**fields, body=a.body) if full else StaffArticle(**fields)


def _favourites(db: Session, user: User) -> set[uuid.UUID]:
    return set(db.scalars(select(ArticleFavourite.article_id).where(ArticleFavourite.patient_id == user.id)))


def _published(db: Session, article_id: uuid.UUID) -> Article:
    a = db.get(Article, article_id)
    if a is None or not a.published:
        raise ApiError(404, "not_found")
    return a


# --- Patient ------------------------------------------------------------------


@router.get("", response_model=list[PatientArticle])
def list_articles(
    language: str | None = None,
    topic: ArticleTopic | None = None,
    addiction_type: AddictionType | None = None,
    favourites: bool = False,
    user: User = Depends(any_patient),
    db: Session = Depends(get_db),
) -> list[PatientArticle]:
    """Published articles, newest first. An addiction filter keeps the
    articles written for every patient too."""
    q = select(Article).where(Article.published.is_(True))
    if language is not None:
        q = q.where(Article.language == language)
    if topic is not None:
        q = q.where(Article.topic == topic)
    if addiction_type is not None:
        q = q.where(or_(Article.addiction_type.is_(None), Article.addiction_type == addiction_type.value))
    saved = _favourites(db, user)
    if favourites:
        q = q.where(Article.id.in_(saved))
    rows = db.scalars(q.order_by(Article.published_at.desc()))
    return [PatientArticle(**_summary(a), favourite=a.id in saved) for a in rows]


@router.get("/{article_id}", response_model=PatientArticleFull)
def read_article(
    article_id: uuid.UUID, user: User = Depends(any_patient), db: Session = Depends(get_db)
) -> PatientArticleFull:
    a = _published(db, article_id)
    return PatientArticleFull(**_summary(a), favourite=a.id in _favourites(db, user), body=a.body)


@router.put("/{article_id}/favourite", status_code=204)
def add_favourite(
    article_id: uuid.UUID, user: User = Depends(any_patient), db: Session = Depends(get_db)
) -> Response:
    """Saves the article; saving twice changes nothing."""
    a = _published(db, article_id)

    def stored() -> ArticleFavourite | None:
        return db.scalar(
            select(ArticleFavourite).where(
                ArticleFavourite.patient_id == user.id, ArticleFavourite.article_id == a.id
            )
        )

    if stored() is None:
        # Two taps at once: the second insert meets the unique key and keeps
        # the row the other request saved.
        insert_once(db, ArticleFavourite(patient_id=user.id, article_id=a.id), stored)
        db.commit()
    return Response(status_code=204)


@router.delete("/{article_id}/favourite", status_code=204)
def remove_favourite(
    article_id: uuid.UUID, user: User = Depends(any_patient), db: Session = Depends(get_db)
) -> Response:
    fav = db.scalar(
        select(ArticleFavourite).where(
            ArticleFavourite.patient_id == user.id, ArticleFavourite.article_id == article_id
        )
    )
    if fav is not None:
        db.delete(fav)
        db.commit()
    return Response(status_code=204)


# --- Dashboard ----------------------------------------------------------------


def _apply(a: Article, body: ArticleIn, request: Request, db: Session, doctor: DoctorProfile) -> None:
    was_published = a.published
    a.title = body.title
    a.body = body.body
    a.language = body.language
    a.topic = body.topic
    a.addiction_type = body.addiction_type.value if body.addiction_type else None
    a.published = body.published
    a.updated_at = clock.now()
    if body.published and not was_published:
        a.published_at = clock.now()
        audit.record(db, "article.published", actor_id=doctor.user_id, target=str(a.id), request=request)
    elif was_published and not body.published:
        audit.record(db, "article.unpublished", actor_id=doctor.user_id, target=str(a.id), request=request)


@staff_router.get("", response_model=list[StaffArticle])
def staff_list(
    doctor: DoctorProfile = Depends(current_doctor), db: Session = Depends(get_db)
) -> list[StaffArticle]:
    """Every article, drafts included, last edited first."""
    return [_staff(a) for a in db.scalars(select(Article).order_by(Article.updated_at.desc()))]


@staff_router.get("/{article_id}", response_model=StaffArticleFull)
def staff_read(
    article_id: uuid.UUID, doctor: DoctorProfile = Depends(current_doctor), db: Session = Depends(get_db)
) -> StaffArticleFull:
    a = db.get(Article, article_id)
    if a is None:
        raise ApiError(404, "not_found")
    return _staff(a, full=True)


@staff_router.post("", response_model=StaffArticleFull, status_code=201)
def staff_create(
    body: ArticleIn,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> StaffArticleFull:
    a = Article(id=uuid.uuid4(), author_id=doctor.user_id, published=False)
    audit.record(db, "article.created", actor_id=doctor.user_id, target=str(a.id), request=request)
    _apply(a, body, request, db, doctor)
    db.add(a)
    db.commit()
    db.refresh(a)
    return _staff(a, full=True)


@staff_router.put("/{article_id}", response_model=StaffArticleFull)
def staff_update(
    article_id: uuid.UUID,
    body: ArticleIn,
    request: Request,
    doctor: DoctorProfile = Depends(current_doctor),
    db: Session = Depends(get_db),
) -> StaffArticleFull:
    a = db.get(Article, article_id)
    if a is None:
        raise ApiError(404, "not_found")
    _apply(a, body, request, db, doctor)
    db.commit()
    db.refresh(a)
    return _staff(a, full=True)
