# ADR-0003: Module Contracts

- **Status:** Accepted (M0 approval, 2026-09-27). **The core rule in section 0 is FROZEN.**
- **Date:** 2026-09-27
- **Milestone:** M0
- **Task:** M0-ARC-003
- **Deciders:** Project owner (see `docs/architecture/M0-APPROVAL.md`)
- **Depends on:** ADR-0001 Product Separation, ADR-0002 Service Boundaries
- **Supersedes / Superseded by:** —

## Context

ADR-0002 gives every business concept one owner, and says other modules may only use it
"through the owner's public interface or events". This ADR defines what that
public interface (the **contract**) looks like, how it may change, and how we stop
modules from going around it.

Because the system is **one modular application** (ADR-0001), modules call each other
in-process. That makes it very easy to import an internal class or query another
module's table. Contracts only work if they are explicit and checked by tooling.

## Decision

### 0. The core rule (FROZEN)

> **No module directly reads or writes another module's tables.**
>
> Modules communicate **only** through:
>
> - an **API**: a synchronous call to the owner's public contract interface; or
> - an **Event**: a message the owner publishes, which others react to.

Example:

```
Billing ❌ → SELECT * FROM hrms.employee        (direct table access)
Billing ❌ → import hrms.internal.EmployeeRepository   (going around the contract)

Billing ✅ → hrms.contract.EmployeeApi.getEmployee(tenantId, employeeId)   (API)
Billing ✅ → subscribes to hrms.employee.created.v1                       (Event)
```

This covers **every** way of touching data: SQL queries, ORM entities, database views,
joins across schemas, shared tables, stored procedures and reporting queries. There are
no exceptions for "read-only" or "just this one report".

**Frozen** means this rule cannot be changed or bypassed without a new ADR that
supersedes this one and an architecture review (ADR-0010).

### 1. What a contract is

Each module (`platform`, `billing`, `hrms`) has exactly **one public contract
package**. It contains only:

| Part | Purpose | Example |
|------|---------|---------|
| **Interfaces (facades)** | Synchronous operations other modules may call | `EntitlementApi.isEnabled(tenantId, feature)` |
| **DTOs** | Plain data passed in and out. Immutable, with no behavior and no ORM annotations | `UserSummary { userId, displayName, email }` |
| **Event definitions** | Events the module publishes (format defined in ADR-0004) | `hrms.employee.created.v1` |
| **Errors** | Typed errors the interfaces may return | `TenantSuspended`, `NotEntitled`, `NotFound` |

Everything else in a module (entities, repositories, services, tables) is
**internal** and must not be used from outside.

```
src/varanasi/
├── platform/
│   ├── contract/     # public: interfaces, DTOs, events, errors
│   └── internal/     # private: domain, persistence, services
├── billing/
│   ├── contract/
│   └── internal/
└── hrms/
    ├── contract/
    └── internal/
```

### 2. Contract rules

1. **Only the owner defines and changes a contract.** Consumers can ask for changes but
   do not edit it.
2. **Pass DTOs, never entities.** Internal database objects never cross a module
   boundary.
3. **Refer to other modules' data by ID.** Store `user_id` or `tenant_id`, not a copy
   of the object. If you need a copy for reading, treat it as read-only and refresh it
   from events.
4. **Every call carries the tenant context.** Each contract operation takes `tenantId`,
   either explicitly or through a request context (ADR-0006). No operation may work
   across tenants unless it is a Platform admin operation that is explicitly marked as
   one.
5. **No transactions across modules.** A single database transaction must not span two
   modules' schemas. For cross-module workflows, use events with the outbox pattern
   (ADR-0005).
6. **Contract calls must stay cheap and safe.** Every call must be idempotent where it
   can be, and must not quietly trigger long-running work in the other module.
7. **Dependency direction** (from ADR-0002):
   - `billing → platform` and `hrms → platform`: allowed, API and events.
   - `platform → billing/hrms`: **no API calls**. Platform only publishes events;
     Billing and HRMS react to them.
   - `billing ↔ hrms`: allowed **only through the other's contract (API or event)**, and
     the caller **must degrade gracefully** if the other product is not enabled for the
     tenant (ADR-0001 rule 7). A tenant may buy Billing without HRMS, or HRMS without
     Billing. Prefer events here.

### 3. Sync call or event?

| Use a **synchronous interface call** when… | Use an **event** when… |
|--------------------------------------------|------------------------|
| You need an answer right now to continue | You are announcing that something happened |
| It is a query or a check (e.g. "is this feature enabled?") | Other modules may react, but you don't need to wait for them |
| The caller depends on the callee (allowed direction) | The dependency would otherwise go the wrong way (e.g. Platform → HRMS) |

Example: HRMS **calls** `AuthorizationApi.check(...)` before approving leave. Platform
**publishes** `platform.tenant.suspended.v1`, and HRMS **reacts** by blocking new pay
runs.

