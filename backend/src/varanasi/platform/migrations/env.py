"""Alembic environment for the platform schema."""

from varanasi.shared.db.migrations import run_migrations

run_migrations("platform")
