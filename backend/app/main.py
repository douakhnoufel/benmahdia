import logging

from fastapi import FastAPI

from .config import get_settings
from .routers import appointments, auth, doctors, me, payments, staff

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
    app.include_router(auth.router)
    app.include_router(me.router)
    app.include_router(doctors.router)
    app.include_router(appointments.router)
    app.include_router(payments.router)
    app.include_router(staff.router)

    @app.get("/health", tags=["health"])
    def health() -> dict[str, str]:
        return {"status": "ok"}

    return app


app = create_app()
