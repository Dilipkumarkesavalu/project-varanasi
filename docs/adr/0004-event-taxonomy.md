# ADR-0004: Event Taxonomy

- **Status:** Accepted (M0 approval, 2026-09-27)
- **Date:** 2026-09-27
- **Milestone:** M0
- **Task:** M0-ARC-004
- **Deciders:** Project owner (see `docs/architecture/M0-APPROVAL.md`)
- **Depends on:** ADR-0002 Service Boundaries, ADR-0003 Module Contracts
- **Supersedes / Superseded by:** —

## Context

ADR-0003 allows modules to communicate through an **API** or an **Event**. Events are the
main way to:

- let Platform notify Billing and HRMS (Platform never calls them directly);
- let Billing and HRMS react to each other without a hard dependency;
- feed future reporting, notifications and integrations.

If every module invents its own event names and formats, consumers break, tracing across
modules becomes impossible, and tenant data can leak. This ADR sets one standard for all
events.

## Decision

### 1. Naming

```
<module>.<entity>.<action>.v<version>
```

| Part | Rule | Example |
|------|------|---------|
| `module` | The **owning** module from ADR-0002: `platform`, `billing` or `hrms` | `hrms` |
| `entity` | The business concept, singular, `snake_case` | `employee`, `leave_request` |
| `action` | **Past tense.** An event is a fact that already happened, not a command | `created`, `issued`, `terminated` |
| `v<version>` | Major version of the payload format, starting at `v1` | `v1` |

Examples:

```
billing.invoice.issued.v1
billing.payment.received.v1
hrms.employee.created.v1
hrms.employee.updated.v1
hrms.employee.terminated.v1
```

Rules:

- **Only the owner publishes events about its concepts.** Billing never publishes
  `hrms.*` events.
- All lowercase, dot-separated, no spaces or dashes.
- Use business language (`invoice.issued`), not technical language (`invoice_row.inserted`).
- Never use command names like `billing.invoice.send`. If you need to ask another module
  to do something, call its API.

### 2. Event envelope

Every event has the same outer structure (the **envelope**). Business data goes inside
`payload`.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `event_name` | string | Yes | Full name without the version, e.g. `hrms.employee.created` |
| `event_version` | integer | Yes | Payload format version, e.g. `1`. Must match the `.v1` suffix |
| `event_id` | UUID | Yes | Unique ID for this event. Consumers use it to ignore duplicates |
| `tenant_id` | UUID | Yes | The tenant the event belongs to. **Never empty** (see section 5) |
| `occurred_at` | timestamp | Yes | When the business fact happened. UTC, ISO-8601 with milliseconds, e.g. `2026-09-27T10:15:30.123Z` |
| `producer` | string | Yes | The module that published it: `platform`, `billing` or `hrms` |
| `correlation_id` | string | Yes | ID of the original request or job that led to this event. The same value flows through every event and log it causes, so one action can be traced end to end |
| `payload` | object | Yes | The business data. Its format is defined per event (section 7) |
| `causation_id` | UUID | Optional | The `event_id` of the event that directly caused this one, if any |
| `actor_id` | UUID | Optional | Platform `user_id` of the person who triggered it. Empty for system actions |

Example:

```json
{
  "event_name": "hrms.employee.created",
  "event_version": 1,
  "event_id": "0192f1a4-7c3e-7b21-9d8a-3f5e2c1b0a99",
  "tenant_id": "0192f19f-11aa-7c00-8e21-5b7d9c4e2f10",
  "occurred_at": "2026-09-27T10:15:30.123Z",
  "producer": "hrms",
  "correlation_id": "req-7f3a9c2e",
  "causation_id": null,
  "actor_id": "0192f1a0-2b3c-7d4e-8f50-6a7b8c9d0e1f",
  "payload": {
    "employee_id": "0192f1a4-7c3e-7b21-9d8a-000000000001",
    "employee_code": "EMP-0042",
    "user_id": null,
    "display_name": "A. Kumar",
    "department_id": "0192f1a4-7c3e-7b21-9d8a-000000000010",
    "joining_date": "2026-10-01",
    "status": "active"
  }
}
```

### 3. Payload rules

1. **Carry what consumers need, not the whole record.** Include IDs plus the few fields
   consumers commonly need, so they don't have to call back immediately. Anything else
   can be fetched through the owner's API.
