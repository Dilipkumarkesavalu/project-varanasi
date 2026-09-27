"""Structured logging (ADR-0008 §11).

JSON lines to stdout on servers, a readable console format locally. Standard-library
loggers (uvicorn, sqlalchemy, …) are routed through the same processors, so every line
has the same shape and carries the request's ``correlation_id`` from the context.
"""

from __future__ import annotations

import logging
import sys
from typing import Any, TextIO

import structlog
from structlog.types import EventDict, Processor, WrappedLogger

# Keys whose values must never reach the logs (ADR-0008 §11 "never log").
_REDACTED_KEYS = frozenset(
    {
        "password",
        "token",
        "access_token",
        "refresh_token",
        "authorization",
        "secret",
        "api_key",
        "pan",
        "aadhaar",
        "bank_account",
        "card_number",
        "salary",
    }
)


def _redact(_: WrappedLogger, __: str, event_dict: EventDict) -> EventDict:
    for key in event_dict.keys() & _REDACTED_KEYS:
        event_dict[key] = "[REDACTED]"
    return event_dict


def configure_logging(level: str = "INFO", fmt: str = "json", stream: TextIO | None = None) -> None:
    stream = stream or sys.stdout
    shared: list[Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
        structlog.processors.TimeStamper(fmt="iso", utc=True, key="timestamp"),
        _redact,
    ]
    renderer: Processor = (
        structlog.processors.JSONRenderer()
        if fmt == "json"
        else structlog.dev.ConsoleRenderer(colors=stream.isatty())
    )

    structlog.configure(
        processors=[*shared, structlog.stdlib.ProcessorFormatter.wrap_for_formatter],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

    handler = logging.StreamHandler(stream)
    handler.setFormatter(
        structlog.stdlib.ProcessorFormatter(
            foreign_pre_chain=shared,
            processors=[
                structlog.stdlib.ProcessorFormatter.remove_processors_meta,
                structlog.processors.format_exc_info,
                renderer,
            ],
        )
    )
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper())

    # We write our own request log line (with correlation_id); silence the duplicate.
    logging.getLogger("uvicorn.access").disabled = True
    for name in ("uvicorn", "uvicorn.error"):
        logging.getLogger(name).handlers = []
        logging.getLogger(name).propagate = True


def get_logger(name: str | None = None, **initial: Any) -> structlog.stdlib.BoundLogger:
    logger: structlog.stdlib.BoundLogger = structlog.stdlib.get_logger(name)
    return logger.bind(**initial) if initial else logger
