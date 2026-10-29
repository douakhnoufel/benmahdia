"""Milestones celebrated and told to the doctor (PRD 5.1)

Revision ID: 0014
Revises: 0013
Create Date: 2026-10-27 12:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0014"
down_revision: str | None = "0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("addictions", sa.Column("milestone_seen", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("addictions", sa.Column("milestone_alerted", sa.Integer(), nullable=False, server_default="0"))


def downgrade() -> None:
    op.drop_column("addictions", "milestone_alerted")
    op.drop_column("addictions", "milestone_seen")
