"""Test configuration shared by all layers (ADR-0009 §2).

Each test gets the marker of the top-level folder it lives in (``unit``, ``integration``,
``migration``, …), so a test can never end up in the wrong layer by accident.
"""

from __future__ import annotations

from pathlib import Path

import pytest

# Container fixtures (postgres, redis_url, storage_endpoint), started lazily when requested.
pytest_plugins = ["tests.fixtures.containers"]

_TESTS_ROOT = Path(__file__).parent
_LAYERS = {"unit", "integration", "contract", "security", "migration", "e2e"}


def pytest_collection_modifyitems(items: list[pytest.Item]) -> None:
    for item in items:
        layer = item.path.relative_to(_TESTS_ROOT).parts[0]
        if layer not in _LAYERS:
            raise pytest.UsageError(
                f"{item.nodeid}: tests must live in one of {sorted(_LAYERS)} (ADR-0009)"
            )
        item.add_marker(getattr(pytest.mark, layer))
