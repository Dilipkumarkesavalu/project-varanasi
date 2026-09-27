# Project Varanasi

Multi-tenant SaaS: **Platform** (identity, tenants, roles, audit, entitlements) ·
**Billing** · **HRMS**, built as one modular backend plus three Flutter web apps, hosted on
AWS Mumbai.

- **M0 (architecture):** APPROVED, QG-01 passed. See
  [docs/architecture/M0-APPROVAL.md](docs/architecture/M0-APPROVAL.md).
- **M1 (foundation):** in progress. See [ADR-0012](docs/adr/0012-m1-foundation-alignment.md).

## Repository map

| Folder | What | Owner |
|--------|------|-------|
| [`backend/`](backend/) | Python/FastAPI modular backend (Platform, Billing, HRMS modules) | Backend + module teams |
| [`apps/`](apps/) | Flutter web apps: `platform/`, `billing/`, `hrms/` | Product teams |
| [`packages/`](packages/) | Shared Flutter packages: `core/`, `ui/` | Frontend core |
| [`infra/`](infra/) | Local DB roles, web image, staging deploy, Terraform | DevOps |
| [`docs/`](docs/) | ADRs, approval records, runbooks | Architecture |

## Quick start (local)

Prerequisites:
- Docker Desktop;
- [uv](https://docs.astral.sh/uv/);
- Flutter 3.47+ with Melos: `dart pub global activate melos`.

```bash
cp .env.example .env
docker compose up -d                           # PostgreSQL, Redis, S3 (RustFS)
docker compose --profile app up -d --build     # + migrations + backend on :8000
curl localhost:8000/health/ready               # {"status":"ok","checks":{...}}

melos bootstrap                                # Flutter workspace
cd apps/billing && flutter run -d chrome --web-port 8082
```

Details: [backend/README.md](backend/README.md), [apps/README.md](apps/README.md).

## Checks (the same as CI)

```bash
cd backend && uv run ruff format --check . && uv run ruff check . && uv run mypy && uv run lint-imports && uv run pytest
melos run format:check && melos run analyze && melos run test && melos run build:web
```

## Deploying

Pushing a version tag deploys to staging with no manual server commands:
`git tag v0.1.0 && git push origin v0.1.0`.
See [docs/runbooks/staging-deploy.md](docs/runbooks/staging-deploy.md).

## Architecture decisions

| ADR | Title | Status |
|-----|-------|--------|
| [0001](docs/adr/0001-product-separation.md) | Product Separation | Accepted |
| [0002](docs/adr/0002-service-boundaries.md) | Service Boundaries | Accepted |
| [0003](docs/adr/0003-module-contracts.md) | Module Contracts | Accepted. DB/module rule **FROZEN** |
| [0004](docs/adr/0004-event-taxonomy.md) | Event Taxonomy | Accepted |
| [0005](docs/adr/0005-event-broker.md) | Event Broker (RabbitMQ) | Accepted. **FROZEN** |
| [0006](docs/adr/0006-tenant-isolation.md) | Tenant Isolation | Accepted. **FROZEN** |
| [0007](docs/adr/0007-api-standards.md) | API Standards | Accepted |
| [0008](docs/adr/0008-coding-repo-conventions.md) | Coding & Repository Conventions | Accepted (amended by 0012) |
| [0009](docs/adr/0009-testing-strategy.md) | Testing Strategy | Accepted |
| [0010](docs/adr/0010-architecture-review-checklist.md) | Architecture Review Checklist | Accepted |
| [0011](docs/adr/0011-cloud-platform.md) | Cloud Platform: AWS `ap-south-1` (**A-016**) | Accepted. **FROZEN** |
| [0012](docs/adr/0012-m1-foundation-alignment.md) | M1 Foundation Alignment | Proposed |

**ADR rules:**
- One decision per file.
- Accepted ADRs change only through a new ADR.
- Frozen decisions also need an architecture review.
- Every PR answers the [ADR-0010 checklist](.github/pull_request_template.md).
