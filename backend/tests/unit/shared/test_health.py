from __future__ import annotations

import httpx
from fastapi import FastAPI

from tests.factories.settings import make_settings
from varanasi.main import create_app
from varanasi.shared.health.router import router


async def _ok() -> None:
    return None


async def _broken() -> None:
    raise ConnectionError("down")


def _client(app: FastAPI) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")


async def test_health_returns_ok_without_touching_dependencies() -> None:
    # The lifespan (which connects to dependencies) is not run by ASGITransport.
    app = create_app(make_settings())

    async with _client(app) as client:
        response = await client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert "x-correlation-id" in response.headers


async def test_ready_is_ok_when_all_checks_pass() -> None:
    app = FastAPI()
    app.include_router(router)
    app.state.health_checks = {"database": _ok, "redis": _ok, "storage": _ok}

    async with _client(app) as client:
        response = await client.get("/health/ready")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "checks": {"database": "ok", "redis": "ok", "storage": "ok"},
    }


async def test_ready_is_503_and_names_the_failing_dependency() -> None:
    app = FastAPI()
    app.include_router(router)
    app.state.health_checks = {"database": _ok, "redis": _broken, "storage": _ok}

    async with _client(app) as client:
        response = await client.get("/health/ready")

    assert response.status_code == 503
    assert response.json()["checks"] == {"database": "ok", "redis": "error", "storage": "ok"}
