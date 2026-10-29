"""A doctor may share a visit note with the clinic's other doctors

Revision ID: 0014
Revises: 0013
Create Date: 2026-10-29 14:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0014"
down_revision: str | None = "0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "appointment_notes",
        sa.Column("shared", sa.Boolean(), nullable=False, server_default=sa.false()),
    )


def downgrade() -> None:
    op.drop_column("appointment_notes", "shared")
