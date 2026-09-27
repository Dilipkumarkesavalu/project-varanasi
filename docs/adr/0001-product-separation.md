# ADR-0001: Product Separation

- **Status:** Accepted (M0 approval, 2026-09-27)
- **Date:** 2026-09-27
- **Milestone:** M0
- **Task:** M0-ARC-001
- **Deciders:** Project owner (see `docs/architecture/M0-APPROVAL.md`)
- **Supersedes / Superseded by:** —

## Context

We are building two business products, **Billing** and **HRMS**. They serve the same
customers (tenants) and the same users. They also need the same basics: sign-in, tenant
management, roles, audit and feature entitlements.

If each product built these on its own, we would get duplicate user accounts, tenant
models that drift apart, and permissions that don't match. If we built one monolith, the
products would be tied together at the data and release level, and they could not be
sold, scaled or developed independently.

We need a clear ownership model before we define service boundaries (ADR-0002),
contracts (ADR-0003), events (ADR-0004) and tenant isolation (ADR-0006).

## Decision

We will structure the system as **three separately owned products**. They are delivered
as modules of one modular application on a dedicated server (see resolved question 2):

| Product | Owns | Examples |
|---------|------|----------|
| **Platform** | Identity, tenants, roles, audit, entitlements | Users, authentication/SSO, tenant (organization) lifecycle, roles & permissions, audit log, feature/plan entitlements |
| **Billing** | Billing-specific business logic and data | Customers, products/price lists, invoices, payments, credit notes, taxes, billing reports |
| **HRMS** | HR-specific business logic and data | Employees, org structure, attendance, leave, payroll inputs, HR documents, HR reports |

Billing and HRMS are **separate applications/modules**. They share:

- **Identity:** a single Platform-issued identity and tenant context
- **Cloud infrastructure:** the same cloud platform and baseline services (ADR-0011 / A-016)
- **Contracts:** versioned APIs and events (ADR-0003, ADR-0004, ADR-0007)

Each product has **clear ownership boundaries** over its own code, data and domain logic.

### Boundary rules

1. **Single owner per data.** Each piece of data has exactly one owning product. Other
   products never read from or write to its database directly.
2. **Communication only through contracts.** Products talk to each other through published
   APIs and events only. There are no shared tables, shared schemas or shared domain
   libraries.
3. **Platform is the only source of identity and tenancy.** Billing and HRMS do not store
   credentials or define their own tenant or user models. They refer to Platform's
   `tenant_id` and `user_id`.
4. **Authorization is defined in Platform and enforced in each product.** Platform owns
   the role and permission model and issues tokens/claims. Each product enforces them for
   its own resources.
5. **Audit goes through Platform.** Products emit audit events in the Platform audit format
   and do not keep separate audit stores.
6. **Entitlements are checked through Platform.** Products ask Platform whether a tenant
   is entitled to a feature. They do not hard-code plan logic.
7. **Billing and HRMS do not depend on each other.** Neither may require the other to be
   deployed or running. Any integration between them goes through events or contracts and
   must degrade gracefully.
8. **Shared code is limited to generic technical libraries** (logging, auth middleware,
   contract clients). Business or domain logic is never shared.

### Ownership clarifications

| Concept | Owner | Notes |
|---------|-------|-------|
| User (login identity) | Platform | Profile basics and credentials |
| Employee | HRMS | Refers to Platform `user_id` if the employee can sign in; may exist without one |
| Tenant / organization | Platform | Products keep product-specific tenant settings in their own stores |
| Billing customer | Billing | Not the same as a tenant or user |
| Roles & permissions | Platform | Products register their permission sets with Platform |
| Plans, tenant subscriptions → entitlements | Platform | Payments go through an external provider; see resolved question 1 |
| Audit log | Platform | Products are producers only |

## Options considered

1. **One monolithic application with shared database.** Fastest to start. However,
   Billing and HRMS become tightly coupled, it becomes hard to sell either product on its
   own, and one team's changes can block the other's releases. *Rejected.*
2. **Fully independent products, each with its own identity and tenancy.** Gives maximum
   autonomy. However, it duplicates identity, tenant and role logic, forces users to keep
   multiple accounts, and makes cross-product SSO and entitlements hard. *Rejected.*
3. **Separate products on a shared Platform (chosen).** Each product owns its own domain,
   while identity, tenancy, roles, audit and entitlements are centralized. It also keeps
   the option open to sell Billing and HRMS separately or together.

## Consequences

- **Positive**
  - Billing and HRMS can be developed independently now, and extracted into their own
    services later if needed.
  - One deployable on one server keeps operations simple and cost low in the early
    stages.
  - Users get one login and consistent roles and audit across products.
  - New products can be added on top of Platform without redoing the foundations.
- **Negative / trade-offs**
  - Platform becomes a critical dependency. It needs high availability and careful
    versioning.
  - Anything that crosses products needs contracts and events instead of joins, which
    means more upfront design and eventual consistency.
  - Reporting across products needs a separate read model or analytics pipeline.
  - Because everything is one deployable, all modules are released together and scale
    together. A bug in one module can take down the whole app.
  - Running a single dedicated server is a single point of failure. Backups, monitoring
    and a restore plan are required (see ADR-0011).
  - We depend on an external payment provider, and its webhooks must be verified and
    handled idempotently.
- **Follow-ups**
  - ADR-0002: map each product to services and bounded contexts.
  - ADR-0003 / ADR-0007: define the Platform contracts (identity, tenant, roles,
    entitlements, audit).
  - ADR-0004: define the audit event and cross-product event formats.
  - ADR-0006: define how `tenant_id` from Platform is enforced in each product.

## Resolved questions

1. **Who charges tenants for using our products (SaaS subscriptions)?**
   There are two kinds of billing, and they must not be confused:
   - The **Billing product** is what tenants use to invoice *their own* customers.
   - **SaaS subscription billing** is how *we* charge tenants for their plan.

   **Decision:**
   - **Platform** owns plans, tenant subscriptions and the entitlements that follow from
     them (which products and features a tenant can use).
   - **Payment collection** (recurring charges, payment methods, receipts) goes through an
     **external subscription/payment provider**, e.g. Razorpay Subscriptions, Stripe
     Billing or Chargebee. The provider is chosen separately.
   - The provider notifies Platform of payment outcomes through webhooks. Platform then
     turns entitlements on, suspends them or turns them off.
   - The **Billing product is not used** for our own SaaS invoicing. Platform never depends
     on Billing, which keeps boundary rule 7 intact.

2. **What is the deployment unit?**
   **Decision:** We will run **one modular application (a modular monolith)** on a
   **dedicated server**.
   - Platform, Billing and HRMS are **modules inside a single deployable**. They are not
     separate services.
   - The boundary rules above still apply *inside* the app:
     - each module has its own code package and its own database schema;
     - modules call each other only through their public module interfaces or in-process
       events;
     - no module queries another module's tables.
   - Module boundaries are enforced by tooling (architecture/lint tests in CI), not just
     by convention. Details go in ADR-0003 and ADR-0008.
   - Because the modules are this cleanly separated, we can later extract one into its own
     service without redesigning it.
   - The server and hosting details are recorded in ADR-0011 (A-016).

## References

- ADR-0002 Service Boundaries
- ADR-0003 Module Contracts
- ADR-0006 Tenant Isolation
- ADR-0011 Cloud Platform (A-016)
