# ADR-0008: Coding & Repository Conventions

- **Status:** Accepted (M0 approval, 2026-09-27)
- **Date:** 2026-09-27
- **Milestone:** M0
- **Task:** M0-ARC-008
- **Deciders:** Project owner (see `docs/architecture/M0-APPROVAL.md`)
- **Depends on:** ADR-0001 – ADR-0007
- **Supersedes / Superseded by:** — (§1, §2, §10 amended by ADR-0012)

## Context

The earlier ADRs decide *what* we build: one modular app with Platform, Billing and HRMS
modules, contracts, events, tenant isolation and API standards. This ADR decides *how the
code and repository are organised*. The goals are:

- any developer can find anything in the same place in every module;
- the rules from ADR-0003 and ADR-0006 are enforced by tools, not memory;
- history, PRs and logs are consistent and searchable.

Several earlier ADRs left tooling choices to this one. Those are settled in section 1.

## Decision

### 1. Tech stack and tooling

| Area | Choice | Why / notes |
|------|--------|-------------|
| Language | **Python 3.13** | Team language. Type hints everywhere |
| Web framework | **FastAPI** | Async, Pydantic validation, and it generates OpenAPI 3.1 |
| Validation / DTOs | **Pydantic v2** | Contract DTOs, HTTP schemas, settings |
| Database | **PostgreSQL** (version fixed in ADR-0011) | ADR-0006 |
| ORM / SQL | **SQLAlchemy 2.x** (async) | Explicit sessions, which makes `SET LOCAL app.tenant_id` per transaction easy (ADR-0006) |
| Migrations | **Alembic**, one migration history per module schema | Section 5 |
| Message broker client | **aio-pika** | RabbitMQ (ADR-0005) |
| Package / env manager | **uv** with `pyproject.toml` + `uv.lock` | Fast, reproducible installs |
| Lint + format | **Ruff** (lint and format, line length 100) | One tool, fast |
| Type checking | **mypy** `--strict` | Required to pass in CI |
| Module boundaries | **import-linter** | Enforces ADR-0003 (section 3) |
| Tests | **pytest**, pytest-asyncio, pytest-xdist, pytest-cov, **Testcontainers** (real PostgreSQL + RabbitMQ), time-machine, diff-cover | Details in ADR-0009 |
| Security scanning | pip-audit (dependencies), gitleaks (secrets) | ADR-0009 §3.4 |
| OpenAPI lint / diff | **Spectral** (lint), **oasdiff** (breaking-change check) | ADR-0007 |
| Logging | **structlog** (JSON) | Section 11 |
| Commit checks | **commitizen** (pre-commit hook + CI) | Section 8 |
| Git hooks | **pre-commit** | Runs ruff, mypy, commitizen and secret scanning locally |

**Contract-first with FastAPI (reconciling with ADR-0007).** FastAPI generates the spec
from code, so we work "contract-first" like this:

1. The first PR for a new endpoint contains **only** the Pydantic request/response models
   and the route signature, returning `501 Not Implemented`.
2. The generated `openapi.json` is committed and reviewed in that PR.
3. CI regenerates the spec on every PR. It **fails** if the committed spec is out of
   date, if Spectral finds a violation, or if oasdiff finds a breaking change in `v1`.

### 2. Folder structure

One repository (monorepo) for the whole application.

