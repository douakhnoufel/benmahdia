import enum
import uuid
from datetime import date, datetime

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    DDL,
    Enum,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    UniqueConstraint,
    Uuid,
    event,
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
    id_declaration: Mapped["IdDeclaration | None"] = relationship(
        back_populates="user", cascade="all, delete-orphan", uselist=False
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


class IdStatus(str, enum.Enum):
    """Where a patient's ID declaration stands (PRD 4.2). The system never
    says "verified": the clinic only approves what the patient declared."""

    declared = "declared"
    approved = "approved"
    rejected = "rejected"


class IdDeclaration(Base):
    """What the patient declared from their ID card, and a selfie for the
    doctor. The plain ID number is never stored: only a keyed HMAC (to catch an
    ID already linked to another account). Name, birth date and the selfie file
    are encrypted with keys that live only in the server's .env."""

    __tablename__ = "id_declarations"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    id_hmac: Mapped[str] = mapped_column(String(64), unique=True)
    # Which document the patient declared: "national_id" or "passport".
    id_type: Mapped[str] = mapped_column(
        String(16), default="national_id", server_default="national_id"
    )
    name_enc: Mapped[bytes] = mapped_column(LargeBinary)
    birth_enc: Mapped[bytes] = mapped_column(LargeBinary)
    # Name of the encrypted selfie file; None once it was deleted.
    selfie_file: Mapped[str | None] = mapped_column(String(64))
    status: Mapped[IdStatus] = mapped_column(
        Enum(IdStatus, name="id_status"), default=IdStatus.declared
    )
    # How many times the patient submitted (limit: id_max_submissions).
    attempts: Mapped[int] = mapped_column(Integer, default=1)
    reject_reason: Mapped[str | None] = mapped_column(String(200))
    declared_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    decided_at: Mapped[datetime | None] = mapped_column(DateTime)
    decided_by: Mapped[uuid.UUID | None] = mapped_column(Uuid)

    user: Mapped[User] = relationship(back_populates="id_declaration")


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


# --- Appointments (PRD 4.3, 4.4, 9) -----------------------------------------


class AppointmentStatus(str, enum.Enum):
    awaiting_payment = "awaiting_payment"
    confirmed = "confirmed"
    completed = "completed"
    cancelled = "cancelled"
    no_show = "no_show"


# Statuses that occupy the doctor's agenda. A cancelled, completed or no-show
# appointment no longer blocks its slot for the overlap rule.
ACTIVE_STATUSES = (AppointmentStatus.awaiting_payment, AppointmentStatus.confirmed)


class PaymentMethod(str, enum.Enum):
    edahabia = "edahabia"
    cib = "cib"
    # Paid at the clinic on the day; pilot only, confirmed by the doctor.
    clinic = "clinic"


class DoctorProfile(Base):
    """Booking settings of one doctor, set by the super admin (PRD 4.3)."""

    __tablename__ = "doctor_profiles"
    __table_args__ = (
        CheckConstraint("slot_minutes IN (5, 10, 15)", name="ck_slot_minutes"),
        CheckConstraint("price_dzd >= 0", name="ck_price_dzd"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    name_ar: Mapped[str] = mapped_column(String(120))
    name_fr: Mapped[str] = mapped_column(String(120))
    slot_minutes: Mapped[int] = mapped_column(Integer, default=15)
    price_dzd: Mapped[int] = mapped_column(Integer)
    # Minimum notice to book or cancel, in hours (PRD 4.3: 24 h).
    notice_hours: Mapped[int] = mapped_column(Integer, default=24)
    # How long an unpaid slot stays held, in minutes (PRD 4.3: 15 min).
    hold_minutes: Mapped[int] = mapped_column(Integer, default=15)


class Availability(Base):
    """One weekly consultation window. Times are minutes after midnight in
    clinic time (Africa/Algiers). Breaks are the gaps between two windows."""

    __tablename__ = "availabilities"
    __table_args__ = (
        CheckConstraint("weekday BETWEEN 0 AND 6", name="ck_weekday"),
        CheckConstraint(
            "start_minute >= 0 AND end_minute <= 1440 AND start_minute < end_minute",
            name="ck_window",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    doctor_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("doctor_profiles.user_id", ondelete="CASCADE"), index=True
    )
    # Monday = 0 ... Sunday = 6 (Python's date.weekday()).
    weekday: Mapped[int] = mapped_column(Integer)
    start_minute: Mapped[int] = mapped_column(Integer)
    end_minute: Mapped[int] = mapped_column(Integer)


class AvailabilityException(Base):
    """A day the doctor does not consult: a holiday or a one-off block."""

    __tablename__ = "availability_exceptions"
    __table_args__ = (UniqueConstraint("doctor_id", "day"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    doctor_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("doctor_profiles.user_id", ondelete="CASCADE"), index=True
    )
    day: Mapped[date] = mapped_column(Date)
    reason: Mapped[str | None] = mapped_column(String(120))


class Appointment(Base):
    __tablename__ = "appointments"
    __table_args__ = (
        CheckConstraint("end_utc > start_utc", name="ck_appointment_range"),
        Index("ix_appointments_doctor_start", "doctor_id", "start_utc"),
        UniqueConstraint("checkin_code", name="uq_appointments_checkin_code"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    doctor_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("doctor_profiles.user_id", ondelete="RESTRICT")
    )
    patient_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # UTC, stored without a zone like every other timestamp.
    start_utc: Mapped[datetime] = mapped_column(DateTime)
    end_utc: Mapped[datetime] = mapped_column(DateTime)
    status: Mapped[AppointmentStatus] = mapped_column(
        Enum(AppointmentStatus, name="appointment_status"),
        default=AppointmentStatus.awaiting_payment,
    )
    price_dzd: Mapped[int] = mapped_column(Integer)
    method: Mapped[PaymentMethod | None] = mapped_column(
        Enum(PaymentMethod, name="payment_method")
    )
    # Set while awaiting payment; the slot is given back after this time.
    hold_expires_at: Mapped[datetime | None] = mapped_column(DateTime)
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime)
    # Set by Chargily's webhook for cards, or by the doctor for pay-at-clinic.
    paid_at: Mapped[datetime | None] = mapped_column(DateTime)
    # Short code the patient shows at the front desk; set once the appointment
    # is confirmed. It identifies the appointment and holds no personal data.
    checkin_code: Mapped[str | None] = mapped_column(String(8))
    # Set when the doctor's dashboard accepted the code on the day.
    checked_in_at: Mapped[datetime | None] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class PaymentStatus(str, enum.Enum):
    pending = "pending"
    paid = "paid"
    failed = "failed"
    refunded = "refunded"


class Payment(Base):
    """One Chargily checkout (PRD 4.4). Only Chargily's id and status are kept,
    never card details."""

    __tablename__ = "payments"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    # Null when the slot was lost before the payment arrived: such a paid
    # payment must be refunded by the clinic.
    appointment_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("appointments.id", ondelete="SET NULL"), index=True
    )
    patient_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    amount_dzd: Mapped[int] = mapped_column(Integer)
    method: Mapped[PaymentMethod] = mapped_column(Enum(PaymentMethod, name="payment_method"))
    chargily_id: Mapped[str] = mapped_column(String(64), unique=True)
    status: Mapped[PaymentStatus] = mapped_column(
        Enum(PaymentStatus, name="payment_status"), default=PaymentStatus.pending
    )
    paid_at: Mapped[datetime | None] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


# PostgreSQL only: the database itself refuses two active appointments that
# overlap for the same doctor, so two simultaneous bookings cannot both win
# (PRD 4.3). SQLite (local tests) relies on the application check instead.
OVERLAP_DDL = """
ALTER TABLE appointments ADD CONSTRAINT ex_appointments_no_overlap
EXCLUDE USING gist (
    doctor_id WITH =,
    tsrange(start_utc, end_utc) WITH &&
) WHERE (status IN ('awaiting_payment', 'confirmed'))
"""

event.listen(
    Appointment.__table__,
    "after_create",
    DDL("CREATE EXTENSION IF NOT EXISTS btree_gist").execute_if(dialect="postgresql"),
)
event.listen(
    Appointment.__table__,
    "after_create",
    DDL(OVERLAP_DDL).execute_if(dialect="postgresql"),
)
