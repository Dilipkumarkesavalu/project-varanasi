"""Health endpoints. Public (no token), outside ``/api/v1`` (ADR-0007 §11).

- ``GET /health``: liveness. The process is up. Never touches dependencies.
- ``GET /health/ready``: readiness. Database, Redis and object storage all reachable.
"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from typing import Literal

from fastapi import APIRouter, Request, Response, status
from pydantic import BaseModel

from varanasi.shared.logging.setup import get_logger

CheckFn = Callable[[], Awaitable[None]]
Status = Literal["ok", "error"]

router = APIRouter(tags=["health"])
_log = get_logger("varanasi.health")
_TIMEOUT_SECONDS = 3.0


class Liveness(BaseModel):
    status: Literal["ok"] = "ok"


class Readiness(BaseModel):
    status: Status
    checks: dict[str, Status]


@router.get("/health", response_model=Liveness, summary="Liveness check")
async def health() -> Liveness:
    return Liveness()


async def _run(name: str, check: CheckFn) -> Status:
    try:
        await asyncio.wait_for(check(), timeout=_TIMEOUT_SECONDS)
    except Exception as error:  # noqa: BLE001  # any failure means "not ready"
        _log.warning("health_check_failed", check=name, error=type(error).__name__)
        return "error"
    return "ok"


@router.get(
    "/health/ready",
    response_model=Readiness,
    summary="Readiness check",
    responses={503: {"model": Readiness, "description": "A dependency is unavailable"}},
)
async def ready(request: Request, response: Response) -> Readiness:
    checks: dict[str, CheckFn] = request.app.state.health_checks
    results = await asyncio.gather(*(_run(name, fn) for name, fn in checks.items()))
    outcome = dict(zip(checks, results, strict=True))
    healthy = all(value == "ok" for value in outcome.values())
    if not healthy:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return Readiness(status="ok" if healthy else "error", checks=outcome)
