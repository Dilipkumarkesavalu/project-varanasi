# ADR-0006: Tenant Isolation

- **Status:** Accepted (M0 approval, 2026-09-27). **FROZEN.**
- **Date:** 2026-09-27
- **Milestone:** M0
- **Task:** M0-ARC-006
- **Deciders:** Project owner (see `docs/architecture/M0-APPROVAL.md`)
- **Depends on:** ADR-0001 Product Separation, ADR-0002 Service Boundaries, ADR-0003
  Module Contracts, ADR-0004 Event Taxonomy, ADR-0005 Event Broker
- **Supersedes / Superseded by:** —

## Context

Many customer organizations (**tenants**) will use the same application. Their data,
including employees, salaries, invoices and customers, is confidential. A single leak
between tenants is a serious business, legal and trust failure.

What is already decided:

- One modular application on a dedicated server (ADR-0001).
- A separate database schema per module (`platform`, `billing`, `hrms`). No module
  touches another module's tables (ADR-0003, frozen).
- Every event carries a `tenant_id` (ADR-0004).

We also expect that some **large enterprise customers** will want their own separate
deployment. We need to support that **without maintaining a second codebase**.

## Decision

### 1. The two tenant types

| | **Shared tenant** (default) | **Dedicated tenant** (enterprise) |
|---|---|---|
| **Who** | All customers by default | Large enterprise customers who qualify (section 5) |
| **Application** | The shared application instance | Its **own** application instance |
| **Database** | **One shared PostgreSQL database.** Rows are separated by `tenant_id` | Its **own** PostgreSQL database (only this tenant's rows) |
| **Event broker** | Shared RabbitMQ; tenant separated by `tenant_id` in every event | Its **own** RabbitMQ instance |
| **Files / cache** | Shared storage and cache, with `tenant_id` prefixes | Its own storage and cache |
| **Server / region** | The shared dedicated server | A separate server; region can be chosen for data residency |
| **Application code** | **The same code** | **The same code**: same release, same migrations |
| **Isolation rules** | Everything in this ADR | Everything in this ADR, **also** applied (defense in depth) |
| **Backups / restore** | Whole-database backups; per-tenant restore via export tooling | Its own backups, schedule and retention |
| **Cost** | Lowest | Higher; priced into the enterprise contract |

**The key principle:** a dedicated tenant is **the same application with a different
deployment configuration**, not a different product.

- There are **no `if dedicated` branches** in business code.
- There are **no customer-specific forks**.
- The dedicated database still has a `tenant_id` column and the same Row-Level Security
  (RLS) rules. It just contains only one tenant.

### 2. Shared tenant model: how data is separated

```
                 One PostgreSQL database
 ┌────────────────┬────────────────┬────────────────┐
 │ schema:        │ schema:        │ schema:        │
 │ platform       │ billing        │ hrms           │
 │                │                │                │
 │ tenant_id on   │ tenant_id on   │ tenant_id on   │
 │ every business │ every business │ every business │
 │ table + RLS    │ table + RLS    │ table + RLS    │
 └────────────────┴────────────────┴────────────────┘
```

#### Table rules

1. **Every business table has `tenant_id UUID NOT NULL`.** No exceptions for "small"
   tables, logs, attachments, settings or join tables.
2. `tenant_id` is the **first column** of every index and unique constraint used for
   business lookups. For example, invoice numbers are unique **per tenant**:
   `UNIQUE (tenant_id, invoice_number)`.
3. **Foreign keys include `tenant_id`**: `FOREIGN KEY (tenant_id, customer_id)
   REFERENCES billing.customer (tenant_id, id)`. This makes it impossible to link a
   Tenant A invoice to a Tenant B customer, even by mistake.
4. **Primary keys are UUIDs (v7)**, never sequential integers, so IDs can't be guessed
   or enumerated across tenants.
5. **Global reference data** such as countries, currencies and standard tax code lists
   is the **only** kind of data without `tenant_id`. It lives in clearly named tables
   (`*_ref`), is owned by one module, and the application can only read it. Tenant
   customisations of reference data go in a separate tenant-scoped table.

#### Tenants and users

- `platform.tenant` is the list of tenants itself. It's managed only by Platform
  (ADR-0002).
- A **user may belong to more than one tenant** through `platform.tenant_membership`.
  (An accountant serving two companies is an example.)
- A user's session and token are always scoped to **one active tenant**. Switching
  tenants issues a new token. There is never a request that acts on two tenants at once.

### 3. How isolation is enforced: four layers

We don't rely on developers remembering a `WHERE tenant_id = ?`. Four independent
layers each block a leak on their own.

#### Layer 1: identity (where `tenant_id` comes from)

- The active `tenant_id` comes **only from the Platform-issued token** (ADR-0002).
- It is **never** taken from the request body, query string, URL path or a custom
  header sent by the client.
- If a URL contains a tenant identifier (e.g. a subdomain `acme.app.com`), it is only
  used for routing, and it must **match** the token's tenant. Otherwise the request is
  rejected.

#### Layer 2: application tenant context

- Every entry point sets a **tenant context** before any business code runs:

  | Entry point | Where `tenant_id` comes from |
  |-------------|------------------------------|
  | HTTP request | The verified token |
  | Event consumer | The event's `tenant_id` (ADR-0004), validated to be an existing, active tenant |
  | Background / scheduled job | The job's stored `tenant_id`. Jobs covering "all tenants" loop and set the context **per tenant** |
  | Contract API call between modules | The caller's current tenant context (ADR-0003 rule 4) |

- If code tries to access tenant data **without a tenant context, it fails with an
  error.** It never falls back to "no filter".
- The data-access layer adds `tenant_id` to every query and every insert automatically.

#### Layer 3: database Row-Level Security (the hard guarantee)

PostgreSQL **Row-Level Security** is enabled and **forced** on every business table:

```sql
ALTER TABLE hrms.employee ENABLE ROW LEVEL SECURITY;
ALTER TABLE hrms.employee FORCE  ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON hrms.employee
  USING      (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
  WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);
```

- At the start of every transaction, the app runs
  `SET LOCAL app.tenant_id = '<tenant uuid>'`. Because it is `LOCAL`, the value is
  cleared at the end of the transaction and can't leak to the next request that reuses
  the pooled connection.
- **It fails closed.** If `app.tenant_id` isn't set, the policy matches **no rows**. A
  forgotten context returns nothing; it never returns everything.
- `WITH CHECK` stops code from inserting or updating a row into another tenant.
- Each module's DB role (ADR-0003) is **not** a superuser, does **not** own the tables,
  and does **not** have `BYPASSRLS`.
- Migrations run with a separate migration role that the application never uses at
  runtime.

#### Layer 4: everything outside the database

| Where data lives | Rule |
|------------------|------|
| **Events** | `tenant_id` is required. Events without it go to the DLQ (ADR-0004, ADR-0005) |
| **Cache** | Every key starts with the tenant: `t:{tenant_id}:…` |
| **Files / object storage** | Every path starts with the tenant: `tenants/{tenant_id}/…`. Download links are short-lived and checked against the tenant context |
| **Logs & traces** | Every line includes `tenant_id`. Logs never contain another tenant's data |
| **Search indexes** (if added) | A tenant filter is applied on the server, never only in the UI |
| **Exports & reports** | Generated within one tenant context only |
| **Emails / notifications** | Recipients are resolved inside the tenant context |

### 4. What must NEVER happen

These are absolute. Any violation is a **severity-1 security incident**.

| # | Never | Example |
|---|-------|---------|
| 1 | **Tenant A cannot query, see, change or delete Tenant B's data**, through any route: API, UI, export, report, search, file, cache, event or log | ❌ `GET /invoices/{id}` returns an invoice that belongs to another tenant |
| 2 | Never trust a `tenant_id` sent by the client | ❌ `POST /employees { "tenant_id": "…B…" }` |
| 3 | Never run a query on a business table without a tenant context | ❌ `SELECT * FROM billing.invoice` in a background job |
| 4 | Never join or link rows across tenants | ❌ An invoice whose `customer_id` belongs to another tenant (blocked by composite FKs) |
| 5 | Never give the application's DB roles `BYPASSRLS` or superuser rights, or disable RLS on a business table | ❌ "Temporarily" turning off RLS to fix a report |
| 6 | Never cache, store or name files without the tenant prefix | ❌ Cache key `invoice:123` |
| 7 | Never publish or process an event without a valid `tenant_id` | ❌ An event with `tenant_id: null` |
| 8 | Never reveal that another tenant's record exists | ❌ Returning `403 Forbidden` for another tenant's ID. **Return `404 Not Found`**, exactly as if it didn't exist |
| 9 | Never give staff or support silent cross-tenant access | ❌ A developer querying production for "one customer". Only **audited, time-limited support access**, approved per case and logged in Platform audit |
| 10 | Never combine data across tenants in product features | ❌ "Compare your payroll with other companies" built from raw tenant data |

#### The only cross-tenant access allowed

- **Platform administration** (create or suspend a tenant, billing status) through
  explicitly marked Platform admin operations. They use a separate, audited admin
  role, and only touch `platform` tables.
- **Internal analytics** using **aggregated, anonymised** data only, through a separate
  approved pipeline, never through the application's DB roles.

Anything else needs a new ADR.

### 5. Dedicated tenants

#### Who qualifies

A customer can move to a dedicated deployment when their **enterprise contract** requires
at least one of:

- **data residency** in a specific country or region;
- contractual or compliance requirements for **physically separate** infrastructure
  or backups;
- **size or load** that would hurt shared tenants (the thresholds will be set during
  sizing in ADR-0011);
- their own **maintenance windows**, retention or backup schedule.

The decision is commercial and needs an architecture review (ADR-0010). It is not a
developer's choice.

#### What a dedicated deployment contains

A **complete copy of the stack**: the application (Platform + Billing + HRMS modules),
PostgreSQL, RabbitMQ, storage and monitoring. It is deployed from the **same release
artifact** and configured through environment settings only.

#### Rules

1. **Same code, same version.** A dedicated deployment may lag the shared deployment by
   **at most one release**, and never runs a custom build.
2. **Same migrations**, run by the same tooling.
3. **Same isolation rules.** `tenant_id` columns, RLS and tenant context stay switched on,
   even though there is only one tenant.
4. **Configuration only.** The differences are limited to settings such as the DB
   connection, domain, region, SSO provider, backup schedule and feature flags from
   entitlements.
5. **Routing:** the Platform tenant directory records which deployment each tenant lives
   on, e.g. `acme.app.com → dedicated deployment "acme-prod"`.

#### Moving a tenant from shared to dedicated

This is possible because every row carries `tenant_id` and all IDs are globally unique
UUIDs:

1. Put the tenant into read-only / maintenance mode.
2. Export all of the tenant's rows from every module schema (`WHERE tenant_id = X`), plus
   the tenant's files.
3. Import them into the new dedicated database. There are no ID clashes, because the
   IDs are UUIDs.
4. Verify row counts and checksums, and switch routing in the tenant directory.
5. After the retention period, delete the tenant's rows from the shared database.

The migration tool will be built when the first dedicated customer is signed. It is
**not** in M0 or M1 scope.

### 6. How we prove it (tests and checks)

| Check | Type | Fails the build when… |
|-------|------|------------------------|
| **Schema lint** on every migration | CI | A business table has no `tenant_id NOT NULL`, no RLS, no `FORCE RLS`, or no tenant policy |
| **Role check** | CI / deploy | An app DB role has `BYPASSRLS` or superuser, or owns business tables |
| **Fail-closed test** | Integration | A query without `app.tenant_id` returns anything other than zero rows |
| **Cross-tenant test suite** | Integration | For **every** API endpoint: create data in Tenant B, call as Tenant A, and expect `404` / empty results / rejected writes |
| **Event tenant test** | Integration | An event consumer processes an event under the wrong tenant, or accepts one without `tenant_id` |
| **Cache/file key test** | Unit | A cache key or file path is built without the tenant prefix |

Details go in ADR-0009. The cross-tenant suite is **mandatory for every new endpoint**.
This is also checked in ADR-0010.

## Options considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **A. Shared DB, `tenant_id` column + RLS** | One DB to run, cheapest, simple migrations, scales to many small tenants | Isolation depends on discipline, so it needs the 4 layers; per-tenant restore is harder | **Chosen as the default** |
| B. Schema per tenant | Stronger separation | Migrations run N times; thousands of schemas slow PostgreSQL down; clashes with our schema-per-module design | Rejected |
| C. Database per tenant for everyone | Strongest separation, easy per-tenant restore | Expensive, heavy operations on one server, N migrations | Rejected as the default, **used for dedicated tenants only** |
| D. `tenant_id` column only, no RLS | Simplest | One missing `WHERE` leaks data; there's no safety net | Rejected |

We chose **A for shared tenants plus C-style dedicated deployments for enterprises**,
running identical code.

## Consequences

- **Positive**
  - Four independent layers: a single bug can't leak data on its own.
  - Fail-closed: forgetting the tenant context returns nothing, not everything.
  - Enterprise customers can get physical separation without a second codebase.
  - Moving a tenant out later is a data export, not a redesign.
- **Negative / trade-offs**
  - Every table, index, FK and query carries `tenant_id`, which adds some verbosity.
  - RLS adds a small query overhead and needs care with connection pooling (`SET LOCAL`
    per transaction).
  - Restoring a single shared tenant from backup needs export/import tooling.
  - Every dedicated deployment adds operations work (upgrades, monitoring, backups).
- **Follow-ups**
  - ADR-0008: data-access layer that sets `app.tenant_id` and adds tenant filters; the
    migration lint tool.
  - ADR-0009: the cross-tenant test suite and fail-closed tests.
  - ADR-0010: add isolation checks to the review checklist.
  - ADR-0011: PostgreSQL hosting, backups, and size thresholds for dedicated tenants.
  - Open question, to be decided **before the first dedicated customer**: does a
    dedicated deployment manage its own entitlements and SaaS subscription, or sync them
    from the central Platform (a "control plane")?

## References

- ADR-0001 Product Separation
- ADR-0002 Service Boundaries
- ADR-0003 Module Contracts
- ADR-0004 Event Taxonomy
- ADR-0005 Event Broker
- ADR-0011 Cloud Platform (A-016)
