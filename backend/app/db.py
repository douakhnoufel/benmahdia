from collections.abc import Callable, Iterator
from typing import TypeVar

from sqlalchemy import create_engine
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import get_settings


class Base(DeclarativeBase):
    pass


def _engine(url: str):
    # hide_parameters: a database error's text (logged by the server with its
    # traceback) never carries the bound values, which can be a patient's
    # answers (CLAUDE.md: no medical content in logs).
    if url.startswith("sqlite"):
        # Local tests and quick runs. Real deployments use PostgreSQL.
        from sqlalchemy.pool import StaticPool

        memory = url in ("sqlite://", "sqlite:///:memory:")
        return create_engine(
            url,
            connect_args={"check_same_thread": False},
            poolclass=StaticPool if memory else None,
            hide_parameters=True,
        )
    return create_engine(url, pool_pre_ping=True, hide_parameters=True)


engine = _engine(get_settings().database_url)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db() -> Iterator[Session]:
    with SessionLocal() as session:
        yield session


T = TypeVar("T")


def insert_once(db: Session, row: T, stored: Callable[[], T | None]) -> tuple[T, bool]:
    """Inserts [row], a once-a-day row with a unique key (a check, a tick, a
    dose answer). When another request saved the same key first (a double
    tap, two phones), the insert is rolled back to a savepoint and the row
    that request stored, read by [stored], is returned instead.

    Returns (the row, whether this call inserted it). Re-raises the
    IntegrityError when no stored row explains it."""
    try:
        with db.begin_nested():
            db.add(row)
        return row, True
    except IntegrityError:
        existing = stored()
        if existing is None:
            raise
        return existing, False
