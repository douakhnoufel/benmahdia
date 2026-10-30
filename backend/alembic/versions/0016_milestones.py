"""Milestones celebrated and told to the doctor (PRD 5.1)

Revision ID: 0016
Revises: 0015
Create Date: 2026-10-27 12:00:00
"""
from collections.abc import Sequence
from datetime import datetime, timezone

import sqlalchemy as sa
from alembic import op

from app.substances import reached_milestone

revision: str = "0016"
down_revision: str | None = "0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("addictions", sa.Column("milestone_seen", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("addictions", sa.Column("milestone_alerted", sa.Integer(), nullable=False, server_default="0"))
    # Existing streaks start at the milestone they already reached: else the
    # first nightly run alerts every doctor once per tracked addiction and
    # every patient sees a celebration for an old milestone. Computed with the
    # app's own ladder, at this migration's "now" (naive UTC, like the app).
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    addictions = sa.table(
        "addictions",
        sa.column("id", sa.Uuid()),
        sa.column("sobriety_start", sa.DateTime()),
        sa.column("milestone_seen", sa.Integer()),
        sa.column("milestone_alerted", sa.Integer()),
    )
    bind = op.get_bind()
    rows = bind.execute(sa.select(addictions.c.id, addictions.c.sobriety_start)).all()
    for row_id, start in rows:
        reached = reached_milestone(max(0, (now - start).days))
        if reached:
            bind.execute(
                addictions.update()
                .where(addictions.c.id == row_id)
                .values(milestone_seen=reached, milestone_alerted=reached)
            )


def downgrade() -> None:
    op.drop_column("addictions", "milestone_alerted")
    op.drop_column("addictions", "milestone_seen")
