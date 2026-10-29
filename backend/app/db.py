from collections.abc import Iterator

from sqlalchemy import create_engine
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

