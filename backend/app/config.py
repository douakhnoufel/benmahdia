from functools import lru_cache
from typing import Annotated

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

_DEV_SECRET_PREFIX = "change-me"


class Settings(BaseSettings):
    """Read from the environment (or a .env file). See .env.example."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    environment: str = "development"
    database_url: str = "sqlite:///./dev.db"

    jwt_secret: str = "change-me-dev-only-jwt-secret-0000000000000000"
    otp_secret: str = "change-me-dev-only-otp-secret-0000000000000000"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    proof_minutes: int = 10

    sms_provider: str = "console"
    otp_length: int = 6
    otp_minutes: int = 5
    otp_resend_seconds: int = 60
    otp_max_attempts: int = 5
    otp_max_per_hour: int = 5

    login_max_failures: int = 5
    lock_minutes: int = 15

    # Comma-separated in the environment.
    google_client_ids: Annotated[list[str], NoDecode] = []
    apple_client_ids: Annotated[list[str], NoDecode] = []
    apple_team_id: str = ""
    apple_key_id: str = ""
    apple_private_key: str = ""

    deletion_grace_days: int = 30

    # How far ahead a patient can book (PRD 4.3).
    booking_horizon_days: int = 60

    @field_validator("google_client_ids", "apple_client_ids", mode="before")
    @classmethod
    def _split(cls, value: object) -> object:
        if isinstance(value, str):
            return [v.strip() for v in value.split(",") if v.strip()]
        return value

    @property
    def production(self) -> bool:
        return self.environment == "production"

    @model_validator(mode="after")
    def _safe_in_production(self) -> "Settings":
        if self.production:
            if self.sms_provider == "console":
                raise ValueError("SMS_PROVIDER=console is for development only")
            for name in ("jwt_secret", "otp_secret"):
                value = getattr(self, name)
                if value.startswith(_DEV_SECRET_PREFIX) or len(value) < 32:
                    raise ValueError(f"{name.upper()} must be a long random secret")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
