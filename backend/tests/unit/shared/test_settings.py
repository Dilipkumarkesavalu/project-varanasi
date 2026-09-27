from __future__ import annotations

from pathlib import Path

import pytest

from tests.factories.settings import TEST_ENV
from varanasi.settings import Environment, Settings, get_settings


@pytest.fixture
def env(monkeypatch: pytest.MonkeyPatch) -> pytest.MonkeyPatch:
    for key, value in TEST_ENV.items():
        monkeypatch.setenv(key, value)
    monkeypatch.chdir(Path(__file__).parent)  # make sure no developer .env is picked up
    get_settings.cache_clear()
    return monkeypatch


def test_settings_load_from_environment(env: pytest.MonkeyPatch) -> None:
    settings = Settings(_env_file=None)

    assert settings.env is Environment.TEST
    assert settings.storage_bucket == "varanasi-test"
    assert str(settings.redis_url) == "redis://localhost:6379/0"


def test_missing_setting_stops_startup_with_clear_message(
    env: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    env.delenv("VARANASI_DB_PLATFORM_URL")

    with pytest.raises(SystemExit) as exit_info:
        get_settings()

    assert exit_info.value.code == 78
    message = capsys.readouterr().err
    assert "VARANASI_DB_PLATFORM_URL: is required but not set" in message
    assert ".env.example" in message


def test_invalid_value_is_reported(
    env: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    env.setenv("VARANASI_ENV", "prod-ish")

    with pytest.raises(SystemExit):
        get_settings()

    assert "VARANASI_ENV:" in capsys.readouterr().err


def test_secret_can_be_read_from_file(env: pytest.MonkeyPatch, tmp_path: Path) -> None:
    secret_file = tmp_path / "storage_secret"
    secret_file.write_text("s3cr3t-from-file\n", encoding="utf-8")
    env.setenv("VARANASI_STORAGE_SECRET_ACCESS_KEY_FILE", str(secret_file))

    settings = Settings(_env_file=None)

    assert settings.storage_secret_access_key is not None
    assert settings.storage_secret_access_key.get_secret_value() == "s3cr3t-from-file"


def test_secrets_are_not_shown_in_repr(env: pytest.MonkeyPatch) -> None:
    env.setenv("VARANASI_STORAGE_SECRET_ACCESS_KEY", "do-not-print-me")

    assert "do-not-print-me" not in repr(Settings(_env_file=None))


def test_cors_origins_are_comma_separated(env: pytest.MonkeyPatch) -> None:
    env.setenv("VARANASI_CORS_ALLOWED_ORIGINS", "http://localhost:8081, http://localhost:8082")

    assert Settings(_env_file=None).cors_allowed_origins == [
        "http://localhost:8081",
        "http://localhost:8082",
    ]
