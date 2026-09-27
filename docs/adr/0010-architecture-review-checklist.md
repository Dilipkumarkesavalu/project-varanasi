# ADR-0010: Architecture Review Checklist

- **Status:** Accepted (M0 approval, 2026-09-27)
- **Date:** 2026-09-27
- **Milestone:** M0
- **Task:** M0-ARC-010
- **Deciders:** Project owner (see `docs/architecture/M0-APPROVAL.md`)
- **Depends on:** ADR-0001 – ADR-0009, ADR-0011
- **Supersedes / Superseded by:** —

## Context

ADR-0001 to ADR-0009 set the rules: product boundaries, one owner per concept,
API-or-event only, the event format, RabbitMQ with an outbox, tenant isolation, API
standards, conventions and tests. Rules only help if every change is checked against them.

This matters even more because **much of our code will be written with AI assistants**.
AI-generated code compiles and looks right, but it tends to:

- take shortcuts: querying another module's table, or skipping the tenant filter "just
  here";
- forget cross-cutting concerns such as authorization, audit, correlation IDs and the
  outbox;
- invent libraries, functions or config options that don't exist;
- silence failures (`# type: ignore`, `except Exception: pass`, deleted or skipped tests)
  to make CI pass;
- produce large diffs that are tiring to review line by line.

CI catches a lot (ADR-0009), but not everything. For example, it can't tell whether an
action *should* be audited or whether an interaction *should* be an event. We need one
checklist that every author, human or AI-assisted, answers on every PR.

## Decision

1. **Every PR answers the checklist below.** It is built into
   `.github/pull_request_template.md`, so it appears automatically.
2. Each item is answered with **☑ ticked** (done/true) or **`N/A: <reason>`**. An empty
   box, or `N/A` with no reason, means the PR is **not ready for review**.
3. Items marked 🔴 are **blockers**. A reviewer must not approve while any of them fails.
4. Items marked 🤖 are also **checked automatically in CI** (ADR-0009). The tick confirms
   the author thought about it; CI confirms it's true.
5. Some changes need an **architecture review** in addition to the normal review
   (section 4).

### 1. The checklist

#### A. Tenant isolation (ADR-0006, frozen)

| # | Question | How to check | |
|---|----------|--------------|---|
| A1 | **Does every business query enforce tenant isolation?** | All DB access goes through the tenant-aware session (`SET LOCAL app.tenant_id`). No raw connection, no `BYPASSRLS` role, no disabled RLS | 🔴 🤖 |
| A2 | Is `tenant_id` taken **only** from the token / tenant context, never from the request body, query or headers? | Search the diff for `tenant_id` in request schemas | 🔴 🤖 |
| A3 | Do new tables have `tenant_id NOT NULL`, forced RLS, the `tenant_isolation` policy and composite tenant FKs? | The schema lint passes | 🔴 🤖 |
| A4 | Do cache keys, file paths, background jobs and exports carry the tenant? | `t:{tenant_id}:…`, `tenants/{tenant_id}/…`, jobs set the context per tenant | 🔴 |
| A5 | Does another tenant's resource return `404`, not `403`? | Cross-tenant tests | 🔴 🤖 |

#### B. Authorization (ADR-0007 §12)

| # | Question | How to check | |
|---|----------|--------------|---|
| B1 | **Is authorization checked** on every new or changed endpoint, action and contract operation? | The endpoint has a permission dependency, and the OpenAPI has `x-permission` | 🔴 🤖 |
| B2 | Are new permissions named `<module>.<resource>.<action>` and registered in `permissions.py`? | | 🔴 |
| B3 | Is the **entitlement** checked for product features, and **suspension** for writes? | | 🔴 |
| B4 | Are sensitive fields (salary, bank, government IDs) hidden unless the user has `*.read_sensitive`? | | 🔴 |

#### C. Module boundaries (ADR-0002, ADR-0003, frozen)

