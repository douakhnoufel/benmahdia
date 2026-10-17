import enum
import uuid
from datetime import datetime

from sqlalchemy import (
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .clock import clock
from .db import Base


def _now() -> datetime:
    return clock.now()


class Role(str, enum.Enum):
    super_admin = "super_admin"
    doctor = "doctor"
    patient = "patient"


class AccountStatus(str, enum.Enum):
    # Signed up; the clinic has not approved the identity check yet (PRD 4.2).
    pending_verification = "pending_verification"
    verified = "verified"
    rejected = "rejected"
    # Deleted by the patient; erased after the grace period (PRD 12.5).
    deleted = "deleted"


class Provider(str, enum.Enum):
    google = "google"
    apple = "apple"


class OtpPurpose(str, enum.Enum):
    sign_up = "sign_up"
    reset_password = "reset_password"
    attach_phone = "attach_phone"


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    role: Mapped[Role] = mapped_column(Enum(Role, name="role"), default=Role.patient)
    status: Mapped[AccountStatus] = mapped_column(
        Enum(AccountStatus, name="account_status"),
        default=AccountStatus.pending_verification,
    )
    # E.164, e.g. +213550123456. Unique among accounts that still exist.
    phone: Mapped[str | None] = mapped_column(String(16), unique=True)
    phone_verified_at: Mapped[datetime | None] = mapped_column(DateTime)
    email: Mapped[str | None] = mapped_column(String(320))
    password_hash: Mapped[str | None] = mapped_column(String(255))
    language: Mapped[str] = mapped_column(String(2), default="ar")
    failed_logins: Mapped[int] = mapped_column(Integer, default=0)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime)

    identities: Mapped[list["Identity"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )

    @property
    def active(self) -> bool:
        return self.deleted_at is None


class Identity(Base):
    """A Google or Apple account linked to a user, keyed by the provider's
    stable subject id (never by email, which can change)."""

    __tablename__ = "identities"
    __table_args__ = (UniqueConstraint("provider", "subject"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    provider: Mapped[Provider] = mapped_column(Enum(Provider, name="provider"))
    subject: Mapped[str] = mapped_column(String(255))
    # Apple only: lets us revoke the app's access when the account is deleted.
    apple_refresh_token: Mapped[str | None] = mapped_column(String(512))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    user: Mapped[User] = relationship(back_populates="identities")


class OtpCode(Base):
    """One SMS code. Only a keyed hash of the code is stored."""

    __tablename__ = "otp_codes"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    phone: Mapped[str] = mapped_column(String(16), index=True)
    purpose: Mapped[OtpPurpose] = mapped_column(Enum(OtpPurpose, name="otp_purpose"))
    code_hash: Mapped[str] = mapped_column(String(64))
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    sent_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    # Right code entered: a single-use proof was issued.
    verified_at: Mapped[datetime | None] = mapped_column(DateTime)
    # The proof was spent (account created, password reset, phone added).
    used_at: Mapped[datetime | None] = mapped_column(DateTime)
    # A newer code replaced this one.
    superseded: Mapped[bool] = mapped_column(default=False)


class RefreshToken(Base):
    """Rotating refresh tokens. Only a hash is stored. Tokens from one login
    share a family; reusing a spent token revokes the whole family."""

    __tablename__ = "refresh_tokens"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    family_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime)


class AuditLog(Base):
    """Who did what, when (PRD 4.1: all logins audited). Never holds medical
    content, codes, passwords or tokens."""

    __tablename__ = "audit_log"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    actor_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, index=True)
    action: Mapped[str] = mapped_column(String(64))
    target: Mapped[str | None] = mapped_column(String(128))
    ip: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, index=True)
