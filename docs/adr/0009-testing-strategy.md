# ADR-0009: Testing Strategy

- **Status:** Accepted (M0 approval, 2026-09-27)
- **Date:** 2026-09-27
- **Milestone:** M0
- **Task:** M0-ARC-009
- **Deciders:** Project owner (see `docs/architecture/M0-APPROVAL.md`)
- **Depends on:** ADR-0003 Module Contracts, ADR-0004 Event Taxonomy, ADR-0005 Event
  Broker, ADR-0006 Tenant Isolation, ADR-0007 API Standards, ADR-0008 Coding & Repository
  Conventions
- **Supersedes / Superseded by:** —

## Context

The earlier ADRs make promises that are only real if tests prove them:

- modules only talk through contracts (ADR-0003);
- events follow a schema and are processed exactly once, even when delivered twice
  (ADR-0004, ADR-0005);
- **Tenant A can never see Tenant B's data** (ADR-0006);
- APIs follow one standard and don't break clients (ADR-0007).

This ADR defines each test layer, **the exact command that runs it**, and **which layers
must pass before a PR can merge**.

## Decision

### 1. Test layers at a glance

| Layer | Question it answers | Speed | Needs Docker? |
|-------|---------------------|-------|---------------|
| **Static** (gate 0) | Is the code well-formed, typed and within module boundaries? | Seconds | No |
| **Unit** | Does this piece of business logic behave correctly on its own? | Seconds | No |
| **Integration** | Does it work with the real PostgreSQL and RabbitMQ? | Minutes | Yes |
| **Contract** | Do module contracts, events and the HTTP API still match what consumers expect? | Minutes | Yes |
| **Security** | Is tenant isolation, authentication and authorization airtight? Are dependencies and secrets clean? | Minutes | Yes |
| **Migration** | Do DB migrations apply cleanly, keep data, and match the models? | Minutes | Yes |
| **End-to-End** | Does a complete business flow work through the running app? | Longest | Yes (full stack) |

Rough proportions: many unit tests, a solid layer of integration tests, and a small
number of focused E2E tests. **Security and contract tests are not optional extras.**
They protect the frozen decisions.

### 2. How tests are organised

```
tests/
├── conftest.py          # auto-applies the layer marker based on the folder
├── factories/           # test data builders per module (never production data)
├── unit/                # {platform,billing,hrms,shared}/
├── integration/         # {platform,billing,hrms,shared}/
├── contract/
│   ├── modules/         # contract API behaviour (ADR-0003)
│   ├── events/          # event schemas + publishing (ADR-0004)
│   └── api/             # HTTP responses match OpenAPI (ADR-0007)
├── security/
│   ├── cross_tenant/    # Tenant A vs Tenant B, for every endpoint (ADR-0006)
│   ├── rls/             # RLS fail-closed + DB role checks
│   ├── auth/            # 401/403 rules, token handling
│   └── schema/          # every business table has tenant_id + RLS
├── migration/
└── e2e/
```

