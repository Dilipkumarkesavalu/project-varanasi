# ADR-0012: M1 Foundation Alignment

- **Status:** Proposed
- **Date:** 2026-09-27
- **Milestone:** M1
- **Deciders:** Project owner
- **Amends:** ADR-0008 §1, §2, §10 (layout, tooling, env vars) and ADR-0011 (hosting details)
- **Supersedes / Superseded by:** —

## Context

The M1 plan (Cloud, Repository & CI/CD Foundation) introduced things that M0 did not
decide, or decided differently:

- a repository layout with `backend/`, `apps/`, `packages/` and `infra/` (ADR-0008 had
  `src/` and `deploy/` at the root);
- **three Flutter apps** (Platform, Billing, HRMS) with shared packages managed by
  **Melos**. M0 never chose a frontend technology;
- **Redis**, which no M0 ADR mentions;
- **MinIO** as the local S3 stand-in.

Building M1 also surfaced constraints that forced some choices. Under ADR-0010 J2, these
cross-module, hard-to-reverse changes need an ADR.

## Decision

### 1. Repository layout (amends ADR-0008 §2)

```
project-varanasi/
├── backend/                  # Python backend: one modular FastAPI app (ADR-0001)
│   ├── pyproject.toml, uv.lock, alembic.ini, Dockerfile
│   ├── src/varanasi/         # main.py, settings.py, shared/, platform/, billing/, hrms/
│   └── tests/                # unit/, integration/, migration/, … (ADR-0009)
├── apps/platform|billing|hrms/   # Flutter web apps, one per product
├── packages/core|ui/         # shared Flutter packages (varanasi_core, varanasi_ui)
├── infra/                    # postgres/, web/, staging/, terraform/ (replaces deploy/)
├── docs/                     # adr/, architecture/, runbooks/
├── pubspec.yaml              # Flutter/Dart workspace root (pub workspaces + Melos)
└── docker-compose.yml        # local stack
```

Everything else in ADR-0008 §2 (the module layout: `contract/` and `internal/` with its
sub-layers and `migrations/`) is unchanged, just under `backend/src/varanasi/`. Each folder
has a README naming its owner, and `.github/CODEOWNERS` enforces ownership.

### 2. Frontend: Flutter web + Melos

- **Three separate Flutter apps**, one per product, which mirrors ADR-0001. They target
  **web** first; other platforms can be added later.
- They share **`varanasi_core`**, which contains:
  - an HTTP client that applies ADR-0007: correlation ID, `Idempotency-Key`, `If-Match`,
    and Problem Details errors;
  - an in-memory token store;
  - routing helpers;
  - JSON logging.
- They also share **`varanasi_ui`**, the design system: tokens, theme and widgets.
- Shared packages contain **no business logic**, the same rule as backend `shared/`.
- **Pub workspaces + Melos 8** give one dependency resolution for all five packages.
- Tokens follow ADR-0007 §11: the access token lives in memory only; the refresh token
  will be an HttpOnly cookie.
- In staging and production, **nginx serves each app under `/platform/`, `/billing/` and
  `/hrms/` and proxies `/api` and `/health` on the same origin**, so no CORS is needed
  there. Locally, the backend allows the Flutter dev-server origins through
  `VARANASI_CORS_ALLOWED_ORIGINS`.
- The brand font (Inter) is declared in the theme but not yet bundled. Runtime fetching
  from Google Fonts was rejected: it is a third-party call from customer browsers, and
  the `google_fonts` dependency tree breaks Windows builds.

### 3. Redis: cache only

- **Redis is a cache.** It is **not** a message broker; ADR-0005 (RabbitMQ) stays frozen.
- Every tenant key starts with `t:{tenant_id}:` (ADR-0006 layer 4).
- Its health is part of `GET /health/ready`.
- Local and staging run `redis:7.4.11-alpine` as a container on the app server.
  Production may move to ElastiCache (Valkey) without a code change.

### 4. Local object storage: RustFS instead of MinIO

- MinIO no longer publishes container images. The Docker Hub and Quay repositories are
  empty as of 2026-09.
- We use **RustFS 1.0.0** (Apache-2.0, S3-compatible) **for local development and tests
  only**.
- The backend talks to it through the same `Storage` interface and boto3 S3 client used
  against **AWS S3** in staging and production (ADR-0011). Switching backends is
  configuration only.
- RustFS itself warns against production use, and we never use it there.

### 5. Database drivers (amends ADR-0008 §1)

- The **runtime uses asyncpg**. psycopg's async mode cannot run on Windows' default event
  loop, which broke local development.
- **Alembic uses synchronous psycopg 3.**
- Settings keep libpq-style URLs (`sslmode=require`); the engine translates them for
  asyncpg.

### 6. Environment and local ports (amends ADR-0008 §10)

- The repo-root `.env` (copied from `.env.example`) serves both Docker Compose and the
  backend, which reads `../.env` when run from `backend/`.
- Compose host ports default to **55432 (Postgres), 56379 (Redis) and 59000/59001
  (storage)**, so they don't collide with other local projects. They are configurable with
  `VARANASI_*_HOST_PORT`.
- RabbitMQ has one user per module (ADR-0005). It is not yet in the local stack; it
  arrives with the first event producer.

### 7. Staging topology (details within ADR-0011)

| Item | Staging choice |
|------|----------------|
| App server | One `m7g.large` (Graviton) EC2 in a private subnet. Runs `backend`, `web` (nginx) and `redis` containers. Admin via SSM only |
| Images | Built for `linux/arm64` in GitHub Actions and pushed to ECR (immutable tags = git tags) |
| Database | RDS PostgreSQL 17, `db.t4g.micro`, Single-AZ, encrypted, master password managed by Secrets Manager. The ADR-0006 roles are bootstrapped idempotently on every deploy |
| Network | ALB in public subnets. **One NAT gateway** (cost trade-off for staging) |
| TLS | HTTPS with ACM when `domain_name` is set. Until then, **HTTP on the ALB DNS name** (staging only, no real customer data) |
| Deploy | Pushing a `v*` tag runs full CI, then builds, pushes and deploys via SSM. `deploy.sh` runs migrations, restarts and fails the deploy if `/health/ready` isn't ok. GitHub uses OIDC; no AWS keys are stored |

## Consequences

- **Positive**
  - One repository holds backend, three apps, shared packages, infrastructure and docs,
    with clear owners.
  - Every M0 rule has a concrete implementation:
    - import-linter for module boundaries;
    - database roles with no superuser rights and no `BYPASSRLS`;
    - correlation IDs from the browser through to the logs;
    - Problem Details errors on both backend and frontend.
  - Local, CI and staging use the same images and commands.
- **Negative / trade-offs**
  - The Flutter toolchain adds CI time (analyze, test and web builds).
  - RustFS is young. If it misbehaves, only local development is affected, and it can be
    swapped for another S3-compatible server.
  - Staging runs HTTP-only until a domain is configured.
- **Follow-ups**
  - Choose the domain and enable HTTPS for staging.
  - Bundle Inter as a font asset.
  - Add RabbitMQ to Compose with the first event producer (ADR-0005).
  - Add CloudWatch agent log shipping on the app server (ADR-0011).

## References

- ADR-0001, ADR-0005, ADR-0006, ADR-0007, ADR-0008, ADR-0009, ADR-0010, ADR-0011
- `docs/runbooks/staging-deploy.md`, `docs/runbooks/github-setup.md`
