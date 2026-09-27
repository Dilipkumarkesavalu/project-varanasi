"""Settings builders for tests. Values are local test fixtures, never real credentials."""

from __future__ import annotations

from typing import Any

from varanasi.settings import Settings

TEST_ENV: dict[str, str] = {
    "VARANASI_ENV": "test",
    "VARANASI_LOG_FORMAT": "json",
    "VARANASI_DB_PLATFORM_URL": "postgresql://platform:pw@localhost:5432/varanasi",
    "VARANASI_DB_BILLING_URL": "postgresql://billing:pw@localhost:5432/varanasi",
    "VARANASI_DB_HRMS_URL": "postgresql://hrms:pw@localhost:5432/varanasi",
    "VARANASI_DB_MIGRATOR_URL": "postgresql://migrator:pw@localhost:5432/varanasi",
    "VARANASI_REDIS_URL": "redis://localhost:6379/0",
    "VARANASI_STORAGE_BUCKET": "varanasi-test",
}


def make_settings(**overrides: Any) -> Settings:
    values: dict[str, Any] = {
        key.removeprefix("VARANASI_").lower(): value for key, value in TEST_ENV.items()
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)