| # | Question | How to check | |
|---|----------|--------------|---|
| C1 | **Did I access another module's database directly?** (Must be **No**.) | No SQL, ORM model, view or join touching another schema. No import of another module's `internal/` | 🔴 🤖 |
| C2 | **Should this interaction be an API or an event instead?** | Need an answer now → contract API call. Announcing a fact → event. Platform → Billing/HRMS is **events only**. Billing ↔ HRMS must still work if the other product isn't enabled | 🔴 |
| C3 | Does every new business concept have exactly **one owner**, recorded in ADR-0002? | | 🔴 |
| C4 | Do contract changes keep backward compatibility (or add a new version, migrate the consumers, then remove the old one)? | CODEOWNERS approved the `contract/` change | 🔴 |
| C5 | Does `shared/` contain only technical code, with no business rules? | | 🟡 |

#### D. Events and messaging (ADR-0004, ADR-0005, frozen)

| # | Question | How to check | |
|---|----------|--------------|---|
| D1 | **Are events emitted through the approved mechanism?** | Published **only** via the module's outbox. No direct `aio_pika` publishing, no other broker, no HTTP callbacks between modules | 🔴 🤖 |
| D2 | **Is the outbox pattern used where required?** | Every event about a DB change is written to the outbox **in the same transaction** as the change | 🔴 |
| D3 | Are new events named `<module>.<entity>.<past-tense>.v<N>`, with a JSON Schema and a row in the ADR-0004 catalogue (producer, consumers, payload)? | | 🔴 🤖 |
| D4 | Is the payload free of sensitive data (salary, bank or card numbers, PAN/Aadhaar, secrets, leave reasons)? | | 🔴 |
| D5 | Are new consumers **idempotent** (`processed_event`), tenant-scoped, and do they classify errors as temporary (retry) or permanent (DLQ)? | Queue added to `deploy/rabbitmq/definitions.json` | 🔴 🤖 |

#### E. API standards (ADR-0007)

| # | Question | How to check | |
|---|----------|--------------|---|
| E1 | Do paths, methods, status codes, errors (Problem Details), pagination, filtering and sorting follow ADR-0007? | Spectral passes | 🔴 🤖 |
| E2 | Do creating `POST`s require `Idempotency-Key`, and do `PATCH`/actions require `If-Match`? | | 🔴 |
| E3 | Is `docs/api/openapi.json` regenerated, with no unintended breaking change? | oasdiff passes | 🔴 🤖 |

#### F. Observability (ADR-0007 §10, ADR-0008 §11)

| # | Question | How to check | |
|---|----------|--------------|---|
| F1 | **Does every request have a correlation ID**, and is it passed into logs, contract calls and every event's `correlation_id`? | Uses the shared middleware and context. No new entry point (job, consumer, script) without one | 🔴 |
| F2 | Are logs structured (`log.info("snake_case_event", …)`) with **no** secrets, tokens, full bodies or sensitive personal data? | | 🔴 |
| F3 | Do new failure modes have a log at the right level, and an alert and runbook if operators must act? | | 🟡 |

#### G. Audit (ADR-0001, ADR-0002)

| # | Question | How to check | |
|---|----------|--------------|---|
| G1 | **Are sensitive actions audited?** | Any action on the list in section 2 records an audit entry through `AuditApi`. That writes `<module>.audit_entry.recorded.v1` to the module's own outbox **in the same transaction** as the change (ADR-0004 §7), never "fire and forget" | 🔴 |
| G2 | Does the audit entry say **who** (`actor_id`), **what** (action + resource ID), **when**, **which tenant**, and the `correlation_id`, **without** the sensitive values themselves? | | 🔴 |

#### H. Data and migrations (ADR-0006, ADR-0008 §5)

