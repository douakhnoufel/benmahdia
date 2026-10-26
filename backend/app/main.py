import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings
from .routers import (
    addiction_checks,
    appointments,
    articles,
    auth,
    checkins,
    doctors,
    habits,
    identity,
    me,
    medications,
    payments,
    recovery,
    staff,
    staff_identity,
    staff_recovery,
)

logging.basicConfig(level=logging.INFO)


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="BenMahdia API",
        version="0.1.0",
        # Interactive docs only outside production.
        docs_url=None if settings.production else "/docs",
        redoc_url=None,
        openapi_url=None if settings.production else "/openapi.json",
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_methods=["GET", "POST", "PUT", "DELETE"],
        allow_headers=["authorization", "content-type"],
    )
    app.include_router(auth.router)
    app.include_router(me.router)
    app.include_router(recovery.router)
    app.include_router(checkins.router)
    app.include_router(addiction_checks.router)
    app.include_router(habits.router)
    app.include_router(articles.router)
    app.include_router(medications.router)
    app.include_router(medications.staff_router)
    app.include_router(identity.router)
    app.include_router(doctors.router)
    app.include_router(appointments.router)
    app.include_router(payments.router)
    app.include_router(staff.router)
    app.include_router(staff_recovery.router)
    app.include_router(addiction_checks.staff_router)
    app.include_router(habits.staff_router)
    app.include_router(articles.staff_router)
    app.include_router(staff_identity.router)

    @app.get("/health", tags=["health"])
    def health() -> dict[str, str]:
        return {"status": "ok"}

    return app


app = create_app()