**Markers are applied automatically from the folder**, so a test can't end up in the
wrong layer by mistake. `pyproject.toml`:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
addopts = "--strict-markers --strict-config -ra"
testpaths = ["tests"]
markers = [
  "unit: fast, isolated, no I/O",
  "integration: real PostgreSQL/RabbitMQ via Testcontainers",
  "contract: module contracts, event schemas, OpenAPI conformance",
  "security: tenant isolation, authn/authz, RLS, schema lint",
  "migration: Alembic upgrade/downgrade/drift",
  "e2e: full running stack",
]
```

`tests/conftest.py` marks every test with the name of its top-level folder
(`unit`, `integration`, …).

**Common rules for all layers**

- **Two tenants by default.** Shared fixtures always create **Tenant A and Tenant B**
  with data, so leaks show up in every layer, not only the security suite.
- **Deterministic.** Freeze time with `time-machine`, seed random generators, and make no
  real network calls (except Testcontainers).
- **Independent.** Each test cleans up after itself (a transaction rollback or a fresh
  schema). Tests can run in any order and in parallel.
- **No production data** ever. Use factories.
- **Flaky tests** are quarantined within 24 hours with a ticket, then fixed or deleted
  within 7 days. A flaky test is never "just re-run".

### 3. Layer definitions and commands

All commands run from the repository root. `uv run` uses the locked environment
(ADR-0008). The same commands run locally and in CI.

---

#### 3.0 Static checks (gate 0)

**Role:** catch style, typing and boundary violations before any test runs.

```bash
uv run ruff format --check .
uv run ruff check .
uv run mypy src tests
uv run lint-imports
```

`lint-imports` enforces the ADR-0003 boundaries (config in ADR-0008 §3). Ruff includes the
`S` (bandit) security rules.

---

#### 3.1 Unit tests

**Role:** prove business rules in isolation. For example: invoice totals and tax, leave
balance calculation, invoice state transitions, entitlement decisions, payroll
deductions.

| Rules |
|-------|
| Test `domain/` and `application/` code. Replace repositories and other modules' contracts with in-memory fakes |
| **No database, broker, network, filesystem or sleep.** A unit test that needs Docker is in the wrong layer |
| Every test runs in under 100 ms. The whole suite runs in under 2 minutes |
| Every bug fix starts with a failing unit test (or an integration test if it's an I/O bug) |

**Command**

```bash
uv run pytest -m unit -n auto --cov=varanasi --cov-report=xml:coverage-unit.xml
```

---

#### 3.2 Integration tests

**Role:** prove our code works with **real infrastructure**, including the things that
fakes can't show:

- repositories and SQL against real PostgreSQL, **with RLS enabled** and using the
  module's real DB role (not a superuser);
- the tenant-aware session actually runs `SET LOCAL app.tenant_id` (ADR-0006);
- **outbox → relay → RabbitMQ → consumer** end to end (ADR-0005);
- consumer **idempotency**: the same `event_id` delivered twice changes data once;
- **retry → DLQ**: a failing handler ends in `<queue>.dlq` after 5 attempts; permanent
  errors go straight to the DLQ;
- HTTP middleware: correlation ID, idempotency keys (replay, `409`, `422`), `ETag` /
  `If-Match` (ADR-0007).

| Rules |
|-------|
| Use **Testcontainers** for PostgreSQL (same major version as production) and RabbitMQ 4.x. Never a shared test DB |
| Apply real migrations and the real `deploy/rabbitmq/definitions.json`, not hand-made test setup |
| Call through FastAPI's test client (`httpx.AsyncClient` + ASGI transport) or the application services |
| Suite runs in under 8 minutes |

**Command**

```bash
uv run pytest -m integration -n 4 --cov=varanasi --cov-append --cov-report=xml:coverage-integration.xml
```

---

#### 3.3 Contract tests

**Role:** stop one side of a boundary from breaking the other. There are three kinds:

**a) Module contracts (ADR-0003).** For each `contract/api.py` interface, a shared test
suite checks the real implementation behaves as documented. Examples:

- `EntitlementApi.is_enabled` returns `False` for a product the tenant hasn't bought;
- `EmployeeApi.get_employee` raises `NotFound` for another tenant's ID;
- DTOs are immutable.

Consumers add test cases here for every operation they depend on, so the owner can't
change that behaviour without seeing a test fail. mypy separately checks that the
implementation matches the `Protocol`.

**b) Event contracts (ADR-0004).**

- Every event a module publishes validates against its JSON Schema.
- It has all 8 required envelope fields and a non-empty `tenant_id`.
- The routing key matches `<event_name>.v<version>`.
- Every published event appears in the ADR-0004 catalogue.
- A schema change on a version that is already published must be **backward-compatible**
  (only optional fields added). Otherwise it must be a new `.vN`.

**c) HTTP API contracts (ADR-0007).**

- The committed `docs/api/openapi.json` matches the code.
- It passes the Spectral ruleset (naming, `x-permission` on every operation, Problem
  Details errors, pagination shape).
- It has **no breaking change** compared with `main`.
- Real responses in tests validate against the spec.

We **do not** use Pact or another consumer-driven contract broker. All consumers live in
this repository and run in the same CI, so the tests above give the same protection
with less machinery. We'll revisit this if a module is extracted into its own service
or external clients multiply.

**Commands**

```bash
# a) module contracts + b) event contracts + c) response-vs-spec validation
uv run pytest -m contract

# c) committed OpenAPI spec is up to date with the code
uv run python scripts/export_openapi.py --check docs/api/openapi.json

# c) OpenAPI lint against our API standards
npx --yes @stoplight/spectral-cli lint docs/api/openapi.json --ruleset .spectral.yaml --fail-severity=warn

# c) no breaking API change vs main
git show origin/main:docs/api/openapi.json > .tmp/openapi-base.json
oasdiff breaking .tmp/openapi-base.json docs/api/openapi.json --fail-on ERR

