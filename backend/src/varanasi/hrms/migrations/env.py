"""Alembic environment for the hrms schema."""

from varanasi.shared.db.migrations import run_migrations

run_migrations("hrms")
