"""Application settings: the only place environment variables are read (ADR-0008 §10).

Every variable is prefixed with ``VARANASI_``. Secrets may instead be supplied as a
file by setting ``VARANASI_<NAME>_FILE`` to its path (used in staging/production,
where secrets are mounted under ``/run/secrets``). Startup fails with a readable
message when a required setting is missing or invalid.
"""

from __future__ import annotations

import os
import sys
from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Annotated, Any

from pydantic import Field, PostgresDsn, RedisDsn, SecretStr, ValidationError, field_validator
from pydantic.fields import FieldInfo
from pydantic_settings import (
    BaseSettings,
    NoDecode,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
)

ENV_PREFIX = "VARANASI_"


class Environment(StrEnum):
    LOCAL = "local"
    TEST = "test"
    STAGING = "staging"
    PRODUCTION = "production"


class LogFormat(StrEnum):
    JSON = "json"
    CONSOLE = "console"


class FileSecretsSource(PydanticBaseSettingsSource):
    """Reads ``VARANASI_<FIELD>_FILE`` variables and loads the value from that file."""

    def get_field_value(self, field: FieldInfo, field_name: str) -> tuple[Any, str, bool]:
        path = os.environ.get(f"{ENV_PREFIX}{field_name.upper()}_FILE")
        if not path:
            return None, field_name, False
        return Path(path).read_text(encoding="utf-8").strip(), field_name, False

    def __call__(self) -> dict[str, Any]:
        values: dict[str, Any] = {}
        for field_name, field in self.settings_cls.model_fields.items():
            value, key, _ = self.get_field_value(field, field_name)
            if value is not None:
                values[key] = value
        return values


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix=ENV_PREFIX,
        env_file=("../.env", ".env"),  # repo-root .env when run from backend/
        env_file_encoding="utf-8",
        extra="ignore",
        frozen=True,
    )

    env: Environment
    log_level: str = "INFO"
    log_format: LogFormat = LogFormat.JSON

    # One database role per module (ADR-0003, ADR-0006). The migrator role owns the schemas.
    db_platform_url: PostgresDsn
    db_billing_url: PostgresDsn
    db_hrms_url: PostgresDsn
    db_migrator_url: PostgresDsn

    redis_url: RedisDsn

    # Object storage: S3 in AWS, RustFS locally (ADR-0012).
    storage_bucket: str = Field(min_length=3)
    storage_endpoint_url: str | None = None  # None = real AWS S3
    storage_region: str = "ap-south-1"
    storage_access_key_id: SecretStr | None = None  # None = use the AWS instance role
    storage_secret_access_key: SecretStr | None = None
    storage_create_bucket: bool = False  # local development only

    # Comma-separated in the environment, e.g. "https://a.example,https://b.example".
    cors_allowed_origins: Annotated[list[str], NoDecode] = []

    @field_validator("cors_allowed_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        # Precedence: explicit init args > env vars > *_FILE secrets > .env file.
        return (init_settings, env_settings, FileSecretsSource(settings_cls), dotenv_settings)


class MigrationSettings(BaseSettings):
    """The subset needed by Alembic, so migrations can run without Redis/storage config."""

    model_config = SettingsConfigDict(
        env_prefix=ENV_PREFIX,
        env_file=("../.env", ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    db_migrator_url: PostgresDsn

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        return (init_settings, env_settings, FileSecretsSource(settings_cls), dotenv_settings)


def _describe(error: ValidationError) -> str:
    lines = ["Invalid or missing configuration. Fix these environment variables:"]
    for item in error.errors():
        name = ENV_PREFIX + "_".join(str(part) for part in item["loc"][:1]).upper()
        problem = "is required but not set" if item["type"] == "missing" else item["msg"]
        lines.append(f"  - {name}: {problem}")
    lines.append("See .env.example for every variable and an example value.")
    return "\n".join(lines)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Load and validate settings once. Exits the process with a clear message on error."""
    try:
        return Settings()  # values come from the environment
    except ValidationError as error:
        sys.stderr.write(_describe(error) + "\n")
        raise SystemExit(78) from None  # 78 = EX_CONFIG
