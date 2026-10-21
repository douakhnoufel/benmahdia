"""appointment check-in code and arrival time

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-17 23:30:00
"""
import secrets
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Same alphabet and length as app/checkin.py (copied so this migration never
# changes if the app code does).
_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
_LENGTH = 6


def upgrade() -> None:
    op.add_column("appointments", sa.Column("checkin_code", sa.String(length=8), nullable=True))
    op.add_column("appointments", sa.Column("checked_in_at", sa.DateTime(), nullable=True))
    op.create_unique_constraint("uq_appointments_checkin_code", "appointments", ["checkin_code"])

    # Appointments confirmed before this migration get a code as well.
    bind = op.get_bind()
    ids = bind.execute(
        sa.text("SELECT id FROM appointments WHERE status = 'confirmed' AND checkin_code IS NULL")
    ).scalars().all()
    used: set[str] = set()
    for appointment_id in ids:
        code = ""
        while not code or code in used:
            code = "".join(secrets.choice(_ALPHABET) for _ in range(_LENGTH))
        used.add(code)
        bind.execute(
            sa.text("UPDATE appointments SET checkin_code = :code WHERE id = :id"),
            {"code": code, "id": appointment_id},
        )


def downgrade() -> None:
    op.drop_constraint("uq_appointments_checkin_code", "appointments", type_="unique")
    op.drop_column("appointments", "checked_in_at")
    op.drop_column("appointments", "checkin_code")