```
project-varanasi/
├── README.md
├── pyproject.toml               # dependencies + ruff, mypy, pytest, import-linter config
├── uv.lock
├── .env.example                 # every env var, with safe example values (no secrets)
├── .pre-commit-config.yaml
├── .github/
│   ├── workflows/               # CI pipelines
│   ├── CODEOWNERS
│   └── pull_request_template.md
├── docs/
│   ├── adr/                     # architecture decisions (this folder)
│   ├── runbooks/                # operations: DLQ replay, restore, tenant migration…
│   └── api/openapi.json         # generated, committed, diffed in CI
├── deploy/
│   ├── docker/                  # Dockerfile(s)
│   ├── compose/                 # docker-compose for local dev + the server
│   └── rabbitmq/definitions.json   # exchanges/queues as code (ADR-0005)
├── src/
│   └── varanasi/
│       ├── main.py              # app factory: wires modules, middleware, routers
│       ├── settings.py          # the ONLY place env vars are read (section 10)
│       ├── shared/              # technical building blocks only, NO business logic
│       │   ├── db/              # engine, session, tenant-aware session (SET LOCAL)
│       │   ├── tenancy/         # tenant context
│       │   ├── auth/            # token verification, permission dependency
│       │   ├── http/            # error mapping, correlation ID, idempotency, pagination
│       │   ├── messaging/       # outbox relay, publisher, consumer base, DLQ handling
│       │   └── logging/         # structlog setup
│       ├── platform/
│       ├── billing/
│       └── hrms/
├── scripts/                     # CI/dev tools: OpenAPI export, event-schema check (ADR-0009)
└── tests/                       # one folder per test layer (ADR-0009)
    ├── conftest.py              # auto-applies the layer marker from the folder name
    ├── factories/               # test data builders, per module
    ├── unit/                    # {platform,billing,hrms,shared}/
    ├── integration/             # {platform,billing,hrms,shared}/
    ├── contract/                # modules/, events/, api/
    ├── security/                # cross_tenant/, rls/, auth/, schema/
    ├── migration/
    └── e2e/
```

**Every module has the same internal layout** (Billing shown):

```
src/varanasi/billing/
├── README.md                    # what this module owns, its contract, events in/out
├── contract/                    # PUBLIC: the only part other modules may import
│   ├── __init__.py
│   ├── api.py                   # Protocol interfaces, e.g. InvoiceApi
│   ├── dto.py                   # immutable Pydantic DTOs
│   ├── errors.py                # typed errors
│   └── events/
│       ├── invoice_issued_v1.py        # event payload model
│       └── invoice_issued_v1.json      # JSON Schema (ADR-0004)
├── internal/                    # PRIVATE
│   ├── domain/                  # entities, value objects, business rules (no framework)
│   ├── application/             # use cases/services; implements contract/api.py
│   ├── infrastructure/          # SQLAlchemy models, repositories, external clients
│   ├── http/                    # FastAPI routers + request/response schemas
│   └── consumers/               # event handlers for events this module consumes
├── migrations/                  # Alembic history for the billing schema only
└── permissions.py               # permissions registered with Platform
```

Dependency direction inside a module: `http / consumers → application → domain`, and
`infrastructure → domain`. **`domain` imports nothing from FastAPI, SQLAlchemy or
aio-pika.**

> ⚠️ `platform` is also the name of a Python standard-library module. Always import it
> as `varanasi.platform…` and never add `src/varanasi` itself to `sys.path`.

### 3. Module boundary enforcement (import-linter)

ADR-0003's rules as configuration. CI fails on any violation:

```toml
[tool.importlinter]
root_package = "varanasi"

[[tool.importlinter.contracts]]
name = "shared has no business logic dependencies"
type = "forbidden"
source_modules = ["varanasi.shared"]
forbidden_modules = ["varanasi.platform", "varanasi.billing", "varanasi.hrms"]

[[tool.importlinter.contracts]]
name = "billing uses other modules only through their contract"
type = "forbidden"
source_modules = ["varanasi.billing"]
forbidden_modules = ["varanasi.platform.internal", "varanasi.hrms.internal"]

[[tool.importlinter.contracts]]
name = "hrms uses other modules only through their contract"
type = "forbidden"
source_modules = ["varanasi.hrms"]
forbidden_modules = ["varanasi.platform.internal", "varanasi.billing.internal"]

[[tool.importlinter.contracts]]
name = "platform never calls billing/hrms APIs (events only)"
type = "forbidden"
source_modules = ["varanasi.platform"]
forbidden_modules = [
  "varanasi.billing.internal", "varanasi.billing.contract.api",
  "varanasi.hrms.internal",    "varanasi.hrms.contract.api",
]

[[tool.importlinter.contracts]]
name = "domain layer is framework-free"
type = "forbidden"
source_modules = ["varanasi.platform.internal.domain",
                  "varanasi.billing.internal.domain",
                  "varanasi.hrms.internal.domain"]
forbidden_modules = ["fastapi", "sqlalchemy", "aio_pika"]
```

### 4. Python naming

Follow **PEP 8**. In addition:

