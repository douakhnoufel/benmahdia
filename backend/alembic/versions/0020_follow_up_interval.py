"""Follow-up interval chosen by the doctor per visit

After a visit the doctor picks when the next one should be: 15 days
(high-risk), 30 (default) or 60 (stable). The follow-up is then bookable only
within two days of that target. NULL keeps the default of 30 days.

Nullable, additive: no existing row is rewritten.

Revision ID: 0020
Revises: 0019
Create Date: 2026-11-02 12:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0020"
down_revision: str | None = "0019"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("appointments") as batch:
        batch.add_column(sa.Column("next_follow_up_days", sa.Integer(), nullable=True))
        batch.create_check_constraint(
            "ck_appointments_next_follow_up_days",
            "next_follow_up_days IS NULL OR next_follow_up_days IN (15, 30, 60)",
        )


def downgrade() -> None:
    with op.batch_alter_table("appointments") as batch:
        batch.drop_constraint("ck_appointments_next_follow_up_days", type_="check")
        batch.drop_column("next_follow_up_days")
