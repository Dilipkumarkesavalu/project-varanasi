"""M1-FOU-014: one request can be followed through the logs by its correlation ID."""

from __future__ import annotations

import io
import json
import re
from typing import Any

import httpx
import pytest
from fastapi import FastAPI

from varanasi.shared.http.correlation import CorrelationIdMiddleware, current_correlation_id
from varanasi.shared.logging.setup import configure_logging, get_logger


def _app() -> FastAPI:
    app = FastAPI()
    app.add_middleware(CorrelationIdMiddleware)
    log = get_logger("test.handler")

    @app.get("/work")
    async def work() -> dict[str, str | None]:
        log.info("work_done", step="inside_handler", password="hunter2")
        return {"seen": current_correlation_id()}

    return app


async def _call(headers: dict[str, str] | None = None) -> httpx.Response:
    transport = httpx.ASGITransport(app=_app())
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        return await client.get("/work", headers=headers or {})


@pytest.fixture(autouse=True)
def log_output() -> io.StringIO:
    stream = io.StringIO()
    configure_logging("INFO", "json", stream=stream)
    return stream


def _log_lines(stream: io.StringIO) -> list[dict[str, Any]]:
    return [json.loads(line) for line in stream.getvalue().splitlines() if line.strip()]


async def test_incoming_correlation_id_is_kept_and_logged(log_output: io.StringIO) -> None:
    response = await _call({"X-Correlation-ID": "req-7f3a9c2e"})

    assert response.headers["x-correlation-id"] == "req-7f3a9c2e"
    assert response.json() == {"seen": "req-7f3a9c2e"}

    lines = _log_lines(log_output)
    handler_line = next(line for line in lines if line["event"] == "work_done")
    request_line = next(line for line in lines if line["event"] == "http_request")
    # Every line produced by the request carries the same ID.
    assert handler_line["correlation_id"] == "req-7f3a9c2e"
    assert request_line["correlation_id"] == "req-7f3a9c2e"
    assert request_line["http_method"] == "GET"
    assert request_line["http_path"] == "/work"
    assert request_line["http_status"] == 200
    assert request_line["duration_ms"] >= 0
    assert request_line["level"] == "info"
    assert "timestamp" in request_line


async def test_missing_correlation_id_is_generated() -> None:
    response = await _call()

    generated = response.headers["x-correlation-id"]
    assert re.fullmatch(r"[0-9a-f]{32}", generated)
    assert response.json() == {"seen": generated}


@pytest.mark.parametrize("bad", ["short", "has spaces in it", "x" * 65, "semi;colon;id"])
async def test_malformed_correlation_id_is_replaced(bad: str) -> None:
    response = await _call({"X-Correlation-ID": bad})

    assert response.headers["x-correlation-id"] != bad
    assert re.fullmatch(r"[0-9a-f]{32}", response.headers["x-correlation-id"])


async def test_correlation_id_does_not_leak_between_requests() -> None:
    first = await _call({"X-Correlation-ID": "first-request-id"})
    second = await _call()

    assert first.json()["seen"] == "first-request-id"
    assert second.json()["seen"] != "first-request-id"
    assert current_correlation_id() is None


async def test_sensitive_values_are_redacted(log_output: io.StringIO) -> None:
    await _call({"X-Correlation-ID": "redaction-check"})

    output = log_output.getvalue()
    assert "hunter2" not in output
    assert "[REDACTED]" in output