| # | Question | How to check | |
|---|----------|--------------|---|
| H1 | Does each migration follow the naming rules, only touch its own module's schema, and is it safe on large tables (expand → migrate → contract)? | Migration tests | 🔴 🤖 |
| H2 | Money is `Decimal` / `numeric(19,4)` + currency, times are UTC, IDs are UUIDv7? | | 🔴 |
| H3 | Are financial and legal records voided or reversed, never deleted? | | 🔴 |

#### I. Tests (ADR-0009)

| # | Question | How to check | |
|---|----------|--------------|---|
| I1 | **Are the required tests included?** Unit tests for business rules, integration tests for DB and messaging, **a cross-tenant case for every new or changed endpoint**, contract tests for contract/event changes, and migration tests if the schema changed | The merge gate and route coverage check pass | 🔴 🤖 |
| I2 | Do the tests actually check the behaviour? (Not just "it runs": they assert the results, including the failure paths.) | | 🔴 |
| I3 | Were **no** tests deleted, skipped or weakened, and no `# type: ignore` / `noqa` / coverage exclusions added without a written reason? | | 🔴 |
| I4 | Is E2E run if the change is on the ADR-0009 §4 trigger list? | | 🔴 🤖 |

#### J. ADR compliance

| # | Question | How to check | |
|---|----------|--------------|---|
| J1 | **Does this change violate any ADR?** If it does, the PR must not merge. Write a new or superseding ADR first | Especially the **frozen** ones: 0003 (DB/module rule), 0005 (RabbitMQ), 0006 (tenant isolation), 0011 (cloud, A-016) | 🔴 |
| J2 | Does this change make a **new** hard-to-reverse or cross-module decision? If yes, is there an ADR in this PR or linked? | | 🔴 |
| J3 | Are docs updated in the same PR (module README, event catalogue, runbooks, OpenAPI)? | | 🟡 |

#### K. AI-assisted changes

