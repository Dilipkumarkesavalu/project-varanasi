# M0 Approval Record

**Project:** Varanasi (Platform · Billing · HRMS)
**Milestone:** M0 — Architecture foundation
**Quality gate:** QG-01
**Date:** 2026-09-27

---

```
M0 STATUS: APPROVED

Architecture decisions:    APPROVED
Service boundaries:        APPROVED
Event architecture:        APPROVED
Tenant model:              APPROVED
API standards:             APPROVED
Coding conventions:        APPROVED
Testing strategy:          APPROVED
PR architecture checklist: APPROVED
Cloud provider + region:   FROZEN   (AWS · ap-south-1 Mumbai · DR ap-south-2 Hyderabad)

Open architectural contradictions: NONE

QG-01: PASSED
```

---

## 1. Decisions approved

| Task | ADR | Decision in one line | Status |
|------|-----|----------------------|--------|
| M0-ARC-001 | [0001 Product Separation](../adr/0001-product-separation.md) | Platform (identity, tenants, roles, audit, entitlements), Billing and HRMS are separately owned modules of **one modular app on a dedicated server**. SaaS subscriptions: Platform + external payment provider | APPROVED |
| M0-ARC-002 | [0002 Service Boundaries](../adr/0002-service-boundaries.md) | **Every business concept has exactly one owner** (ownership table) | APPROVED |
| M0-ARC-003 | [0003 Module Contracts](../adr/0003-module-contracts.md) | **No module reads or writes another module's tables. API or Event only** | APPROVED · rule **FROZEN** |
| M0-ARC-004 | [0004 Event Taxonomy](../adr/0004-event-taxonomy.md) | `<module>.<entity>.<past-tense>.v<N>`, a standard 8-field envelope, and an event catalogue | APPROVED |
| M0-ARC-005 | [0005 Event Broker](../adr/0005-event-broker.md) | **RabbitMQ** + transactional outbox, retries with backoff, DLQ | APPROVED · **FROZEN** |
| M0-ARC-006 | [0006 Tenant Isolation](../adr/0006-tenant-isolation.md) | Shared PostgreSQL + `tenant_id` + forced RLS (4 layers). Dedicated deployments for enterprise, same code | APPROVED · **FROZEN** |
| M0-ARC-007 | [0007 API Standards](../adr/0007-api-standards.md) | REST `/api/v1`, Problem Details, cursor pagination, Idempotency-Key, correlation ID, JWT + permissions | APPROVED |
| M0-ARC-008 | [0008 Coding & Repo Conventions](../adr/0008-coding-repo-conventions.md) | Python 3.13 / FastAPI / SQLAlchemy / uv. Monorepo layout, naming, Conventional Commits, trunk-based | APPROVED |
| M0-ARC-009 | [0009 Testing Strategy](../adr/0009-testing-strategy.md) | Unit / integration / contract / security required on every PR. Migration and E2E conditional. A command defined for each | APPROVED |
| M0-ARC-010 | [0010 Architecture Review Checklist](../adr/0010-architecture-review-checklist.md) | A 42-item checklist (incl. AI-assisted changes) in the [PR template](../../.github/pull_request_template.md) | APPROVED |
| **A-016** | [0011 Cloud Platform](../adr/0011-cloud-platform.md) | **AWS, `ap-south-1` (Mumbai)**, DR/backups in `ap-south-2` (Hyderabad). All data stays in India | **FROZEN** |

## 2. Frozen decisions

Changing any of these needs a **superseding ADR + architecture review** (ADR-0010 §4):

1. **ADR-0003 §0:** no direct access to another module's tables. API or Event only.
2. **ADR-0005:** event broker = RabbitMQ, with the outbox.
3. **ADR-0006:** tenant model (shared DB + `tenant_id` + forced RLS; dedicated = same code).
4. **ADR-0011 / A-016:** cloud = AWS, primary region = `ap-south-1` Mumbai.

## 3. Contradiction review

All eleven ADRs were cross-checked before approval. The contradictions found were
**resolved in the ADRs themselves** before sign-off:

