"""ID declarations (PRD 4.2)

Revision ID: 0006
Revises: 0005
Create Date: 2026-10-18 00:10:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "id_declarations",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("id_hmac", sa.String(length=64), nullable=False),
        sa.Column("name_enc", sa.LargeBinary(), nullable=False),
        sa.Column("birth_enc", sa.LargeBinary(), nullable=False),
        sa.Column("selfie_file", sa.String(length=64), nullable=True),
        sa.Column(
            "status",
            sa.Enum("declared", "approved", "rejected", name="id_status"),
            nullable=False,
        ),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("reject_reason", sa.String(length=200), nullable=True),
        sa.Column("declared_at", sa.DateTime(), nullable=False),
        sa.Column("decided_at", sa.DateTime(), nullable=True),
        sa.Column("decided_by", sa.Uuid(), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("user_id"),
        sa.UniqueConstraint("id_hmac"),
    )


def downgrade() -> None:
    op.drop_table("id_declarations")
    sa.Enum(name="id_status").drop(op.get_bind(), checkfirst=True)
