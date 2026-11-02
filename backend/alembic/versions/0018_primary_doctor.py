"""Primary doctor: the doctor of a patient's first confirmed booking

A label only ("my doctor" in the app and the dashboard). Every doctor of the
clinic still reads every clinic patient's file and receives the alerts (PRD 3),
so nothing here limits access. The table is separate from users so users and
doctor_profiles keep no circular foreign key.

Existing patients are filled in from their earliest booking that was ever
confirmed (any status but awaiting_payment), ties broken by the appointment id.

PostgreSQL only, like the deployment. Tests build their tables from the
models (app/models.py).

Revision ID: 0018
Revises: 0017
Create Date: 2026-10-30 15:30:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0018"
down_revision: str | None = "0017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "primary_doctors",
        sa.Column("patient_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column(
            "doctor_id",
            sa.Uuid(),
            sa.ForeignKey("doctor_profiles.user_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("set_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_primary_doctors_doctor_id", "primary_doctors", ["doctor_id"])
    op.execute(
        """
        INSERT INTO primary_doctors (patient_id, doctor_id, set_at)
        SELECT DISTINCT ON (patient_id) patient_id, doctor_id, created_at
        FROM appointments
        WHERE status <> 'awaiting_payment'
        ORDER BY patient_id, created_at, id
        """
    )


def downgrade() -> None:
    op.drop_index("ix_primary_doctors_doctor_id", table_name="primary_doctors")
    op.drop_table("primary_doctors")