2. **No sensitive data in events.** Never put in a payload:
   - passwords, tokens or secrets;
   - bank account or card numbers;
   - salary amounts, payslip lines, or government IDs (PAN, Aadhaar, etc.);
   - medical or leave-reason details.

   If a consumer needs these, it calls the owner's API, which checks permissions.
3. **IDs are UUIDs**, and refer to the owner's concept (`employee_id`, `invoice_id`).
4. **Money** is `{ "amount": "1250.00", "currency": "INR" }`. The amount is a
   decimal **string** to avoid floating-point errors, and the currency is an ISO-4217 code.
5. **Dates** are `YYYY-MM-DD`. **Timestamps** are UTC ISO-8601.
6. **Field names** are `snake_case`.
7. **`*.updated` events list what changed** in `changed_fields`. They include new values
   only for non-sensitive fields.

### 4. Versioning

| Change to the payload | Same version? | What to do |
|-----------------------|---------------|------------|
| Add an optional field | Yes | Consumers must ignore fields they don't recognise |
| Remove or rename a field, change a type or meaning, make a field required | **No, it's breaking** | Publish `.v2` **alongside** `.v1`, move all consumers to `.v2`, then stop publishing `.v1` |

The schema for each version lives in the owning module's `contract/` package as a JSON
Schema file (ADR-0003). CI checks that published events match their schema.

### 5. Tenant safety

- Every event has a `tenant_id`, including Platform events. For tenant lifecycle
  events, `tenant_id` is the tenant itself.
- A consumer must process an event **only within that tenant's context**, and must set
  the tenant context from `tenant_id` before touching any data (ADR-0006).
- An event without a valid `tenant_id` is rejected and sent to the dead-letter queue
  (ADR-0005).

### 6. Delivery expectations

Details are in ADR-0005. Every producer and consumer should assume the following:

- **At-least-once delivery.** The same event may arrive more than once. Consumers must
  be **idempotent**: record the `event_id` values they have processed and skip repeats.
- **No global ordering.** Ordering is only best-effort per entity. Consumers should use
  `occurred_at` and the current state from the owner's API when order matters.
- **Publish only after commit.** An event is published only after the producer's
  database transaction commits (outbox pattern, ADR-0005). No event is ever published
  for a change that was rolled back.

### 7. Event catalogue

This catalogue lists every event and answers three questions: **Who produces it? Who
consumes it? What does the payload contain?**

"None yet" means no module consumes the event today. It is still published for future
reporting, notifications and integrations.

#### Billing events

| Event | Producer | Consumers | Triggered when | Payload |
|-------|----------|-----------|----------------|---------|
| `billing.invoice.issued.v1` | Billing | None yet (future: notifications, reporting) | An invoice is finalised and issued to a customer (not when a draft is saved) | `invoice_id`, `invoice_number`, `customer_id`, `issue_date`, `due_date`, `total` (money), `status` |
| `billing.payment.received.v1` | Billing | None yet (future: notifications, reporting) | A payment from a tenant's customer is recorded against an invoice | `payment_id`, `invoice_id`, `customer_id`, `amount` (money), `received_on`, `method` (`cash`, `bank_transfer`, `upi`, `card`, `other`). **No account or card numbers** |

#### HRMS events

| Event | Producer | Consumers | Triggered when | Payload |
|-------|----------|-----------|----------------|---------|
| `hrms.employee.created.v1` | HRMS | **Platform**: updates the tenant's employee count for entitlement limits | A new employee record is created | `employee_id`, `employee_code`, `user_id` (nullable), `display_name`, `department_id`, `joining_date`, `status` |
| `hrms.employee.updated.v1` | HRMS | None yet (future: reporting) | Non-sensitive employee details change | `employee_id`, `changed_fields` (list of field names), new values for non-sensitive fields only (`display_name`, `department_id`, `designation`, `status`, `user_id`). **No salary, bank or ID fields** |
| `hrms.employee.terminated.v1` | HRMS | **Platform**: updates the employee count, and deactivates the linked login if the tenant has enabled that setting | An employee's employment ends | `employee_id`, `user_id` (nullable), `last_working_date`, `termination_type` (`resignation`, `termination`, `retirement`, `other`). **No reason text** |

#### Platform events

