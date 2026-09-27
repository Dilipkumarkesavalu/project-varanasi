"""Shared Alembic runner. Each module has its own history and schema (ADR-0008 §5).

Version tables live in ``public`` as ``alembic_version_<module>`` so that a module's
first migration can create (and its downgrade can drop) the module schema itself.
"""

from __future__ import annotations

from alembic import context
from sqlalchemy import create_engine, pool

from varanasi.settings import MigrationSettings
from varanasi.shared.db.engine import psycopg_url


def run_migrations(module: str) -> None:
    config = context.config
    url = config.get_main_option("sqlalchemy.url") or str(MigrationSettings().db_migrator_url)
    version_table = f"alembic_version_{module}"

    if context.is_offline_mode():
        context.configure(url=psycopg_url(url), version_table=version_table, literal_binds=True)
        with context.begin_transaction():
            context.run_migrations()
        return

    engine = create_engine(psycopg_url(url), poolclass=pool.NullPool)
    with engine.connect() as connection:
        context.configure(
            connection=connection,
            version_table=version_table,
            version_table_schema="public",
            include_schemas=True,
            include_name=lambda name, type_, _parent: type_ != "schema" or name == module,
        )
        with context.begin_transaction():
            context.run_migrations()
    engine.dispose()