# b) event schemas: no breaking change within a published version
uv run python scripts/check_event_schemas.py --base origin/main
```

---

#### 3.4 Security tests

**Role:** prove the frozen tenant-isolation rules (ADR-0006) and the auth rules (ADR-0007)
hold, and keep known vulnerabilities and secrets out of the code.

| Suite | What it proves |
|-------|----------------|
| `security/cross_tenant/` | For **every** endpoint, a Tenant A token acting on Tenant B's data gets: `404` for reads/updates/deletes by ID, lists with **no** Tenant B rows, and writes that can't create or link Tenant B data. Includes search, export and file-download endpoints |
| **Route coverage check** (inside `cross_tenant/`) | The test lists every route registered in the FastAPI app and **fails if any route has no cross-tenant case**. A new endpoint can't be merged without one |
| `security/rls/` | A query with no `app.tenant_id` returns **zero rows** (fail-closed). `WITH CHECK` blocks writes to another tenant. App DB roles have no `BYPASSRLS`/superuser and don't own tables. The tenant setting doesn't leak to the next transaction on a pooled connection |
| `security/auth/` | Missing, expired or tampered tokens get `401`. Wrong `aud`/`iss` gets `401`. A client-supplied `tenant_id` is ignored. Missing permission gets `403`. Not entitled gets `403 not_entitled`. A suspended tenant gets `403` on writes and `200` on reads. Sensitive fields are hidden without `*.read_sensitive` |
| `security/schema/` | Every table in `platform`/`billing`/`hrms` (except `*_ref`) has `tenant_id NOT NULL`, RLS enabled and **forced**, and the `tenant_isolation` policy. Composite tenant FKs exist |
| Event tenant checks | Consumers reject events without a valid `tenant_id` (sent to the DLQ) and process under the event's tenant only |
| Dependency audit | No known vulnerabilities in locked dependencies |
| Secret scan | No secrets committed in the PR's changes |

**Commands**

```bash
# tenant isolation, RLS, auth, schema lint
uv run pytest -m security

# known-vulnerable dependencies
uv run --with pip-audit pip-audit --strict

# secrets in the commits of this PR
gitleaks git --redact --log-opts="origin/main..HEAD"
```

Outside the PR gate: an **OWASP ZAP baseline scan** runs nightly against staging, and an
external penetration test is done before the first production launch and yearly after
that.

---

#### 3.5 Migration tests

**Role:** make sure database changes are safe to deploy, for each module's Alembic history
(ADR-0008 §5).

| Test | What it proves |
|------|----------------|
| **Drift check** | The SQLAlchemy models and the migrations match. It catches "changed a model, forgot the migration" |
| **Upgrade from empty** | `base → head` works on an empty database |
| **Upgrade from last release** | Starting from the **previous release's schema with sample data** for two tenants, `→ head` works and the data survives |
| **Stairway** | Every migration can go up → down → up (checks `downgrade()` for local use and catches ordering bugs) |
| **Tenant/RLS lint** | New tables follow ADR-0006 (shares the checks in `security/schema/`) |
| **Lock safety** | Flags dangerous operations on large tables (e.g. adding a `NOT NULL` column without a default, or building an index without `CONCURRENTLY`) |

**Commands**

```bash
# drift check, per module history
uv run alembic -n platform check
uv run alembic -n billing check
uv run alembic -n hrms check

