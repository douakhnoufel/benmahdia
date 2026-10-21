"""Document type of an ID declaration: national ID card or passport

Revision ID: 0007
Revises: 0006
Create Date: 2026-10-21 23:55:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "id_declarations",
        sa.Column(
            "id_type",
            sa.String(length=16),
            nullable=False,
            server_default="national_id",
        ),
    )


def downgrade() -> None:
    op.drop_column("id_declarations", "id_type")