| # | Question | How to check | |
|---|----------|--------------|---|
| K1 | Was AI used to write a meaningful part of this PR? (Declare it. It isn't a problem; it tells the reviewer where to look harder) | | — |
| K2 | Have I **read and understood every line**, and can I explain it? The author is responsible, not the tool | | 🔴 |
| K3 | Do all libraries, functions, config options and CLI flags used **actually exist** in the versions we lock? | `uv.lock`, the docs | 🔴 |
| K4 | Is the diff free of the AI red flags in section 3? | | 🔴 |
| K5 | Were **no secrets, customer data or production data** pasted into an AI tool while making this change? | | 🔴 |

🔴 = blocker · 🟡 = should fix (the reviewer may accept a follow-up ticket) · 🤖 = also
enforced by CI

### 2. Sensitive actions that must be audited (G1)

| Area | Actions |
|------|---------|
| Access | Login success or failure, logout, token refresh failure, password or MFA change, tenant switch |
| Users & roles | User invited, deactivated or reactivated; role assigned or revoked; permission set changed |
| Tenant | Tenant created, suspended, reactivated or closed; tenant settings changed; entitlement or plan changed |
| Support | Any support or admin cross-tenant access (ADR-0006 rule 9): start, end and actions |
| Billing | Invoice issued or voided; payment recorded or reversed; customer deleted or merged |
| HRMS | Employee created or terminated; salary, bank or government-ID fields changed or **viewed**; pay run finalized; leave approved or rejected |
| Data | Any export or bulk download; any bulk delete or import |
| Operations | DLQ message discarded (ADR-0005); manual data fix scripts |

New sensitive actions are added to this table in the same PR that introduces them.

### 3. Red flags reviewers search the diff for

These usually point to a rule being broken. Many are common in AI-generated code.

| Red flag in the diff | Likely problem | Rule |
|----------------------|----------------|------|
| `text("SELECT` / raw SQL / `session.execute("…")` | Bypassing the repository or tenant session; possible cross-schema access | A1, C1 |
| `platform.` / `billing.` / `hrms.` schema names in another module's SQL | Direct access to another module's DB | C1 |
| `from varanasi.<other_module>.internal` | Going around the contract | C1 |
| `tenant_id` in a request schema or `request.headers` | Trusting a client-supplied tenant | A2 |
| `SET app.tenant_id` without `LOCAL`, or `BYPASSRLS`, `DISABLE ROW LEVEL SECURITY` | Tenant setting leaking between requests, or isolation turned off | A1 |
| A route with no permission dependency / no `x-permission` | Missing authorization | B1 |
| `aio_pika` imported outside `shared/messaging` | Publishing without the outbox | D1, D2 |
| An event published after `commit()` or in a `try` after the transaction | Lost or phantom events | D2 |
| `os.environ` outside `settings.py` | Unvalidated configuration | ADR-0008 §10 |
| `print(`, logging `request.body`, logging `password`/`token` | Leaking data into logs | F2 |
| `except Exception: pass`, or `except:` that swallows the error | Hidden failures, which also break DLQ routing | D5, F3 |
| `float` used for money | Rounding errors | H2 |
| `datetime.now()` without `UTC` | Timezone bugs | H2 |
| `# type: ignore`, `# noqa`, `pytest.mark.skip`, deleted asserts | Silencing checks | I3 |
| A new dependency in `pyproject.toml` | Is it real, maintained, licensed, and needed? | K3 |
| A very large generated diff (> ~400 lines) | Hard to review properly. Split it | ADR-0008 §9 |

### 4. When an architecture review is also required

A normal review needs 1 approval (ADR-0008 §9). Changes that could weaken the architecture
**also** need approval from an **architecture reviewer** (CODEOWNERS for `docs/adr/**`)
when the PR:

- adds or changes a module **contract** (`*/contract/**`) or an **event** definition;
- adds a new **business concept**, module, or cross-module interaction;
- touches `src/varanasi/shared/**` (auth, tenancy, db session, messaging);
- adds a new **table** or changes RLS, DB roles or tenant handling;
- adds an external **dependency** or service, or changes `deploy/**`;
- adds or changes an **ADR**, or asks for an exception to one.

The architecture reviewer uses this same checklist, focusing on sections A, C, D and J.

### 5. Where the checklist lives

- **PR template:** `.github/pull_request_template.md` contains the full checklist
  (short form with the item IDs). It is created alongside this ADR.
- **This ADR** is the long form with the "how to check" guidance. The template links here.
- When an ADR is added or changed, this checklist is updated **in the same PR**.

## Options considered

| Option | Verdict | Why |
|--------|---------|-----|
| Rely on CI only | ❌ | CI can't judge "should this be an event?" or "is this action sensitive?" |
| A checklist on a wiki page | ❌ | Nobody opens it. It has to be in the PR itself |
| **A checklist in the PR template + CI + an architecture reviewer for risky changes (chosen)** | ✅ | The author thinks, CI verifies, and a second person checks the high-risk areas |
| A separate architecture board meeting for every change | ❌ | Too slow for a small team. Kept to section 4 cases, done asynchronously in the PR |

## Consequences

- **Positive**
  - Every PR, human or AI-assisted, is checked against the same rules.
  - Blockers are explicit, so reviews are faster and less subjective.
  - The red-flag list makes the typical AI shortcuts easy to spot.
- **Negative / trade-offs**
  - Longer PR descriptions. Authors must answer every item (N/A is quick when it
    really doesn't apply).
  - Risky changes wait for an architecture reviewer.
  - The checklist must be kept in sync with the ADRs.
- **Follow-ups**
  - Create `.github/CODEOWNERS` with the architecture reviewers (M1, when the repo
    skeleton is created).
  - Optional CI job: fail if the PR description still has unanswered checklist boxes.
  - Consider an AI-assistant instructions file (e.g. `CLAUDE.md` / `AGENTS.md`) that
    points AI tools to these ADRs and this checklist, so the code is right the first time.

## References

- ADR-0001 – ADR-0009, ADR-0011
- `.github/pull_request_template.md`
