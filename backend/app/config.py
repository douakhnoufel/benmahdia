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

    # ID declaration (PRD 4.2). Three separate secrets, only in .env: the
    # HMAC of the ID number, the key for the encrypted name / birth date, and
    # the key for the encrypted selfie files.
    id_hmac_key: str = "change-me-dev-only-id-hmac-key-0000000000000"
    id_data_key: str = "change-me-dev-only-id-data-key-0000000000000"
    selfie_key: str = "change-me-dev-only-selfie-key-00000000000000"
    # The doctors' private notes after a visit (PRD 4.3), encrypted at rest.
    notes_key: str = "change-me-dev-only-notes-key-000000000000000"
    # Where encrypted selfie files live (a private folder, never served).
    selfie_dir: str = "./data/selfies"
    selfie_max_bytes: int = 2_097_152
    # First declaration plus three resubmissions after a rejection.
    id_max_submissions: int = 4

    # Front-desk check-in: wrong codes one doctor account may try within the
    # window before it must wait (stops guessing of booking codes).
    checkin_max_failures: int = 10
    checkin_window_minutes: int = 10

    # How far ahead a patient can book (PRD 4.3).
    booking_horizon_days: int = 60

    # Chargily Pay v2 (PRD 4.4). The test URL and a test_sk_ key never move
    # real money; production needs the live URL and a live key.
    chargily_api_url: str = "https://pay.chargily.net/test/api/v2"
    chargily_secret_key: str = ""
    # Public address of this API, for Chargily's webhook and the return pages
    # (locally: an ngrok-style tunnel).
    public_base_url: str = "http://localhost:8000"

    # Browser origins allowed to call the API (the doctor dashboard).
    # Comma-separated in the environment.
    cors_origins: Annotated[list[str], NoDecode] = ["http://localhost:5173"]

    @field_validator("google_client_ids", "apple_client_ids", "cors_origins", mode="before")
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
            if self.chargily_secret_key.startswith("test_") or "/test/" in self.chargily_api_url:
                raise ValueError("Chargily test mode is for development only")
            for name in ("jwt_secret", "otp_secret", "id_hmac_key", "id_data_key", "selfie_key", "notes_key"):
                value = getattr(self, name)
                if value.startswith(_DEV_SECRET_PREFIX) or len(value) < 32:
                    raise ValueError(f"{name.upper()} must be a long random secret")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
