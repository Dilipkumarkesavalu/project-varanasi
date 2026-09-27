"""Redis client for caching (ADR-0012). Not a message broker: events use RabbitMQ (ADR-0005).

Every cache key for tenant data must start with ``t:{tenant_id}:`` (ADR-0006 layer 4).
"""

from __future__ import annotations

from uuid import UUID

from redis.asyncio import Redis


def create_redis(url: str) -> Redis:
    return Redis.from_url(url, decode_responses=True, socket_timeout=2, socket_connect_timeout=2)


async def check_redis(client: Redis) -> None:
    if not await client.ping():
        raise ConnectionError("Redis did not answer PING")


def tenant_cache_key(tenant_id: UUID, key: str) -> str:
    return f"t:{tenant_id}:{key}"