| Thing | Convention | Example |
|-------|------------|---------|
| Packages / modules (files) | `snake_case`, short | `leave_request.py` |
| Classes | `PascalCase` | `LeaveRequest` |
| Functions / methods | `snake_case`, **starting with a verb** | `issue_invoice()`, `get_employee()` |
| Variables | `snake_case`, descriptive (no `x`, `tmp`, `data2`) | `due_date`, `open_invoices` |
| Booleans | `is_` / `has_` / `can_` prefix | `is_active`, `has_login` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_PAGE_LIMIT = 200` |
| Private (module-internal) | Leading underscore | `_calculate_tax()` |
| Contract interface | `<Concept>Api` (a `Protocol`) | `InvoiceApi`, `EntitlementApi` |
| Contract DTO | Plain noun describing the shape | `InvoiceSummary`, `UserSummary` |
| Domain entity | Plain noun | `Invoice`, `Employee` |
| SQLAlchemy model | `<Entity>Model` | `InvoiceModel` |
| Repository | `<Entity>Repository` | `InvoiceRepository` |
| Use case / service | `<Entity>Service` or verb phrase | `InvoiceService`, `IssueInvoice` |
| HTTP request / response schemas | `<Entity><Action>Request`, `<Entity>Response` | `InvoiceCreateRequest`, `InvoiceResponse` |
| Event payload model | `<Entity><Action>V<n>` | `InvoiceIssuedV1` |
| Event consumer | `on_<event>` function in `consumers/` | `on_tenant_suspended_v1()` |
| Errors / exceptions | `<Problem>Error` | `InvoiceAlreadyIssuedError` |
| Tests | `test_<unit>_<behaviour>` | `test_issue_invoice_rejects_already_issued` |

Other rules:

- **Type hints are mandatory** on all functions. `mypy --strict` must pass.
- Use `async` for anything doing I/O (DB, HTTP, broker).
- Never use bare `except:`. Catch specific errors, and let unknown errors surface.
- Money is always `decimal.Decimal`, never `float`.
- Datetimes are always timezone-aware UTC (`datetime.now(UTC)`).
- No `print()`. Use the logger (section 11).

### 5. Database naming

| Thing | Convention | Example |
|-------|------------|---------|
| Schema | Module name | `platform`, `billing`, `hrms` |
| Table | `snake_case`, **singular** | `billing.invoice`, `hrms.leave_request` |
| Join table | Both names, alphabetical | `platform.role_user` |
| Reference (global) table | `_ref` suffix, no `tenant_id` (ADR-0006) | `platform.currency_ref` |
| Primary key | `id UUID` (v7) | `id` |
| Tenant column | `tenant_id UUID NOT NULL` on every business table | `tenant_id` |
| Foreign key column | `<referenced_entity>_id` | `customer_id`, `employee_id` |
| Timestamps | `timestamptz`, `_at` suffix | `created_at`, `updated_at`, `issued_at` |
| Dates | `date`, `_date` / `_on` suffix | `due_date`, `received_on` |
| Booleans | `is_` / `has_` prefix, `NOT NULL` with a default | `is_active` |
| Enums / statuses | `text` + `CHECK` constraint (not PostgreSQL `ENUM`, which is hard to change) | `status text CHECK (status IN ('draft','issued','void'))` |
| Money | Two columns: `<name>_amount numeric(19,4)` + `<name>_currency char(3)` | `total_amount`, `total_currency` |
| Optimistic lock version (ETag, ADR-0007) | `version integer NOT NULL DEFAULT 1` | `version` |
| Primary key constraint | `pk_<table>` | `pk_invoice` |
| Foreign key constraint | `fk_<table>__<column>__<ref_table>` | `fk_invoice__customer_id__customer` |
| Unique constraint | `uq_<table>__<columns>` | `uq_invoice__tenant_id_invoice_number` |
| Index | `ix_<table>__<columns>` | `ix_invoice__tenant_id_issue_date` |
| Check constraint | `ck_<table>__<rule>` | `ck_invoice__status` |
| RLS policy | `tenant_isolation` (ADR-0006) | |
| Standard technical tables (per module schema) | `outbox`, `processed_event`, `idempotency_record` | `billing.outbox` |

**DB roles** (ADR-0003, ADR-0006): `varanasi_platform_app`, `varanasi_billing_app`,
`varanasi_hrms_app` (runtime, own schema only, no `BYPASSRLS`), `varanasi_migrator`
(migrations only), `varanasi_platform_admin` (audited Platform admin operations).

**Migrations**

- One Alembic history per module: `src/varanasi/<module>/migrations/`.
- File name: `YYYYMMDD_HHMM_<short_description>.py`, e.g.
  `20260927_1015_create_invoice.py`.
- **Forward-only in production.** A `downgrade()` is written for local use, but fixes in
  production are made with a new migration.
- Breaking schema changes use **expand → migrate → contract** across releases. For
  example: add the new column, backfill, switch the code, then drop the old column in a
  later release.
- CI schema lint (ADR-0006): every new business table must have `tenant_id`, RLS,
  `FORCE RLS` and the `tenant_isolation` policy.

### 6. API naming

The full rules are in ADR-0007. Summary for code:

| Thing | Convention | Example |
|-------|------------|---------|
| Path | `/api/v1/<plural-kebab-noun>` | `/api/v1/leave-requests` |
| Action path | `POST /<resource>/{id}/<verb>` | `/api/v1/invoices/{id}/issue` |
| JSON fields & query params | `snake_case` | `due_date`, `?issue_date[gte]=` |
| `operationId` | `<module>_<resource>_<action>` | `billing_invoices_create`, `hrms_leave_requests_approve` |
| OpenAPI tag | Module name | `billing` |
| Permission | `<module>.<resource>.<action>` (singular resource) | `billing.invoice.issue` |
| Error `code` | `snake_case` | `invoice_already_issued` |
| Router file | `internal/http/<resource>_router.py` | `invoice_router.py` |

### 7. Git branch naming

```
<type>/<module>-<short-description>
```

- `type`: the same types as commits (section 8): `feat`, `fix`, `chore`, `docs`,
  `refactor`, `test`, `perf`, `ci`, `build`.
- `module`: `platform`, `billing`, `hrms`, `shared`, `infra`, `docs`.
- `short-description`: 2–5 words in `kebab-case`, lowercase.

Examples:

```
feat/billing-invoice-api
fix/hrms-leave-validation
chore/platform-auth-cleanup
docs/adr-event-broker
ci/infra-openapi-diff-check
```

**Branching model: trunk-based.**

- `main` is always releasable and **protected**: no direct pushes, no force pushes, and
  merges need a PR with green CI.
- Branches are **short-lived** (ideally under 3 days) and branched from `main`.
- Unfinished features that are merged stay hidden behind a feature flag.
- Releases are **tags** on `main`: `vMAJOR.MINOR.PATCH`, e.g. `v0.3.0`.
- Production hotfixes: a `fix/...` branch from `main`, merged, then a new patch tag.

### 8. Commit conventions: Conventional Commits 1.0

```
<type>(<scope>): <subject>

