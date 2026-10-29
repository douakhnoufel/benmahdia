"""Doctors' private notes after a visit (PRD 4.3)

Revision ID: 0013
Revises: 0012
Create Date: 2026-10-29 10:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0013"
down_revision: str | None = "0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "appointment_notes",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("appointment_id", sa.Uuid(), nullable=False),
        sa.Column("doctor_id", sa.Uuid(), nullable=False),
        sa.Column("text_enc", sa.LargeBinary(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["appointment_id"], ["appointments.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["doctor_id"], ["doctor_profiles.user_id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("appointment_id"),
    )
    op.create_index("ix_appointment_notes_doctor_id", "appointment_notes", ["doctor_id"])


def downgrade() -> None:
    op.drop_table("appointment_notes")
