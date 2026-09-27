"""Correlation ID + request log middleware (ADR-0007 §10, ADR-0008 §11).

Accepts a well-formed ``X-Correlation-ID`` from the client or generates one, binds it to
the logging context for everything the request does, returns it in the response, and
writes exactly one ``http_request`` log line per request.
"""

from __future__ import annotations

import re
import time
import uuid
from contextvars import ContextVar

import structlog
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from varanasi.shared.logging.setup import get_logger

HEADER = "x-correlation-id"
_VALID = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
_current: ContextVar[str | None] = ContextVar("correlation_id", default=None)

_log = get_logger("varanasi.http")


def current_correlation_id() -> str | None:
    """The correlation ID of the request being handled, if any."""
    return _current.get()


def new_correlation_id() -> str:
    return uuid.uuid4().hex


class CorrelationIdMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        incoming = dict(scope["headers"]).get(HEADER.encode(), b"").decode("latin-1")
        correlation_id = incoming if _VALID.fullmatch(incoming) else new_correlation_id()

        token = _current.set(correlation_id)
        structlog.contextvars.bind_contextvars(correlation_id=correlation_id)
        status_code = 500
        started = time.perf_counter()

        async def send_with_header(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                headers = list(message.get("headers", []))
                headers.append((HEADER.encode(), correlation_id.encode()))
                message["headers"] = headers
            await send(message)

        try:
            await self.app(scope, receive, send_with_header)
        finally:
            _log.info(
                "http_request",
                http_method=scope["method"],
                http_path=scope["path"],
                http_status=status_code,
                duration_ms=round((time.perf_counter() - started) * 1000, 2),
            )
            structlog.contextvars.unbind_contextvars("correlation_id")
            _current.reset(token)
