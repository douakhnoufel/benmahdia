"""Data integrity: missing foreign keys, a dangerous cascade, check
constraints and the dashboard's query indexes

- medications.prescribed_by, articles.author_id and addictions.reviewed_by
  now reference doctor_profiles.user_id, ON DELETE RESTRICT: a clinical
  record keeps who wrote it. audit_log.actor_id stays without a foreign key
  on purpose: the audit trail must outlive the account.
- appointment_notes.doctor_id was ON DELETE CASCADE (removing a doctor's
  profile silently deleted their clinical notes); it is now RESTRICT.
- Check constraints for values the API already validates, so the database
  is the last line. The "HH:MM" regex checks on dose_logs.time and
  habits.reminder_time are PostgreSQL syntax.
- Indexes for the clinic-wide day list, the hold expiry, the alerts list,
  the audit log and the article library.

Before each new check constraint and foreign key, the migration counts the
rows that would violate it and stops with an error naming the table and the
constraint (never a row's content). It never deletes or rewrites data.

PostgreSQL only, like the deployment: no SQLite batch mode. Tests build
their tables from the models (app/models.py), which declare the same rules.

Users -> appointments/payments stay ON DELETE CASCADE: their retention policy
is an open PRD question (PRD 16).

Revision ID: 0017
Revises: 0016
Create Date: 2026-10-30 12:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0017"
down_revision: str | None = "0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

HHMM_REGEX = "^([01][0-9]|2[0-3]):[0-5][0-9]$"

# (table, constraint name, condition every row must meet)
CHECKS: list[tuple[str, str, str]] = [
    ("appointments", "ck_appointments_price_dzd", "price_dzd >= 0"),
    ("payments", "ck_payments_amount_dzd", "amount_dzd > 0"),
    ("addiction_checks", "ck_addiction_checks_craving", "craving BETWEEN 1 AND 5"),
    ("addictions", "ck_addictions_goal_days", "goal_days > 0"),
    ("addictions", "ck_addictions_milestone_seen", "milestone_seen >= 0"),
    ("addictions", "ck_addictions_milestone_alerted", "milestone_alerted >= 0"),
    ("addictions", "ck_addictions_longest_past_days", "longest_past_days >= 0"),
    ("addictions", "ck_addictions_past_days", "past_days >= 0"),
    ("medications", "ck_medications_dates", "end_date IS NULL OR end_date >= start_date"),
    ("articles", "ck_articles_language", "language IN ('ar', 'fr')"),
    ("articles", "ck_articles_published_at", "published = false OR published_at IS NOT NULL"),
    ("alerts", "ck_alerts_priority", "priority IN ('normal', 'high')"),
    ("dose_logs", "ck_dose_logs_time", f"\"time\" ~ '{HHMM_REGEX}'"),
    ("habits", "ck_habits_reminder_time", f"reminder_time ~ '{HHMM_REGEX}'"),
]

# (table, constraint name, column) -> doctor_profiles.user_id, ON DELETE RESTRICT
FOREIGN_KEYS: list[tuple[str, str, str]] = [
    ("medications", "fk_medications_prescribed_by", "prescribed_by"),
    ("articles", "fk_articles_author_id", "author_id"),
    ("addictions", "fk_addictions_reviewed_by", "reviewed_by"),
]

# (index name, table, columns)
INDEXES: list[tuple[str, str, list[str]]] = [
    ("ix_appointments_start_utc", "appointments", ["start_utc"]),
    ("ix_appointments_status_hold_expires_at", "appointments", ["status", "hold_expires_at"]),
    ("ix_alerts_created_at", "alerts", ["created_at"]),
    ("ix_audit_log_action_created_at", "audit_log", ["action", "created_at"]),
    ("ix_articles_published_published_at", "articles", ["published", "published_at"]),
]


def _refuse_if_any(table: str, constraint: str, where: str) -> None:
    """Stops the upgrade when rows match [where]; names only the table and
    the constraint, never what the rows hold."""
    count = op.get_bind().execute(sa.text(f"SELECT count(*) FROM {table} WHERE {where}")).scalar()
    if count:
        raise RuntimeError(
            f"0017: {count} row(s) in table {table} violate {constraint}; "
            "correct them by hand, then run the upgrade again."
        )


def upgrade() -> None:
    # A row passes a CHECK when its condition is true or unknown (NULL), so
    # only a condition that is false counts as a violation.
    for table, name, condition in CHECKS:
        _refuse_if_any(table, name, f"({condition}) IS FALSE")
    for table, name, column in FOREIGN_KEYS:
        _refuse_if_any(
            table,
            name,
            f"{column} IS NOT NULL AND NOT EXISTS "
            f"(SELECT 1 FROM doctor_profiles d WHERE d.user_id = {table}.{column})",
        )

    for table, name, condition in CHECKS:
        op.create_check_constraint(name, table, condition)
    for table, name, column in FOREIGN_KEYS:
        op.create_foreign_key(
            name, table, "doctor_profiles", [column], ["user_id"], ondelete="RESTRICT"
        )

    op.drop_constraint("appointment_notes_doctor_id_fkey", "appointment_notes", type_="foreignkey")
    op.create_foreign_key(
        "appointment_notes_doctor_id_fkey",
        "appointment_notes",
        "doctor_profiles",
        ["doctor_id"],
        ["user_id"],
        ondelete="RESTRICT",
    )

    for name, table, columns in INDEXES:
        op.create_index(name, table, columns)


def downgrade() -> None:
    for name, table, _ in reversed(INDEXES):
        op.drop_index(name, table_name=table)

    op.drop_constraint("appointment_notes_doctor_id_fkey", "appointment_notes", type_="foreignkey")
    op.create_foreign_key(
        "appointment_notes_doctor_id_fkey",
        "appointment_notes",
        "doctor_profiles",
        ["doctor_id"],
        ["user_id"],
        ondelete="CASCADE",
    )

    for table, name, _ in reversed(FOREIGN_KEYS):
        op.drop_constraint(name, table, type_="foreignkey")
    for table, name, _ in reversed(CHECKS):
        op.drop_constraint(name, table, type_="check")
