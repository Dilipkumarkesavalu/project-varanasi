"""Create the hrms schema and grant the module's runtime role access (ADR-0003, ADR-0006).

The runtime role gets data access only: it does not own tables and cannot bypass RLS.

Revision ID: c1f0c0de0001
Revises:
Create Date: 2026-09-27 00:00:00
"""

from collections.abc import Sequence

from alembic import op

revision: str = "c1f0c0de0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

SCHEMA = "hrms"
APP_ROLE = "varanasi_hrms_app"


def upgrade() -> None:
    op.execute(f"CREATE SCHEMA {SCHEMA}")
    op.execute(f"GRANT USAGE ON SCHEMA {SCHEMA} TO {APP_ROLE}")
    op.execute(
        f"ALTER DEFAULT PRIVILEGES IN SCHEMA {SCHEMA} "
        f"GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO {APP_ROLE}"
    )
    op.execute(
        f"ALTER DEFAULT PRIVILEGES IN SCHEMA {SCHEMA} "
        f"GRANT USAGE, SELECT ON SEQUENCES TO {APP_ROLE}"
    )


def downgrade() -> None:
    op.execute(
        f"ALTER DEFAULT PRIVILEGES IN SCHEMA {SCHEMA} "
        f"REVOKE USAGE, SELECT ON SEQUENCES FROM {APP_ROLE}"
    )
    op.execute(
        f"ALTER DEFAULT PRIVILEGES IN SCHEMA {SCHEMA} "
        f"REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM {APP_ROLE}"
    )
    op.execute(f"REVOKE USAGE ON SCHEMA {SCHEMA} FROM {APP_ROLE}")
    op.execute(f"DROP SCHEMA {SCHEMA}")