[optional body: what and WHY, wrapped at 72 characters]

[optional footer(s)]
```

| Part | Rule |
|------|------|
| `type` | `feat` (new feature), `fix` (bug fix), `docs`, `refactor` (no behaviour change), `test`, `perf`, `chore` (maintenance), `ci`, `build` (build/dependencies), `revert` |
| `scope` | **Required.** `platform`, `billing`, `hrms`, `shared`, `infra`, `deps`, `docs`, `adr` |
| `subject` | Imperative mood ("add", not "added"), lowercase, no full stop, **≤ 72 characters** including type and scope |
| Breaking change | `!` after the scope **and** a `BREAKING CHANGE:` footer explaining it |
| Task reference | Footer `Refs: M0-ARC-008` (or ticket ID) |

Examples:

```
feat(billing): add invoice creation
fix(hrms): prevent duplicate leave requests
refactor(platform): extract token verification into shared auth
docs(adr): freeze event broker decision
chore(deps): bump fastapi to 0.x.y
```

```
feat(billing)!: require currency on invoice lines

Invoice lines previously inherited the invoice currency. Mixed-currency
lines are now supported, so each line must declare its currency.

BREAKING CHANGE: POST /api/v1/invoices now rejects lines without currency.
Refs: BIL-142
```

- Enforced by a **commitizen** pre-commit hook locally, and in CI on the PR title.
- The changelog and version bumps are generated from commits (`cz bump`, `cz changelog`).

### 9. Pull request conventions

- **The PR title is a Conventional Commit** (e.g. `feat(billing): add invoice creation`),
  because PRs are **squash-merged** and the title becomes the commit on `main`.
- **Keep PRs small.** Aim for under ~400 changed lines (excluding generated files). Split
  larger work.
- Open a **draft PR** early for work in progress.
- The **description** uses [`.github/pull_request_template.md`](../../.github/pull_request_template.md):
  What / Why / How to test, whether an architecture review is needed, and the **full
  ADR-0010 architecture review checklist**. Every item is ticked or marked
  `N/A: <reason>`.

- **Reviews**
  - At least **1 approval**.
  - **CODEOWNERS** approval is also required for:
    - `*/contract/**` (module contracts, ADR-0003)
    - `*/migrations/**`
    - `docs/adr/**`
    - `src/varanasi/shared/**`
    - `deploy/**`
- **Merging needs green CI:** ruff, mypy, import-linter, schema lint, tests, OpenAPI diff
  and secret scan.
- **Merge method:** squash merge only. Delete the branch after merging.
- The author resolves review comments. The reviewer approves once they're satisfied.

### 10. Environment variables

- **Prefix `VARANASI_`**, `UPPER_SNAKE_CASE`, grouped by area.
- Read **only** in `src/varanasi/settings.py` using **pydantic-settings**. Nowhere else
  calls `os.environ`.
- The app **fails at startup** if a required variable is missing or invalid. No silent
  defaults for anything security-related.
- `.env.example` is committed and lists **every** variable with a safe example value. The
  real `.env` is in `.gitignore`.
- **Secrets are never committed.** In production they come from the secret store
  (ADR-0011) and are never logged, even at debug level.

Standard variables:

| Variable | Example | Notes |
|----------|---------|-------|
| `VARANASI_ENV` | `local` | One of `local`, `test`, `staging`, `production` |
| `VARANASI_LOG_LEVEL` | `INFO` | |
| `VARANASI_LOG_FORMAT` | `json` | `json` (servers) or `console` (local) |
| `VARANASI_DB_PLATFORM_URL` | `postgresql+asyncpg://varanasi_platform_app:***@db:5432/varanasi` | One URL per module DB role (ADR-0003) |
| `VARANASI_DB_BILLING_URL` | … | |
| `VARANASI_DB_HRMS_URL` | … | |
| `VARANASI_DB_MIGRATOR_URL` | … | Only used by the migration job |
| `VARANASI_RABBITMQ_PLATFORM_URL` | `amqps://varanasi_platform:***@mq:5671/varanasi` | One RabbitMQ user per module, limited to its own routing keys and queues (ADR-0005) |
| `VARANASI_RABBITMQ_BILLING_URL` | … | |
| `VARANASI_RABBITMQ_HRMS_URL` | … | |
| `VARANASI_AUTH_ISSUER` | `https://api.varanasi.app` | JWT `iss` |
| `VARANASI_AUTH_PRIVATE_KEY_FILE` | `/run/secrets/jwt_private_key.pem` | Secrets are passed as **files** (`_FILE` suffix) where possible |
| `VARANASI_CORS_ALLOWED_ORIGINS` | `https://app.varanasi.app` | Comma-separated |
| `VARANASI_PAYMENT_PROVIDER_WEBHOOK_SECRET_FILE` | `/run/secrets/payment_webhook` | ADR-0001 external provider |

### 11. Logging conventions

- **Structured JSON** logs to **stdout** using structlog. The deployment collects them.
  Local development may use the `console` format.
- The **message is a short `snake_case` event name**. Details go in fields:
  `log.info("invoice_issued", invoice_id=…, total_amount=…)`.
- These fields are **added automatically** to every log line by middleware or context:

  | Field | Source |
  |-------|--------|
  | `timestamp` (UTC), `level`, `logger` | structlog |
  | `correlation_id` | `X-Correlation-ID` / event envelope (ADR-0007, ADR-0004) |
  | `tenant_id`, `user_id` | Tenant context / token (ADR-0006) |
  | `module` | `platform` / `billing` / `hrms` |
  | `event_id`, `event_name` | Inside event consumers |
  | `http_method`, `http_path`, `http_status`, `duration_ms` | Request log (one line per request) |

- **Levels**

  | Level | Use for |
  |-------|---------|
  | `DEBUG` | Developer detail. Off in production |
  | `INFO` | Normal business milestones (`invoice_issued`, `pay_run_finalized`), requests |
  | `WARNING` | Something unexpected that was handled (retry scheduled, deprecated endpoint called) |
  | `ERROR` | A failed operation that needs attention (a message sent to the DLQ, an unhandled exception) |
  | `CRITICAL` | The app can't function (DB unreachable at startup) |

- **Never log:**
  - passwords, tokens, API keys or secrets;
  - full request or response bodies;
  - salary, bank or card numbers, or government IDs (PAN/Aadhaar);
  - medical or leave-reason text.

  Email addresses and phone numbers are masked (`a***@example.com`). A structlog processor
  redacts known sensitive keys as a safety net.
- Exceptions are logged once, where they are handled, with `exc_info`. Don't log the same
  exception and re-raise it at every layer.

### 12. Documentation rules

| What | Where | Rule |
|------|-------|------|
| **Architecture decisions** | `docs/adr/NNNN-title.md` | Any decision that is hard to reverse or affects more than one module needs an ADR. Numbers are never reused; accepted ADRs are superseded, never rewritten |
| **Module overview** | `src/varanasi/<module>/README.md` | Purpose, owned concepts (ADR-0002), contract operations, events published/consumed, permissions |
| **API** | `docs/api/openapi.json` (generated) | Every endpoint has a summary, description, examples, `x-permission`, and error responses |
| **Events** | `contract/events/*.json` + ADR-0004 catalogue | Updated in the same PR as the event change |
| **Code** | Docstrings | Required on every public contract function, class and module (Google style). Comments explain **why**, not what |
| **Operations** | `docs/runbooks/` | A runbook for each alert (e.g. "DLQ not empty", "outbox backlog", "restore database") |
| **Changelog** | `CHANGELOG.md` | Generated from Conventional Commits. Not hand-edited |
| **Repository README** | `README.md` | How to set up, run, test and deploy locally in **under 15 minutes** |

**Docs are part of "done".** A PR that changes behaviour, a contract, an event, the API
or operations must update the matching docs **in the same PR**.

## Options considered

| Topic | Chosen | Rejected and why |
|-------|--------|------------------|
| Framework | FastAPI | **Django**: batteries included, but its ORM and app model fight schema-per-module + RLS + async; its admin could bypass contracts. **Flask**: too little built in (validation, OpenAPI) |
| Repo | Monorepo | **Repo per module**: overhead with no benefit for a single deployable (ADR-0001) |
| Branching | Trunk-based + short branches | **GitFlow**: long-lived `develop`/`release` branches slow a small team down and cause merge pain |
| Merge | Squash | **Merge commits**: noisy history. **Rebase-merge**: every WIP commit would need to follow the commit convention |
| Enums in DB | `text` + `CHECK` | **PostgreSQL `ENUM`**: removing or renaming values needs painful migrations |

## Consequences

- **Positive**
  - Every module looks the same, so it's quick to find things and onboard.
  - Boundary rules (ADR-0003), tenant rules (ADR-0006) and API rules (ADR-0007) are
    checked automatically in CI.
  - Clean, searchable history and a generated changelog.
  - Logs can be traced by `correlation_id` and filtered by `tenant_id`, without leaking
    sensitive data.
- **Negative / trade-offs**
  - Upfront setup work: pre-commit, CI jobs, import-linter, schema lint, Spectral and
    oasdiff.
  - Strict typing and small-PR discipline take getting used to.
  - "Contract-first" with a code-generated spec needs the two-step PR habit.
- **Follow-ups**
  - M1: create the repository skeleton exactly as in section 2, with CI running all
    checks from day one.
  - ADR-0009: test layout and Testcontainers setup.
  - ADR-0010: reference these conventions in the review checklist.
  - ADR-0011: the secret store and how secrets are mounted as files.

## References

- PEP 8, PEP 484
- Conventional Commits 1.0.0 (conventionalcommits.org)
- ADR-0003 Module Contracts
- ADR-0004 Event Taxonomy
- ADR-0005 Event Broker
- ADR-0006 Tenant Isolation
- ADR-0007 API Standards
