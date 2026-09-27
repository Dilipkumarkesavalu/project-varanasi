"""Real dependencies for integration/migration tests (ADR-0009 §3.2), via Testcontainers.

Images are the same pinned versions as docker-compose.yml. Containers start lazily, once
per test session, only when a test asks for them.
"""

from __future__ import annotations

import time
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

import httpx
import psycopg
import pytest
from testcontainers.community.postgres import PostgresContainer
from testcontainers.community.redis import RedisContainer
from testcontainers.core.container import DockerContainer

POSTGRES_IMAGE = "postgres:17.11"
REDIS_IMAGE = "redis:7.4.11-alpine"
STORAGE_IMAGE = "rustfs/rustfs:1.0.0"

DB_NAME = "varanasi"
SUPERUSER_PASSWORD = "test-superuser"
ROLE_PASSWORDS = {
    "migrator_pw": "test-migrator",
    "platform_pw": "test-platform",
    "billing_pw": "test-billing",
    "hrms_pw": "test-hrms",
}
STORAGE_ACCESS_KEY = "test-access-key"
STORAGE_SECRET_KEY = "test-secret-key"

_ROLES_SQL = Path(__file__).parents[3] / "infra" / "postgres" / "init" / "roles.sql.tpl"


@dataclass(frozen=True)
class PostgresInfo:
    host: str
    port: int

    def url(self, user: str, password: str) -> str:
        return f"postgresql://{user}:{password}@{self.host}:{self.port}/{DB_NAME}"

    @property
    def superuser_url(self) -> str:
        return self.url("postgres", SUPERUSER_PASSWORD)

    @property
    def migrator_url(self) -> str:
        return self.url("varanasi_migrator", ROLE_PASSWORDS["migrator_pw"])

    def app_url(self, module: str) -> str:
        return self.url(f"varanasi_{module}_app", ROLE_PASSWORDS[f"{module}_pw"])


def _render_roles_sql() -> str:
    """Apply the same roles script the dev container uses, filling in psql variables."""
    sql = _ROLES_SQL.read_text(encoding="utf-8")
    for name, value in ROLE_PASSWORDS.items():
        sql = sql.replace(f":'{name}'", f"'{value}'")
    return sql.replace(':"dbname"', f'"{DB_NAME}"')


@pytest.fixture(scope="session")
def postgres() -> Iterator[PostgresInfo]:
    with PostgresContainer(
        POSTGRES_IMAGE, username="postgres", password=SUPERUSER_PASSWORD, dbname=DB_NAME
    ) as container:
        info = PostgresInfo(
            host=container.get_container_host_ip(),
            port=int(container.get_exposed_port(5432)),
        )
        with psycopg.connect(info.superuser_url, autocommit=True) as connection:
            connection.execute(_render_roles_sql())
        yield info


@pytest.fixture(scope="session")
def redis_url() -> Iterator[str]:
    with RedisContainer(REDIS_IMAGE) as container:
        host = container.get_container_host_ip()
        yield f"redis://{host}:{container.get_exposed_port(6379)}/0"


@pytest.fixture(scope="session")
def storage_endpoint() -> Iterator[str]:
    container = (
        DockerContainer(STORAGE_IMAGE)
        .with_env("RUSTFS_ACCESS_KEY", STORAGE_ACCESS_KEY)
        .with_env("RUSTFS_SECRET_KEY", STORAGE_SECRET_KEY)
        .with_exposed_ports(9000)
    )
    with container:
        endpoint = f"http://{container.get_container_host_ip()}:{container.get_exposed_port(9000)}"
        _wait_until_healthy(f"{endpoint}/health")
        yield endpoint


def _wait_until_healthy(url: str, timeout: float = 30.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if httpx.get(url, timeout=1).status_code == httpx.codes.OK:
                return
        except httpx.HTTPError:
            pass
        time.sleep(0.5)
    raise TimeoutError(f"{url} did not become healthy within {timeout}s")
