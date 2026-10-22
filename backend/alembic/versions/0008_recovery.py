"""Addictions, relapses and doctor alerts (PRD 5, 9)

Revision ID: 0008
Revises: 0007
Create Date: 2026-10-22 17:40:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "addictions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("patient_id", sa.Uuid(), nullable=False),
        sa.Column(
            "type",
            sa.Enum(
                "opioids", "cannabis", "alcohol", "tobacco", "pills", "gambling", "other",
                name="addiction_type",
            ),
            nullable=False,
        ),
        sa.Column("substance", sa.String(length=100), nullable=True),
        sa.Column("sobriety_start", sa.DateTime(), nullable=False),
        sa.Column("longest_past_days", sa.Integer(), nullable=False),
        sa.Column("past_days", sa.Integer(), nullable=False),
        sa.Column(
            "review_status",
            sa.Enum("pending", "confirmed", "rejected", name="review_status"),
            nullable=False,
        ),
        sa.Column("reviewed_at", sa.DateTime(), nullable=True),
        sa.Column("reviewed_by", sa.Uuid(), nullable=True),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["patient_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_addictions_patient_id", "addictions", ["patient_id"])
    op.create_table(
        "relapses",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("addiction_id", sa.Uuid(), nullable=False),
        sa.Column("occurred_at", sa.DateTime(), nullable=False),
        sa.Column("note", sa.String(length=500), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["addiction_id"], ["addictions.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_relapses_addiction_id", "relapses", ["addiction_id"])
    op.create_table(
        "alerts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("doctor_id", sa.Uuid(), nullable=False),
        sa.Column("patient_id", sa.Uuid(), nullable=False),
        sa.Column("type", sa.String(length=32), nullable=False),
        sa.Column("priority", sa.String(length=8), nullable=False),
        sa.Column("read", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["doctor_id"], ["doctor_profiles.user_id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["patient_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_alerts_doctor_id", "alerts", ["doctor_id"])
    op.create_index("ix_alerts_patient_id", "alerts", ["patient_id"])


def downgrade() -> None:
    op.drop_table("alerts")
    op.drop_table("relapses")
    op.drop_table("addictions")
    bind = op.get_bind()
    sa.Enum(name="review_status").drop(bind, checkfirst=True)
    sa.Enum(name="addiction_type").drop(bind, checkfirst=True)
