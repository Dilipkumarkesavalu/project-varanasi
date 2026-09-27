# ADR-0002: Service Boundaries

- **Status:** Accepted (M0 approval, 2026-09-27)
- **Date:** 2026-09-27
- **Milestone:** M0
- **Task:** M0-ARC-002
- **Deciders:** Project owner (see `docs/architecture/M0-APPROVAL.md`)
- **Depends on:** ADR-0001 Product Separation
- **Supersedes / Superseded by:** —

## Context

ADR-0001 splits the system into three products (Platform, Billing, HRMS). All three are
delivered as **modules of one modular application on a dedicated server**.

Inside a single app, it's easy for modules to reach into each other's data. Before
anyone writes code, we need an explicit list of who owns every business concept, so that
there is no confusion about where data lives and who may change it.

## Decision

### The core rule

> **Every business concept has exactly one owner.**

The owning module is the only one that:

- stores the concept in its own database schema;
- creates, changes or deletes it;
- defines its business rules and validation;
- publishes its public interface and its events.

Every other module is a **consumer**. It reads the concept through the owner's public
interface, or reacts to the owner's events. It never touches the owner's tables.

### Ownership table

| Concept | Owner | What it means here | How other modules use it |
|---------|-------|--------------------|--------------------------|
| **Users** | Platform | A person who can sign in | Store `user_id` only; fetch profile through the Platform interface |
| **Authentication** | Platform | Login, sessions, tokens, SSO, MFA, password reset | Validate the token/claims Platform issues; never handle credentials |
| **Tenants** | Platform | A customer organization and its lifecycle (create, suspend, close) | Every record carries `tenant_id`; tenant status comes from Platform |
| **Roles** | Platform | Named bundles of permissions assigned to users | Read the user's roles from token claims or the Platform interface |
| **Permissions** | Platform | The catalogue of allowed actions | Each module **registers** its permissions with Platform and **enforces** them on its own resources |
| **Audit** | Platform | The immutable log of who did what, when | Modules **emit** audit events; only Platform stores and queries them |
| **Entitlements** | Platform | Which products and features a tenant has paid for (plans and subscriptions, per ADR-0001) | Modules **ask** Platform before allowing a feature; they never hard-code plan logic |
| **Invoices** | Billing | Invoices a tenant raises to *its own* customers | Other modules use Billing's interface or events only |
| **Payments** | Billing | Payments a tenant receives from *its own* customers against those invoices | Same as above |
| **Employees** | HRMS | A person employed by the tenant | May link to a Platform `user_id` if the employee can sign in |
| **Attendance** | HRMS | Check-in/out, shifts, timesheets | Used by HRMS Leave and Payroll internally |
| **Leave** | HRMS | Leave types, balances, requests, approvals | Approvers are resolved through Platform users and roles |
| **Payroll** | HRMS | Salary structures, pay runs, payslips, statutory deductions | Uses HRMS Attendance and Leave internally |

### Easy-to-confuse concepts

These look similar but have **different owners**. Keep them apart:

| Looks like… | …but is actually | Owner |
|-------------|------------------|-------|
| A **User** | An **Employee** (HR record) | HRMS. An employee may have no login; a user may not be an employee. |
| A **Tenant** | A **Billing customer** (someone the tenant invoices) | Billing |
| **Payments** in Billing | **Our SaaS subscription payments** (tenants paying us) | Platform, collected through an external provider (ADR-0001) |
| **Payroll** payouts | Money going *out* to employees | HRMS. This is not a Billing payment. |
| **Permissions** | **Entitlements** | Both are Platform, but they answer different questions. Permissions ask "may this *user* do this?" Entitlements ask "has this *tenant* paid for this?" |

### Adding new concepts

When a new business concept appears:

1. Assign it **one** owner before any code is written.
2. Add it to the ownership table in this ADR.
3. If two modules both seem to need to own it, split it into two concepts with clear
   names (as with User vs. Employee) or pick one owner and expose it to the other.

### How modules map to the code

Since this is one modular app, each owner is a top-level module:

```
src/varanasi/
├── platform/   # users, auth, tenants, roles, permissions, audit, entitlements
├── billing/    # invoices, payments (tenant's customers)
└── hrms/       # employees, attendance, leave, payroll
```

- Each module has its **own database schema** (for example `platform.*`, `billing.*`,
  `hrms.*`).
- Each module exposes a **public interface** package. Everything else in it is
  internal.
- **No module directly reads or writes another module's tables.** Modules communicate
  only through an **API** or an **Event** (frozen in ADR-0003).
- Allowed dependencies:
  - `billing → platform` and `hrms → platform`: API and events.
  - `platform → billing/hrms`: events only, never API calls.
  - `billing ↔ hrms`: only through the other's contract (API or event), and it must
    still work when the other product isn't enabled for the tenant.

## Options considered

1. **Shared ownership, where any module can write any table.** Quick at first, but rules
   end up spread across modules and nobody is accountable for the data. *Rejected.*
2. **Ownership by team or convention only, with no table.** Easy to drift, and gets
   argued over each time a feature is built. *Rejected.*
3. **One owner per concept, recorded in a table and enforced in code (chosen).**

## Consequences

- **Positive**
  - There is always one place to look when asking "where does this live and who can
    change it?"
  - Boundaries line up with database schemas and code packages, so they can be checked
    automatically.
  - Any module can later be pulled out into its own service with little rework.
- **Negative / trade-offs**
  - A feature that crosses modules has to go through interfaces or events instead of a
    direct query or join.
  - Some data will be copied between modules for reading (for example, a user's name
    shown on a payslip). Each copy must be treated as read-only and kept up to date from
    events.
- **Follow-ups**
  - ADR-0003: define each module's public interface and how boundaries are enforced.
  - ADR-0004: define the events each owner publishes.
  - ADR-0006: define how `tenant_id` is enforced in every schema.
  - ADR-0008: add architecture tests that fail CI when a module crosses a boundary.

## References

- ADR-0001 Product Separation
- ADR-0003 Module Contracts
- ADR-0004 Event Taxonomy
- ADR-0006 Tenant Isolation
