"""doctors, availability and appointments

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-17 21:10:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from app.models import OVERLAP_DDL

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "doctor_profiles",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("name_ar", sa.String(length=120), nullable=False),
        sa.Column("name_fr", sa.String(length=120), nullable=False),
        sa.Column("slot_minutes", sa.Integer(), nullable=False),
        sa.Column("price_dzd", sa.Integer(), nullable=False),
        sa.Column("notice_hours", sa.Integer(), nullable=False),
        sa.Column("hold_minutes", sa.Integer(), nullable=False),
        sa.CheckConstraint("slot_minutes IN (5, 10, 15)", name="ck_slot_minutes"),
        sa.CheckConstraint("price_dzd >= 0", name="ck_price_dzd"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("user_id"),
    )
    op.create_table(
        "availabilities",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("doctor_id", sa.Uuid(), nullable=False),
        sa.Column("weekday", sa.Integer(), nullable=False),
        sa.Column("start_minute", sa.Integer(), nullable=False),
        sa.Column("end_minute", sa.Integer(), nullable=False),
        sa.CheckConstraint("weekday BETWEEN 0 AND 6", name="ck_weekday"),
        sa.CheckConstraint(
            "start_minute >= 0 AND end_minute <= 1440 AND start_minute < end_minute",
            name="ck_window",
        ),
        sa.ForeignKeyConstraint(["doctor_id"], ["doctor_profiles.user_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_availabilities_doctor_id"), "availabilities", ["doctor_id"])
    op.create_table(
        "availability_exceptions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("doctor_id", sa.Uuid(), nullable=False),
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("reason", sa.String(length=120), nullable=True),
        sa.ForeignKeyConstraint(["doctor_id"], ["doctor_profiles.user_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("doctor_id", "day"),
    )
    op.create_index(
        op.f("ix_availability_exceptions_doctor_id"), "availability_exceptions", ["doctor_id"]
    )
    op.create_table(
        "appointments",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("doctor_id", sa.Uuid(), nullable=False),
        sa.Column("patient_id", sa.Uuid(), nullable=False),
        sa.Column("start_utc", sa.DateTime(), nullable=False),
        sa.Column("end_utc", sa.DateTime(), nullable=False),
        sa.Column(
            "status",
            sa.Enum(
                "awaiting_payment", "confirmed", "completed", "cancelled", "no_show",
                name="appointment_status",
            ),
            nullable=False,
        ),
        sa.Column("price_dzd", sa.Integer(), nullable=False),
        sa.Column(
            "method",
            sa.Enum("edahabia", "cib", "clinic", name="payment_method"),
            nullable=True,
        ),
        sa.Column("hold_expires_at", sa.DateTime(), nullable=True),
        sa.Column("cancelled_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("end_utc > start_utc", name="ck_appointment_range"),
        sa.ForeignKeyConstraint(["doctor_id"], ["doctor_profiles.user_id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["patient_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_appointments_patient_id"), "appointments", ["patient_id"])
    op.create_index("ix_appointments_doctor_start", "appointments", ["doctor_id", "start_utc"])
    if op.get_bind().dialect.name == "postgresql":
        op.execute("CREATE EXTENSION IF NOT EXISTS btree_gist")
        op.execute(OVERLAP_DDL)


def downgrade() -> None:
    op.drop_index("ix_appointments_doctor_start", table_name="appointments")
    op.drop_index(op.f("ix_appointments_patient_id"), table_name="appointments")
    op.drop_table("appointments")
    op.drop_index(op.f("ix_availability_exceptions_doctor_id"), table_name="availability_exceptions")
    op.drop_table("availability_exceptions")
    op.drop_index(op.f("ix_availabilities_doctor_id"), table_name="availabilities")
    op.drop_table("availabilities")
    op.drop_table("doctor_profiles")
    for name in ("appointment_status", "payment_method"):
        sa.Enum(name=name).drop(op.get_bind(), checkfirst=True)