| # | Contradiction found | Resolution |
|---|---------------------|------------|
| 1 | ADR-0002/0003 banned Billing ↔ HRMS calls, but ADR-0001 and M0-ARC-003 allowed them through contracts | Aligned: allowed **only** through the other's contract (API/event), and must still work when the other product isn't enabled. Platform → others is events only |
| 2 | ADR-0003 named the event `hrms.employee.exited`; ADR-0004 uses `terminated` | Renamed to `hrms.employee.terminated` |
| 3 | ADR-0003 had `AuditApi` writing into Platform's tables, which is a cross-module transaction (breaks ADR-0003 rule 5), while ADR-0010 requires audit to be atomic with the change | Audit entries are written to the **calling module's own outbox** as `<module>.audit_entry.recorded.v1`. Platform consumes and stores them (ADR-0003, ADR-0004 §7, ADR-0010 G1) |
| 4 | ADR-0005 requires one RabbitMQ user per module; ADR-0008 defined a single broker URL | ADR-0008 now defines `VARANASI_RABBITMQ_{PLATFORM,BILLING,HRMS}_URL` |
| 5 | ADR-0002/0003 showed code under `app/`; ADR-0008 uses `src/varanasi/` | Unified on `src/varanasi/` |
| 6 | ADR-0003 left the architecture-test tool open; ADR-0008 chose import-linter | ADR-0003 now references import-linter (ADR-0008 §3) |
| 7 | ADR-0005 assumed the database lived on the app server's disk; ADR-0011 puts it on RDS | ADR-0005's failure table updated: losing the server loses no data, and messages are replayed from the outbox |
| 8 | ADR-0008's PR template duplicated and differed from the ADR-0010 checklist | ADR-0008 now points to the single template in `.github/pull_request_template.md` |

**Result: open architectural contradictions: NONE.**

## 4. Known open items (not contradictions, not blocking M0)

These are **deliberately deferred**, each with a clear trigger. None of them conflicts
with an approved decision.

| Item | Decide by | Source |
|------|-----------|--------|
| Which external payment provider (Razorpay / Stripe / Chargebee) | Before SaaS billing goes live | ADR-0001 |
| Dedicated tenants: local entitlements vs a central control plane | Before the first dedicated customer | ADR-0006 |
| Size thresholds for moving a tenant to a dedicated deployment | Before the first enterprise contract | ADR-0006, ADR-0011 |
| Rate-limit numbers | M1, after load testing | ADR-0007 |
| Real domain for `errors.varanasi.app` / `api.varanasi.app` | M1 | ADR-0007 |
| Enable RDS Multi-AZ; first restore drill | Before GA | ADR-0011 |

## 5. QG-01 criteria

| Criterion | Result |
|-----------|--------|
| ADR-0001 – ADR-0010 written, reviewed and Accepted | ✅ |
| A-016 cloud provider **and** region decided and frozen (not "later") | ✅ AWS · `ap-south-1` |
| Every business concept has one owner | ✅ ADR-0002 |
| Cross-module communication rule frozen | ✅ ADR-0003 §0 |
| Event standard + broker decided | ✅ ADR-0004, ADR-0005 |
| Tenant isolation model frozen, including shared vs dedicated | ✅ ADR-0006 |
| API, coding and testing standards defined with concrete examples and commands | ✅ ADR-0007 – ADR-0009 |
| PR checklist in the PR template | ✅ `.github/pull_request_template.md` |
| No open architectural contradictions | ✅ Section 3 |

**QG-01: PASSED**

## 6. Sign-off

| Role | Name | Date | Signature / approval reference |
|------|------|------|--------------------------------|
| Project owner | | 2026-09-27 | |
| Architecture reviewer | | | |

## 7. What happens next (M1)

- Create the repository skeleton exactly as in ADR-0008 §2, with every CI check from
  ADR-0009 running from the first commit.
- Terraform for the AWS `staging` and `production` accounts in `ap-south-1` (ADR-0011).
- Shared building blocks: tenant-aware session + RLS, auth and permission middleware,
  correlation ID, idempotency, Problem Details, outbox relay, consumer base, DLQ tool.
- Set up `CODEOWNERS` with the architecture reviewers (ADR-0010 §4).
