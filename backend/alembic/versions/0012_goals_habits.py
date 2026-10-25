"""Small goals and good habits (PRD 5.6)

Revision ID: 0012
Revises: 0011
Create Date: 2026-10-26 10:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

KINDS = ("sport", "brush_teeth", "water", "reading", "call_family", "sleep", "custom")


def upgrade() -> None:
    op.add_column("addictions", sa.Column("goal_days", sa.Integer(), nullable=True))
    op.create_table(
        "habits",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("patient_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.Enum(*KINDS, name="habit_kind"), nullable=False),
        sa.Column("text", sa.String(length=60), nullable=True),
        sa.Column("reminder_time", sa.String(length=5), nullable=True),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["patient_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_habits_patient_id", "habits", ["patient_id"])
    op.create_table(
        "habit_logs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("habit_id", sa.Uuid(), nullable=False),
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["habit_id"], ["habits.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("habit_id", "day"),
    )
    op.create_index("ix_habit_logs_habit_id", "habit_logs", ["habit_id"])


def downgrade() -> None:
    op.drop_table("habit_logs")
    op.drop_table("habits")
    sa.Enum(name="habit_kind").drop(op.get_bind(), checkfirst=True)
    op.drop_column("addictions", "goal_days")
