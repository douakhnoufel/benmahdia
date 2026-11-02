"""Craving logs for the difficult-moment screen

One row per difficult moment: the craving intensity (1-10) when it started,
the HALT states the patient named (hungry, angry, lonely, tired) and the
intensity once it passed. No free text.

Additive: a new table, no existing row is rewritten.

Revision ID: 0021
Revises: 0020
Create Date: 2026-11-02 14:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0021"
down_revision: str | None = "0020"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "craving_logs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("patient_id", sa.Uuid(), nullable=False),
        sa.Column("intensity_before", sa.Integer(), nullable=False),
        sa.Column("intensity_after", sa.Integer(), nullable=True),
        sa.Column("halt", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("passed_at", sa.DateTime(), nullable=True),
        sa.CheckConstraint("intensity_before BETWEEN 1 AND 10", name="ck_craving_logs_before"),
        sa.CheckConstraint(
            "intensity_after IS NULL OR intensity_after BETWEEN 1 AND 10",
            name="ck_craving_logs_after",
        ),
        sa.ForeignKeyConstraint(["patient_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_craving_logs_patient_id", "craving_logs", ["patient_id"])


def downgrade() -> None:
    op.drop_table("craving_logs")
