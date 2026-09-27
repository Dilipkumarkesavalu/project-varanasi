"""M1-FOU-009: a test file uploads and downloads through the Storage interface."""

from __future__ import annotations

from uuid import uuid4

import pytest

from tests.fixtures.containers import STORAGE_ACCESS_KEY, STORAGE_SECRET_KEY
from varanasi.shared.storage import ObjectNotFoundError, S3Storage, Storage, tenant_key


@pytest.fixture
async def storage(storage_endpoint: str) -> S3Storage:
    s3 = S3Storage(
        "storage-test",
        region="ap-south-1",
        endpoint_url=storage_endpoint,
        access_key_id=STORAGE_ACCESS_KEY,
        secret_access_key=STORAGE_SECRET_KEY,
    )
    await s3.ensure_bucket()
    return s3


async def test_file_uploads_and_downloads(storage: Storage) -> None:
    key = tenant_key(uuid4(), "documents/hello.txt")
    content = "Namaste from Varanasi ✓".encode()

    await storage.upload(key, content, "text/plain; charset=utf-8")
    stored = await storage.download(key)

    assert stored.data == content
    assert stored.content_type == "text/plain; charset=utf-8"


async def test_binary_file_round_trips_unchanged(storage: Storage) -> None:
    key = tenant_key(uuid4(), "exports/blob.bin")
    content = bytes(range(256)) * 4096  # 1 MiB with every byte value

    await storage.upload(key, content)

    assert (await storage.download(key)).data == content


async def test_missing_object_raises_not_found(storage: Storage) -> None:
    with pytest.raises(ObjectNotFoundError):
        await storage.download(tenant_key(uuid4(), "does/not/exist.pdf"))


async def test_storage_check_passes(storage: Storage) -> None:
    await storage.check()
