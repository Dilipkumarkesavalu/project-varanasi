"""M1-FOU-010: every module's migrations upgrade and downgrade cleanly on an empty database."""

from __future__ import annotations

from pathlib import Path

import psycopg
import pytest
from alembic import command
from alembic.config import Config
from alembic.script import ScriptDirectory

from tests.fixtures.containers import PostgresInfo

MODULES = ["platform", "billing", "hrms"]
_ALEMBIC_INI = Path(__file__).parents[2] / "alembic.ini"


def _config(module: str, postgres: PostgresInfo) -> Config:
    config = Config(str(_ALEMBIC_INI), ini_section=module)
    config.set_main_option("sqlalchemy.url", postgres.migrator_url)
    return config


def _query(postgres: PostgresInfo, sql: str, *params: object) -> list[tuple[object, ...]]:
    with psycopg.connect(postgres.superuser_url) as connection:
        return connection.execute(sql, params).fetchall()


def _schema_owner(postgres: PostgresInfo, schema: str) -> list[tuple[object, ...]]:
    return _query(
        postgres,
        "SELECT nspowner::regrole::text FROM pg_namespace WHERE nspname = %s",
        schema,
    )


@pytest.mark.parametrize("module", MODULES)
def test_upgrade_then_downgrade_on_empty_database(module: str, postgres: PostgresInfo) -> None:
    config = _config(module, postgres)

    command.upgrade(config, "head")
    assert _schema_owner(postgres, module) == [("varanasi_migrator",)]
    app_role = f"varanasi_{module}_app"
    assert _query(postgres, "SELECT has_schema_privilege(%s, %s, 'USAGE')", app_role, module) == [
        (True,)
    ]

    command.downgrade(config, "base")
    assert _schema_owner(postgres, module) == []

    # Stairway: going up again after a full downgrade must still work (ADR-0009 §3.5).
    command.upgrade(config, "head")
    assert _schema_owner(postgres, module) == [("varanasi_migrator",)]
    command.downgrade(config, "base")


@pytest.mark.parametrize("module", MODULES)
def test_each_module_has_a_single_head(module: str, postgres: PostgresInfo) -> None:
    heads = ScriptDirectory.from_config(_config(module, postgres)).get_heads()

    assert len(heads) == 1, f"{module} has diverging migration heads: {heads}"


@pytest.mark.parametrize("module", MODULES)
def test_runtime_role_cannot_create_objects_in_schema(module: str, postgres: PostgresInfo) -> None:
    # Only the migrator changes schemas; the runtime role gets data access only (ADR-0006).
    config = _config(module, postgres)
    command.upgrade(config, "head")
    try:
        role = f"varanasi_{module}_app"
        assert _query(postgres, "SELECT has_schema_privilege(%s, %s, 'CREATE')", role, module) == [
            (False,)
        ]
    finally:
        command.downgrade(config, "base")
