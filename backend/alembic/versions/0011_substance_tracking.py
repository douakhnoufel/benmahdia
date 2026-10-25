"""Substance profiles and per-addiction daily checks (PRD 5.6)

Revision ID: 0011
Revises: 0010
Create Date: 2026-10-25 18:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

PROFILES = ("nicotine", "thc", "pregabalin", "buprenorphine", "cocaine", "amphetamines")


def upgrade() -> None:
    if op.get_context().dialect.name == "postgresql":
        # A new enum value cannot be added inside the migration's transaction
        # on older PostgreSQL versions.
        with op.get_context().autocommit_block():
            op.execute("ALTER TYPE addiction_type ADD VALUE IF NOT EXISTS 'stimulants'")
    profile = sa.Enum(*PROFILES, name="substance_profile")
    profile.create(op.get_bind(), checkfirst=True)
    op.add_column("addictions", sa.Column("profile", profile, nullable=True))
    op.create_table(
        "addiction_checks",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("addiction_id", sa.Uuid(), nullable=False),
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("used", sa.Boolean(), nullable=False),
        sa.Column("craving", sa.Integer(), nullable=False),
        sa.Column("signals", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["addiction_id"], ["addictions.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("addiction_id", "day"),
    )
    op.create_index("ix_addiction_checks_addiction_id", "addiction_checks", ["addiction_id"])


def downgrade() -> None:
    # The 'stimulants' addiction type stays: PostgreSQL cannot drop an enum value.
    op.drop_table("addiction_checks")
    op.drop_column("addictions", "profile")
    sa.Enum(name="substance_profile").drop(op.get_bind(), checkfirst=True)
