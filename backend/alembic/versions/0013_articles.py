"""Articles and patient favourites (PRD 5.5)

Revision ID: 0013
Revises: 0012
Create Date: 2026-10-27 10:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0013"
down_revision: str | None = "0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

TOPICS = ("addiction", "cravings", "relapse", "medication", "family", "motivation")


def upgrade() -> None:
    op.create_table(
        "articles",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("author_id", sa.Uuid(), nullable=False),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("language", sa.String(length=2), nullable=False),
        sa.Column("topic", sa.Enum(*TOPICS, name="article_topic"), nullable=False),
        sa.Column("addiction_type", sa.String(length=16), nullable=True),
        sa.Column("published", sa.Boolean(), nullable=False),
        sa.Column("published_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "article_favourites",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("patient_id", sa.Uuid(), nullable=False),
        sa.Column("article_id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["patient_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["article_id"], ["articles.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("patient_id", "article_id"),
    )
    op.create_index("ix_article_favourites_patient_id", "article_favourites", ["patient_id"])
    op.create_index("ix_article_favourites_article_id", "article_favourites", ["article_id"])


def downgrade() -> None:
    op.drop_table("article_favourites")
    op.drop_table("articles")
    sa.Enum(name="article_topic").drop(op.get_bind(), checkfirst=True)