| Event | Producer | Consumers | Triggered when | Payload |
|-------|----------|-----------|----------------|---------|
| `platform.tenant.created.v1` | Platform | **Billing, HRMS**: set up default settings for the new tenant | A tenant is created | `tenant_id`, `name`, `country`, `timezone`, `default_currency` |
| `platform.tenant.suspended.v1` | Platform | **Billing, HRMS**: block writes (new invoices, new pay runs) while still allowing reads | A tenant is suspended, e.g. for non-payment | `tenant_id`, `reason_code` (`non_payment`, `admin_action`, `other`), `suspended_at` |
| `platform.tenant.reactivated.v1` | Platform | **Billing, HRMS**: unblock writes | A suspended tenant is restored | `tenant_id`, `reactivated_at` |
| `platform.user.deactivated.v1` | Platform | **HRMS**: marks the linked employee as having no active login | A user's access is removed | `user_id`, `deactivated_at` |
| `platform.entitlement.changed.v1` | Platform | **Billing, HRMS**: refresh cached entitlements and limits | A tenant's plan or features change | `tenant_id`, `products` (e.g. `["billing","hrms"]`), `features` (list), `limits` (e.g. `{ "max_employees": 50 }`) |

#### Audit events (documented exception to "only the owner publishes")

Audit is owned by Platform (ADR-0002), but the *facts* being audited happen in every
module. To keep each audit entry atomic with the change it records (ADR-0010 G1), without
writing across schemas (ADR-0003 rule 5), **each module publishes its own audit events
through its own outbox**. **Platform owns the schema.**

| Event | Producer | Consumers | Triggered when | Payload |
|-------|----------|-----------|----------------|---------|
| `<module>.audit_entry.recorded.v1` (e.g. `billing.audit_entry.recorded.v1`) | Any module (Platform writes its own audit entries directly) | **Platform**: stores the entry in the audit log | A sensitive action (ADR-0010 §2) is committed | `action` (e.g. `billing.invoice.voided`), `resource_type`, `resource_id`, `outcome` (`success`, `denied`, `failed`), `changed_fields` (names only). **Never the sensitive values themselves.** Actor, tenant, time and correlation come from the envelope |

The JSON Schema lives in `platform/contract/events/audit_entry_recorded_v1.json`. All
producers use it.

### 8. Adding a new event

Before a new event is published, the owning module must:

1. Name it according to section 1.
2. Write its payload JSON Schema in `contract/events/`.
3. Add a row to the catalogue in section 7 covering the producer, consumers, trigger and
   payload.
4. Check that the payload follows section 3 (especially that it contains no sensitive
   data).
5. Get it reviewed with the ADR-0010 checklist.

Consumers must be added to the catalogue whenever they start subscribing, so the list of
consumers is always accurate.

## Options considered

1. **Free-form events per module.** Quick, but events become inconsistent, can't be
   traced, and consumers break easily. *Rejected.*
2. **Adopt CloudEvents exactly.** An industry standard, but its field names
   (`specversion`, `source`, `type`) are less readable for this team and it adds nothing
   while we run in one app. *Not adopted now.* Our envelope maps 1:1 onto CloudEvents
   if we need it later (`event_id`→`id`, `producer`→`source`,
   `event_name`+`event_version`→`type`, `occurred_at`→`time`, `payload`→`data`, and
   `tenant_id`/`correlation_id` as extensions).
3. **A single simple envelope with named, versioned events and a catalogue (chosen).**

## Consequences

- **Positive**
  - Every event is recognisable, traceable (`correlation_id`) and tenant-scoped.
  - Consumers can rely on a stable format and a clear way to handle new versions.
  - The catalogue shows exactly who depends on what.
- **Negative / trade-offs**
  - Consumers must handle duplicates and out-of-order events.
  - The catalogue and schemas have to be kept up to date. This is enforced in review
    and CI.
  - Some consumers will need an extra API call for data that isn't in the payload.
- **Follow-ups**
  - ADR-0005: in-process event bus, outbox, retries and dead-letter queue.
  - ADR-0006: how consumers set tenant context from `tenant_id`.
  - ADR-0009: schema validation and consumer idempotency tests.

## References

- ADR-0002 Service Boundaries
- ADR-0003 Module Contracts
- ADR-0005 Event Broker
- ADR-0006 Tenant Isolation
