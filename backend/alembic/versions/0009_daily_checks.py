"""Daily checks and the reminder time (PRD 5.4)

Revision ID: 0009
Revises: 0008
Create Date: 2026-10-22 18:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("reminder_time", sa.String(length=5), nullable=True))
    op.create_table(
        "daily_checks",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("patient_id", sa.Uuid(), nullable=False),
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["patient_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("patient_id", "day"),
    )
    op.create_index("ix_daily_checks_patient_id", "daily_checks", ["patient_id"])


def downgrade() -> None:
    op.drop_table("daily_checks")
    op.drop_column("users", "reminder_time")
