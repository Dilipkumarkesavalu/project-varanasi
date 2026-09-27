"""M1-FOU-008/002: the running app reports real dependency health."""

from __future__ import annotations

import httpx
import psycopg

from tests.factories.settings import make_settings
from tests.fixtures.containers import STORAGE_ACCESS_KEY, STORAGE_SECRET_KEY, PostgresInfo
from varanasi.main import create_app
from varanasi.settings import Settings


def _settings(postgres: PostgresInfo, redis_url: str, storage_endpoint: str) -> Settings:
    return make_settings(
        db_platform_url=postgres.app_url("platform"),
        db_billing_url=postgres.app_url("billing"),
        db_hrms_url=postgres.app_url("hrms"),
        db_migrator_url=postgres.migrator_url,
        redis_url=redis_url,
        storage_endpoint_url=storage_endpoint,
        storage_access_key_id=STORAGE_ACCESS_KEY,
        storage_secret_access_key=STORAGE_SECRET_KEY,
        storage_bucket="readiness-test",
        env="local",
        storage_create_bucket=True,
    )


async def _get_ready(settings: Settings) -> httpx.Response:
    app = create_app(settings)
    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.get("/health/ready")


async def test_ready_when_database_redis_and_storage_are_up(
    postgres: PostgresInfo, redis_url: str, storage_endpoint: str
) -> None:
    response = await _get_ready(_settings(postgres, redis_url, storage_endpoint))

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "checks": {"database": "ok", "redis": "ok", "storage": "ok"},
    }


async def test_ready_reports_redis_unhealthy_when_unreachable(
    postgres: PostgresInfo, storage_endpoint: str
) -> None:
    unreachable = "redis://127.0.0.1:1/0"

    response = await _get_ready(_settings(postgres, unreachable, storage_endpoint))

    assert response.status_code == 503
    assert response.json()["checks"] == {"database": "ok", "redis": "error", "storage": "ok"}


def test_module_role_is_not_superuser(postgres: PostgresInfo) -> None:
    # ADR-0006 layer 3: runtime roles must not bypass RLS.
    with psycopg.connect(postgres.app_url("platform")) as connection:
        row = connection.execute(
            "SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user"
        ).fetchone()

    assert row == (False, False)
