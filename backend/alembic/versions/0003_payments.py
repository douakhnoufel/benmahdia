"""chargily payments

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-17 22:30:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # payment_method already exists (0002); reuse it instead of recreating it.
    method = postgresql.ENUM("edahabia", "cib", "clinic", name="payment_method", create_type=False)
    if op.get_bind().dialect.name != "postgresql":
        method = sa.Enum("edahabia", "cib", "clinic", name="payment_method")
    op.create_table(
        "payments",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("appointment_id", sa.Uuid(), nullable=True),
        sa.Column("patient_id", sa.Uuid(), nullable=False),
        sa.Column("amount_dzd", sa.Integer(), nullable=False),
        sa.Column("method", method, nullable=False),
        sa.Column("chargily_id", sa.String(length=64), nullable=False),
        sa.Column(
            "status",
            sa.Enum("pending", "paid", "failed", "refunded", name="payment_status"),
            nullable=False,
        ),
        sa.Column("paid_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["appointment_id"], ["appointments.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["patient_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("chargily_id"),
    )
    op.create_index(op.f("ix_payments_appointment_id"), "payments", ["appointment_id"])
    op.create_index(op.f("ix_payments_patient_id"), "payments", ["patient_id"])


def downgrade() -> None:
    op.drop_index(op.f("ix_payments_patient_id"), table_name="payments")
    op.drop_index(op.f("ix_payments_appointment_id"), table_name="payments")
    op.drop_table("payments")
    sa.Enum(name="payment_status").drop(op.get_bind(), checkfirst=True)
