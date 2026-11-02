"""Second declared name for the two-sided national ID scan (PRD 4.2)

The national ID card is now read on both sides: the Arabic name from the
front (kept in name_enc, as before) and the Latin transliteration from the
back MRZ. The transliteration is stored, encrypted like the Arabic name, in a
new nullable column. Passports keep a single name in name_enc, so the column
stays NULL for them and for every declaration made before this change.

Nullable, additive: no existing row is rewritten.

Revision ID: 0019
Revises: 0018
Create Date: 2026-10-31 12:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0019"
down_revision: str | None = "0018"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("id_declarations", sa.Column("name_latin_enc", sa.LargeBinary(), nullable=True))


def downgrade() -> None:
    op.drop_column("id_declarations", "name_latin_enc")
