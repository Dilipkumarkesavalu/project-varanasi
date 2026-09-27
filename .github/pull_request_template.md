<!--
PR title must be a Conventional Commit, e.g. `feat(billing): add invoice creation`
(it becomes the squash-merge commit — ADR-0008).

Answer EVERY checklist item: tick it, or replace the box line with `N/A: <reason>`.
Empty boxes or N/A without a reason = not ready for review.
🔴 = blocker. Full guidance: docs/adr/0010-architecture-review-checklist.md
-->

## What
<!-- One or two sentences. -->

## Why
<!-- Problem / task. Refs: M0-ARC-010 or ticket ID -->

## How to test
<!-- Steps or test names. -->

## Architecture review needed?
<!-- Yes if this touches contract/, events, shared/, new tables/RLS/roles, new dependency, deploy/, or an ADR (ADR-0010 §4). -->
- [ ] Yes, architecture reviewer requested
- [ ] No

---

## Architecture review checklist (ADR-0010)

### A. Tenant isolation 🔴
- [ ] A1 Every business query enforces tenant isolation (tenant-aware session, RLS on, no bypass)
- [ ] A2 `tenant_id` comes only from the token/tenant context, never from client input
- [ ] A3 New tables have `tenant_id NOT NULL`, forced RLS, `tenant_isolation` policy, composite tenant FKs
- [ ] A4 Cache keys, file paths, jobs and exports carry the tenant
- [ ] A5 Another tenant's resource returns `404`

### B. Authorization 🔴
- [ ] B1 Authorization is checked on every new/changed endpoint, action and contract operation (`x-permission` set)
- [ ] B2 New permissions follow `<module>.<resource>.<action>` and are registered
- [ ] B3 Entitlement checked for product features; suspension checked for writes
- [ ] B4 Sensitive fields are hidden without `*.read_sensitive`

### C. Module boundaries 🔴
- [ ] C1 I did **not** access another module's database directly (no cross-schema SQL/ORM, no `internal/` imports)
- [ ] C2 Cross-module interactions use the right mechanism (API for answers now, event for facts; Platform → others = events only)
- [ ] C3 Every new business concept has exactly one owner (ADR-0002 updated)
- [ ] C4 Contract changes are backward-compatible or versioned
- [ ] C5 `shared/` contains no business logic

### D. Events & messaging 🔴
- [ ] D1 Events are emitted only through the approved mechanism (module outbox → RabbitMQ)
- [ ] D2 Outbox is used: event written in the same transaction as the DB change
- [ ] D3 New events are named correctly, have a JSON Schema and a row in the ADR-0004 catalogue
- [ ] D4 Event payloads contain no sensitive data
- [ ] D5 New consumers are idempotent, tenant-scoped, classify errors (retry vs DLQ), queue defined as code

### E. API standards 🔴
- [ ] E1 Paths, methods, status codes, Problem Details errors, pagination, filtering, sorting follow ADR-0007
- [ ] E2 Creating `POST`s require `Idempotency-Key`; `PATCH`/actions require `If-Match`
- [ ] E3 `docs/api/openapi.json` regenerated; no unintended breaking change

### F. Observability 🔴
- [ ] F1 Every request/job/consumer has a correlation ID, propagated to logs, contract calls and events
- [ ] F2 Logs are structured and contain no secrets, tokens, full bodies or sensitive personal data
- [ ] F3 New failure modes are logged at the right level (alert + runbook if operators must act)

### G. Audit 🔴
- [ ] G1 Sensitive actions (ADR-0010 §2) are audited via `AuditApi`, atomically with the change
- [ ] G2 Audit entries record who/what/when/tenant/correlation ID, without sensitive values

### H. Data & migrations 🔴
- [ ] H1 Migrations follow naming, touch only this module's schema, are safe on large tables
- [ ] H2 Money = `Decimal`/`numeric(19,4)` + currency; times UTC; IDs UUIDv7
- [ ] H3 Financial/legal records are voided/reversed, never deleted

### I. Tests 🔴
- [ ] I1 Required tests included (unit, integration, cross-tenant for every new/changed endpoint, contract, migration if DB changed)
- [ ] I2 Tests assert real behaviour, including failure paths
- [ ] I3 No tests deleted/skipped/weakened; no new `type: ignore`/`noqa`/coverage exclusions without a written reason
- [ ] I4 E2E run if this change is on the ADR-0009 §4 trigger list

### J. ADR compliance 🔴
- [ ] J1 This change does **not** violate any ADR (esp. frozen: 0003, 0005, 0006, 0011)
- [ ] J2 Any new hard-to-reverse or cross-module decision has an ADR (in this PR or linked)
- [ ] J3 Docs updated in this PR (module README, event catalogue, runbooks, OpenAPI)

### K. AI-assisted changes
- [ ] K1 AI was used for a meaningful part of this PR: **Yes / No** (delete one)
- [ ] K2 I have read and understood every line and can explain it
- [ ] K3 All libraries, functions, config options and flags used exist in our locked versions
- [ ] K4 Diff checked against the red-flag list (ADR-0010 §3)
- [ ] K5 No secrets, customer data or production data were pasted into an AI tool
