# backend/

**Owner:** Backend team. Module code is owned by the module teams (Platform / Billing / HRMS); `src/varanasi/shared/` is owned by the architecture reviewers. See [`.github/CODEOWNERS`](../.github/CODEOWNERS).

The Python backend: **one modular FastAPI application** containing the Platform, Billing and
HRMS modules (ADR-0001 – ADR-0003). Conventions are in
[ADR-0008](../docs/adr/0008-coding-repo-conventions.md) and
[ADR-0012](../docs/adr/0012-m1-foundation-alignment.md).

## Layout

```
backend/
├── pyproject.toml / uv.lock      # dependencies (locked), ruff, mypy, pytest, import-linter
├── alembic.ini                   # one migration history per module schema
├── Dockerfile                    # non-root, locked dependencies
├── src/varanasi/
│   ├── main.py                   # app factory
│   ├── settings.py               # the ONLY place env vars are read
│   ├── shared/                   # logging, correlation ID, db, cache, storage, health
│   ├── platform/  billing/  hrms/
│   │   ├── contract/             # public: the only thing other modules may import
│   │   ├── internal/             # private: domain, application, infrastructure, http, consumers
│   │   └── migrations/           # Alembic history for this module's schema
└── tests/                        # unit/, integration/, migration/, … (ADR-0009)
```

## Run it locally

Prerequisites: Docker Desktop, [uv](https://docs.astral.sh/uv/).

```bash
# 1. From the repo root: copy the example config and start PostgreSQL, Redis and RustFS (S3)
cp .env.example .env
docker compose up -d

# 2. Install dependencies and apply migrations
cd backend
uv sync
uv run alembic -n platform upgrade head
uv run alembic -n billing upgrade head
uv run alembic -n hrms upgrade head

# 3. Start the API
uv run uvicorn varanasi.main:create_app --factory --reload
```

- Liveness: <http://localhost:8000/health> returns `{"status":"ok"}`
- Readiness: <http://localhost:8000/health/ready> reports database, redis and storage status
- API docs: <http://localhost:8000/docs>

Or run the whole stack in containers: `docker compose --profile app up -d --build`.

## Checks (same commands as CI, ADR-0009)

```bash
uv run ruff format --check .
uv run ruff check .
uv run mypy src tests
uv run lint-imports
uv run pytest -m unit
uv run pytest -m "integration or migration"   # needs Docker
```
