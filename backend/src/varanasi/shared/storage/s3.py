"""S3-compatible storage: AWS S3 in staging/production, RustFS locally."""

from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

from varanasi.shared.storage.base import ObjectNotFoundError, StoredObject

if TYPE_CHECKING:
    from mypy_boto3_s3.client import S3Client

_NOT_FOUND = frozenset({"NoSuchKey", "404", "NotFound"})


class S3Storage:
    def __init__(
        self,
        bucket: str,
        *,
        region: str,
        endpoint_url: str | None = None,
        access_key_id: str | None = None,
        secret_access_key: str | None = None,
    ) -> None:
        self._bucket = bucket
        # When no keys are given, boto3 uses the AWS instance role (ADR-0011: no static keys).
        self._client: S3Client = boto3.client(
            "s3",
            region_name=region,
            endpoint_url=endpoint_url,
            aws_access_key_id=access_key_id,
            aws_secret_access_key=secret_access_key,
            config=Config(
                s3={"addressing_style": "path" if endpoint_url else "auto"},
                retries={"max_attempts": 3, "mode": "standard"},
            ),
        )

    async def upload(
        self, key: str, data: bytes, content_type: str = "application/octet-stream"
    ) -> None:
        await asyncio.to_thread(
            self._client.put_object,
            Bucket=self._bucket,
            Key=key,
            Body=data,
            ContentType=content_type,
        )

    async def download(self, key: str) -> StoredObject:
        try:
            response = await asyncio.to_thread(
                self._client.get_object, Bucket=self._bucket, Key=key
            )
        except ClientError as error:
            if error.response.get("Error", {}).get("Code") in _NOT_FOUND:
                raise ObjectNotFoundError(key) from None
            raise
        body = await asyncio.to_thread(response["Body"].read)
        return StoredObject(
            key=key,
            data=body,
            content_type=response.get("ContentType", "application/octet-stream"),
        )

    async def check(self) -> None:
        await asyncio.to_thread(self._client.head_bucket, Bucket=self._bucket)

    async def ensure_bucket(self) -> None:
        """Create the bucket if missing. Local development only; AWS buckets come from Terraform."""
        try:
            await self.check()
        except ClientError:
            await asyncio.to_thread(self._client.create_bucket, Bucket=self._bucket)
