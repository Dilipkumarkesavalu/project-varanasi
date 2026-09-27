"""Object storage interface (M1-FOU-009).

Business code depends only on :class:`Storage`. Locally it is backed by RustFS, in AWS
by S3 (ADR-0011, ADR-0012), and in unit tests by :class:`InMemoryStorage`.

Keys for tenant data must start with the tenant prefix (ADR-0006 layer 4); use
:func:`tenant_key` to build them.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Protocol
from uuid import UUID

_SAFE_PATH = re.compile(r"^[A-Za-z0-9._\-/]+$")


class ObjectNotFoundError(Exception):
    """Raised when a key does not exist in the bucket."""

    def __init__(self, key: str) -> None:
        super().__init__(f"Object not found: {key}")
        self.key = key


@dataclass(frozen=True, slots=True)
class StoredObject:
    key: str
    data: bytes
    content_type: str


class Storage(Protocol):
    async def upload(
        self, key: str, data: bytes, content_type: str = "application/octet-stream"
    ) -> None: ...

    async def download(self, key: str) -> StoredObject: ...

    async def check(self) -> None:
        """Raise if the storage backend is unreachable (used by the readiness check)."""
        ...


def tenant_key(tenant_id: UUID, path: str) -> str:
    """Build a storage key inside the tenant's prefix: ``tenants/{tenant_id}/{path}``."""
    clean = path.strip("/")
    if not clean or ".." in clean.split("/") or not _SAFE_PATH.fullmatch(clean):
        raise ValueError(f"Unsafe storage path: {path!r}")
    return f"tenants/{tenant_id}/{clean}"


class InMemoryStorage:
    """Test double with the same behaviour as the real backends."""

    def __init__(self) -> None:
        self._objects: dict[str, StoredObject] = {}

    async def upload(
        self, key: str, data: bytes, content_type: str = "application/octet-stream"
    ) -> None:
        self._objects[key] = StoredObject(key=key, data=bytes(data), content_type=content_type)

    async def download(self, key: str) -> StoredObject:
        try:
            return self._objects[key]
        except KeyError:
            raise ObjectNotFoundError(key) from None

    async def check(self) -> None:
        return None
