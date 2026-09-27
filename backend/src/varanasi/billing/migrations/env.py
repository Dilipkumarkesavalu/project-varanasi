"""Alembic environment for the billing schema."""

from varanasi.shared.db.migrations import run_migrations

run_migrations("billing")
