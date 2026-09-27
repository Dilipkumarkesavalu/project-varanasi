from __future__ import annotations

from uuid import UUID

import pytest

from varanasi.shared.storage import InMemoryStorage, ObjectNotFoundError, tenant_key

TENANT_A = UUID("0192f19f-11aa-7c00-8e21-5b7d9c4e2f10")


async def test_upload_then_download_returns_same_bytes() -> None:
    storage = InMemoryStorage()

    await storage.upload("a/b.txt", b"hello", "text/plain")
    stored = await storage.download("a/b.txt")

    assert stored.data == b"hello"
    assert stored.content_type == "text/plain"


async def test_download_missing_key_raises() -> None:
    with pytest.raises(ObjectNotFoundError):
        await InMemoryStorage().download("nope")


def test_tenant_key_prefixes_tenant() -> None:
    assert tenant_key(TENANT_A, "/invoices/2026/inv-1.pdf") == (
        f"tenants/{TENANT_A}/invoices/2026/inv-1.pdf"
    )


@pytest.mark.parametrize("path", ["", "/", "../other-tenant/x", "a/../../b", "a b.pdf", "a?.pdf"])
def test_tenant_key_rejects_unsafe_paths(path: str) -> None:
    with pytest.raises(ValueError, match="Unsafe storage path"):
        tenant_key(TENANT_A, path)
