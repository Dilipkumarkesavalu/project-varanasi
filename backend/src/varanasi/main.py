"""Application factory: wires settings, logging, shared infrastructure and routers."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from varanasi.settings import Environment, Settings, get_settings
from varanasi.shared.cache.redis import check_redis, create_redis
from varanasi.shared.db.engine import check_database, create_engine
from varanasi.shared.health.router import router as health_router
from varanasi.shared.http.correlation import CorrelationIdMiddleware
from varanasi.shared.logging.setup import configure_logging, get_logger
from varanasi.shared.storage import S3Storage

_log = get_logger("varanasi.app")


def build_storage(settings: Settings) -> S3Storage:
    return S3Storage(
        settings.storage_bucket,
        region=settings.storage_region,
        endpoint_url=settings.storage_endpoint_url,
        access_key_id=(
            settings.storage_access_key_id.get_secret_value()
            if settings.storage_access_key_id
            else None
        ),
        secret_access_key=(
            settings.storage_secret_access_key.get_secret_value()
            if settings.storage_secret_access_key
            else None
        ),
    )


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level, settings.log_format)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        engine = create_engine(str(settings.db_platform_url))
        redis = create_redis(str(settings.redis_url))
        storage = build_storage(settings)
        if settings.storage_create_bucket and settings.env is Environment.LOCAL:
            await storage.ensure_bucket()

        app.state.storage = storage
        app.state.health_checks = {
            "database": lambda: check_database(engine),
            "redis": lambda: check_redis(redis),
            "storage": storage.check,
        }
        _log.info("app_started", env=settings.env.value)
        try:
            yield
        finally:
            await redis.aclose()
            await engine.dispose()
            _log.info("app_stopped")

    app = FastAPI(
        title="Varanasi API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url="/docs" if settings.env is not Environment.PRODUCTION else None,
        redoc_url=None,
    )
    if settings.cors_allowed_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_allowed_origins,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
            expose_headers=["X-Correlation-ID", "ETag", "Location"],
        )
    # Added last so it runs first: every request, including CORS preflights, gets an ID.
    app.add_middleware(CorrelationIdMiddleware)
    app.include_router(health_router)
    return app