### 4. Initial contracts

These are the starting contracts. Their exact method signatures will be written in code
during M1.

**Platform (used by everyone)**

| Contract | Key operations | Key events |
|----------|----------------|------------|
| `IdentityApi` | get user, get users by IDs, resolve the current user from a token | `platform.user.created`, `platform.user.deactivated` |
| `TenantApi` | get tenant, get tenant status | `platform.tenant.created`, `platform.tenant.suspended`, `platform.tenant.closed` |
| `AuthorizationApi` | check a permission, list a user's roles, **register a module's permissions** | `platform.role.assigned`, `platform.role.revoked` |
| `EntitlementApi` | is a feature enabled, get limits (e.g. employee count) | `platform.entitlement.changed` |
| `AuditApi` | Defines the audit entry format. `audit.record(...)` writes the entry to the **calling module's own outbox**, in the caller's transaction. Platform consumes it and stores it. (A direct write to Platform's tables would be a cross-module transaction and break rule 5.) Querying audit is Platform-only | `<module>.audit_entry.recorded.v1` (ADR-0004 §7) |

**Billing (no other module depends on it yet)**

| Contract | Key operations | Key events |
|----------|----------------|------------|
| `InvoiceApi` | get invoice, list invoices by customer | `billing.invoice.issued`, `billing.invoice.voided` |
| `PaymentApi` | get payment | `billing.payment.received` |

**HRMS (no other module depends on it yet)**

| Contract | Key operations | Key events |
|----------|----------------|------------|
| `EmployeeApi` | get employee, find employee by `user_id` | `hrms.employee.created`, `hrms.employee.updated`, `hrms.employee.terminated` |
| `LeaveApi` | get leave balance | `hrms.leave.approved` |
| `PayrollApi` | get pay run status | `hrms.payrun.completed` |

The Billing and HRMS contracts should be kept **small**. Only expose an operation once a
real consumer needs it.

### 5. Changing a contract

Even inside one app, treat contracts as if other teams depend on them:

| Change | Allowed? | How |
|--------|----------|-----|
| Add a new operation, event or optional field | Yes | Normal review |
| Rename or remove anything, change a field's type or meaning, make an optional field required | **Breaking** | Add the new version next to the old one, move all consumers over, then remove the old version. Record it in the changelog. |
| Change an event's format | **Breaking** | Publish a new event version (e.g. `.v2`) alongside `.v1` (ADR-0004) |

Every change to a `contract/` package needs a review from the owning module
(`CODEOWNERS`) and is checked with the ADR-0010 checklist.

### 6. Enforcement

Rules that aren't checked get broken. We will enforce them automatically in CI:

- **Architecture tests** with **import-linter** (configuration in ADR-0008 §3) that fail
  the build when:
  - code imports another module's `internal/` package;
  - `billing` imports anything from `hrms` except `hrms/contract`, or the reverse;
  - `platform` imports anything from `billing` or `hrms` other than their event
    definitions.
- **Database permissions:** this is the hard guarantee for the frozen rule. Each module
  connects with its own DB role, and that role can only access its own schema, so a
  query against another module's tables **fails at the database** (ADR-0006).
- **SQL/migration review:** migrations and raw SQL that mention another module's schema
  fail CI.
- **Contract tests** check that each contract works the way consumers expect
  (ADR-0009).

## Options considered

1. **No formal contracts, where modules call each other's services freely.** Fastest to
   start, but the modular monolith quickly turns into an ordinary tangled monolith.
   *Rejected.*
2. **Internal HTTP/REST APIs between modules in the same process.** This gives strong
   isolation, but adds network overhead, serialization and failure modes with no benefit
   while everything runs in one app. *Rejected for now.* This is the path to take if a
   module is later split out.
3. **In-process contract packages with typed interfaces, DTOs and events, enforced by
   tooling (chosen).** Fast and simple, and it maps directly onto HTTP APIs or a message
   broker if a module is extracted later.

## Consequences

- **Positive**
  - Clear, reviewable edges between modules. Each module's internals can change freely.
  - Any module can be extracted into its own service later by putting HTTP or a message
    broker behind the same contract.
  - Boundary violations are caught in CI, not in production.
- **Negative / trade-offs**
  - More code: DTOs and mapping in both directions.
  - Cross-module workflows are eventually consistent instead of running in a single
    transaction.
  - Contract changes need discipline even when the change looks small.
- **Follow-ups**
  - ADR-0004: event naming, format and versioning.
  - ADR-0005: in-process event bus and outbox.
  - ADR-0006: tenant context propagation and per-module DB roles.
  - ADR-0008: pick the architecture-test tool for the chosen stack.
  - ADR-0009: contract test approach.

## References

- ADR-0001 Product Separation
- ADR-0002 Service Boundaries
- ADR-0004 Event Taxonomy
- ADR-0005 Event Broker
- ADR-0006 Tenant Isolation
