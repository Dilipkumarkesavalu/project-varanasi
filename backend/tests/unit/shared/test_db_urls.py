from __future__ import annotations

import pytest

from varanasi.shared.db.engine import asyncpg_url, psycopg_url


@pytest.mark.parametrize(
    "url",
    [
        "postgresql://u:p@db:5432/varanasi",
        "postgres://u:p@db:5432/varanasi",
        "postgresql+psycopg://u:p@db:5432/varanasi",
    ],
)
def test_runtime_url_uses_asyncpg(url: str) -> None:
    assert asyncpg_url(url) == "postgresql+asyncpg://u:p@db:5432/varanasi"


def test_sslmode_is_renamed_for_asyncpg_but_kept_for_psycopg() -> None:
    url = "postgresql://u:p@rds.example:5432/varanasi?sslmode=require"

    assert asyncpg_url(url) == "postgresql+asyncpg://u:p@rds.example:5432/varanasi?ssl=require"
    assert psycopg_url(url) == "postgresql+psycopg://u:p@rds.example:5432/varanasi?sslmode=require"