# upgrade-from-empty, upgrade-from-last-release, stairway, lock safety
uv run pytest -m migration
```

---

#### 3.6 End-to-End tests

**Role:** prove a few **critical business journeys** work through the **real running
stack**: the app container, PostgreSQL, RabbitMQ and the outbox relay, called over HTTP
exactly like a client would.

Initial journeys (kept few and valuable):

1. **Tenant onboarding:** create a tenant → `platform.tenant.created.v1` → Billing and
   HRMS default settings exist → the admin logs in.
2. **Invoice to payment:** create a customer → create an invoice → issue it (event
   published) → record a payment → the invoice shows as paid.
3. **Employee lifecycle:** create an employee → Platform's employee count increases
   (event) → terminate them → the count decreases and the linked login is deactivated
   (if enabled).
4. **Leave:** request leave → the manager approves → the balance updates.
5. **Suspension:** suspend the tenant → writes are blocked in Billing and HRMS, reads
   still work → reactivate.
6. **Entitlement:** a tenant without HRMS gets `403 not_entitled` on HRMS endpoints.

| Rules |
|-------|
| API-level for now (Python + `httpx`). Browser E2E (Playwright) is added when the web frontend exists |
| Starts the stack from the **same Docker image** that will be deployed |
| Waits for asynchronous effects by polling with a timeout, never with fixed `sleep`s |
| Suite runs in under 15 minutes |

**Commands**

```bash
docker compose -f deploy/compose/compose.e2e.yaml up -d --build --wait
VARANASI_E2E_BASE_URL=http://localhost:8080 uv run pytest -m e2e
docker compose -f deploy/compose/compose.e2e.yaml down -v
```

### 4. Merge gate: what must pass before a PR can merge

| Layer | Required? | When | Command(s) |
|-------|-----------|------|------------|
| **Static** | ✅ **Required** | Every PR | §3.0 |
| **Unit** | ✅ **Required** | Every PR | §3.1 |
| **Integration** | ✅ **Required** | Every PR | §3.2 |
| **Contract** | ✅ **Required** | Every PR | §3.3 |
| **Security** | ✅ **Required** | Every PR | §3.4 |
| **Coverage** | ✅ **Required** | Every PR: **≥ 80 % of changed lines** covered by unit + integration tests | `uv run diff-cover coverage-unit.xml coverage-integration.xml --compare-branch=origin/main --fail-under=80` |
| **Migration** | ⚠️ **Required when DB changes.** The drift check runs on **every** PR | When any `*/migrations/**` or `*/internal/infrastructure/**` file changes | §3.5 |
| **E2E** | ⚠️ **Required for selected changes** | See triggers below | §3.6 |

**E2E is required when a PR:**

- touches `src/varanasi/shared/**` (auth, tenancy, db session, messaging, http
  middleware);
- touches any `*/contract/**` (module contracts or event definitions);
- adds or changes an event consumer (`*/internal/consumers/**`);
- touches `src/varanasi/main.py`, `settings.py`, `deploy/**`, `pyproject.toml` or
  `uv.lock`;
- includes a migration;
- has the `run-e2e` label (a reviewer can always ask for it).

E2E also runs **on every merge to `main`** and **before every release tag**. A failure
on `main` blocks releases until it's fixed.

**Branch protection** on `main` marks these CI checks as required: `static`, `unit`,
`integration`, `contract`, `security`, `coverage`, `migration-drift`, plus
`migration` and `e2e`, which report success automatically when their trigger paths
aren't touched.

### 5. CI pipeline order

```
static ──► unit ──► ┬─► integration ─┬─► coverage
                    ├─► contract     │
                    ├─► security     │
                    ├─► migration*   │
                    └─► e2e*  ───────┘
            * = conditional (see §4)
```

The fast checks run first, so most failures are reported within a couple of minutes.
The Docker-based layers run in parallel.

### 6. Running everything locally

```bash
# everything the merge gate runs, except E2E (needs Docker for integration+)
uv run ruff format --check . && uv run ruff check . && uv run mypy src tests && uv run lint-imports
uv run pytest -m "not e2e"
```

In M1 these commands will also be wrapped in `make` targets (`make check`,
`make test-unit`, `make test-e2e`, …) as shortcuts. The commands above remain the source
of truth.

## Options considered

| Option | Verdict | Why |
|--------|---------|-----|
| SQLite or mocks instead of PostgreSQL in integration tests | ❌ | They can't test RLS, `SET LOCAL`, schemas or roles, which are the things we most need to prove (ADR-0006) |
| A shared, long-lived test database | ❌ | Order-dependent, flaky tests. Testcontainers gives each run a clean one |
| Pact / a consumer-driven contract broker | ❌ for now | All consumers are in one repo and CI. Revisit on extraction |
| E2E on every PR | ❌ | Slow. Most of the value is covered by integration + contract tests. Required only where the risk is highest |
| A global coverage threshold (e.g. 90 % overall) | ❌ | Encourages meaningless tests. Changed-line coverage focuses on new code |

## Consequences

- **Positive**
  - Every frozen decision (DB/module rule, broker behaviour, tenant isolation) has an
    automated test that fails the build if it's broken.
  - A new endpoint can't be merged without a cross-tenant test.
  - Developers run exactly the same commands locally as CI.
- **Negative / trade-offs**
  - Docker is required locally for anything beyond unit tests.
  - CI time and cost are higher than a unit-only pipeline. This is kept in check by the
    time budgets and conditional E2E.
  - The route-coverage check and cross-tenant cases add work to every new endpoint.
    That's intended.
- **Follow-ups**
  - M1: implement `tests/conftest.py` auto-marking, the two-tenant fixtures, factories,
    `scripts/export_openapi.py`, `scripts/check_event_schemas.py`, `.spectral.yaml`,
    `deploy/compose/compose.e2e.yaml`, the Alembic `-n <module>` config and the CI
    workflow.
  - ADR-0010: reference this merge gate in the review checklist.
  - ADR-0011: a staging environment for the nightly ZAP scan.

## References

- ADR-0003 Module Contracts
- ADR-0004 Event Taxonomy
- ADR-0005 Event Broker
- ADR-0006 Tenant Isolation
- ADR-0007 API Standards
- ADR-0008 Coding & Repository Conventions
