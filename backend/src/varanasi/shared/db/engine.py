"""Database engines, one per module role (ADR-0003, ADR-0006).

The tenant-aware session (``SET LOCAL app.tenant_id``) is added in the next milestone
together with the first business tables; M1 only needs connectivity and health.
"""

from __future__ import annotations

from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

_PREFIXES = ("postgresql+asyncpg://", "postgresql+psycopg://", "postgresql://", "postgres://")


def _with_driver(url: str, driver: str) -> str:
    for prefix in _PREFIXES:
        if url.startswith(prefix):
            return f"postgresql+{driver}://" + url.removeprefix(prefix)
    return url


def asyncpg_url(url: str) -> str:
    """Runtime driver: asyncpg (works on every OS event loop, including Windows).

    Settings use libpq's ``sslmode=`` (understood by psycopg/Alembic); asyncpg calls the
    same option ``ssl=``, so it is renamed here.
    """
    parts = urlsplit(_with_driver(url, "asyncpg"))
    query = [("ssl" if key == "sslmode" else key, value) for key, value in parse_qsl(parts.query)]
    return urlunsplit(parts._replace(query=urlencode(query)))


def psycopg_url(url: str) -> str:
    """Migration driver: synchronous psycopg 3 (used by Alembic)."""
    return _with_driver(url, "psycopg")


def create_engine(url: str) -> AsyncEngine:
    return create_async_engine(asyncpg_url(url), pool_pre_ping=True, pool_size=5, max_overflow=5)


async def check_database(engine: AsyncEngine) -> None:
    async with engine.connect() as connection:
        await connection.execute(text("SELECT 1"))
