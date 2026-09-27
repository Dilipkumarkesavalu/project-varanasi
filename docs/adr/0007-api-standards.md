# ADR-0007: API Standards

- **Status:** Accepted (M0 approval, 2026-09-27)
- **Date:** 2026-09-27
- **Milestone:** M0
- **Task:** M0-ARC-007
- **Deciders:** Project owner (see `docs/architecture/M0-APPROVAL.md`)
- **Depends on:** ADR-0002 Service Boundaries, ADR-0003 Module Contracts, ADR-0004 Event
  Taxonomy, ADR-0006 Tenant Isolation
- **Supersedes / Superseded by:** —

## Context

Platform, Billing and HRMS all expose HTTP APIs to our web app and, later, to mobile apps
and customer integrations. If every module designs its APIs differently, clients need
special cases everywhere, errors are hard to handle, and security rules get applied
unevenly.

**Scope:** this ADR covers the **external HTTP APIs** that clients call. Calls *between
modules* inside the app use in-process contracts (ADR-0003), not HTTP.

## Decision

### 1. Basics

| Topic | Standard |
|-------|----------|
| Style | **REST over HTTPS**, JSON bodies |
| Spec | **OpenAPI 3.1**, contract-first. The spec is written or updated **before** the code, one spec per module, merged into one published document |
| Base path | `/api/v1/…` |
| Transport | HTTPS only (TLS 1.2+). HTTP is redirected or refused |
| Content type | `application/json; charset=utf-8`. Errors use `application/problem+json` |
| Field names | `snake_case`, the same as events (ADR-0004) |
| IDs | UUID strings (v7), e.g. `"0192f1a4-7c3e-7b21-9d8a-3f5e2c1b0a99"` |
| Timestamps | UTC ISO-8601 with `Z`: `"2026-09-27T10:15:30.123Z"` |
| Dates | `"2026-09-27"` |
| Money | `{ "amount": "1250.00", "currency": "INR" }`. The amount is a **decimal string** |
| Enums | Lowercase `snake_case` strings: `"draft"`, `"issued"`, `"bank_transfer"` |
| Nulls | Optional fields with no value are returned as `null`, not left out |
| Lint | OpenAPI specs are checked in CI with **Spectral** against these rules |

### 2. URLs and resources

```
/api/v1/{resource}
/api/v1/{resource}/{id}
/api/v1/{resource}/{id}/{sub-resource}
/api/v1/{resource}/{id}/{action}          ← state-changing actions only (POST)
```

Rules:

- Resources are **plural nouns** in `kebab-case`: `/invoices`, `/employees`,
  `/leave-requests`.
- Nest resources at most **one level** deep: `/invoices/{id}/payments` is fine,
  `/customers/{id}/invoices/{id}/payments` is not.
- **The tenant is never in the URL** for business resources. It comes from the token
  (ADR-0006).
- A **resource name belongs to exactly one module** (ADR-0002). The registry is below;
  a new resource is added here before it is built.
- **Business actions** that aren't simple edits use `POST /{resource}/{id}/{verb}`,
  e.g. `POST /invoices/{id}/issue`. These match the events they cause
  (`billing.invoice.issued.v1`).

**Resource registry (initial)**

| Path | Owner | Notes |
|------|-------|-------|
| `/api/v1/auth/…` | Platform | Login, token refresh, logout (section 10) |
| `/api/v1/me` | Platform | The current user and their tenant memberships |
| `/api/v1/tenants/current` | Platform | The caller's active tenant (name, settings, status) |
| `/api/v1/tenants` | Platform | **Platform admin only**: list or create tenants |
| `/api/v1/users`, `/api/v1/roles` | Platform | Users and roles within the current tenant |
| `/api/v1/entitlements` | Platform | The current tenant's products, features and limits (read-only) |
| `/api/v1/audit-events` | Platform | Audit log for the current tenant (read-only) |
| `/api/v1/customers` | Billing | The tenant's customers |
| `/api/v1/invoices` | Billing | Invoices; actions: `issue`, `void` |
| `/api/v1/payments` | Billing | Payments received |
| `/api/v1/employees` | HRMS | Employees; actions: `terminate` |
| `/api/v1/attendance-records` | HRMS | Attendance |
| `/api/v1/leave-requests` | HRMS | Leave; actions: `approve`, `reject`, `cancel` |
| `/api/v1/pay-runs` | HRMS | Payroll runs; actions: `finalize` |

### 3. HTTP methods

| Method | Use for | Idempotent? | Body |
|--------|---------|-------------|------|
| `GET` | Read one resource or a list | Yes | None |
| `POST` | Create a resource, or run an action (`/{id}/issue`) | **No, so it needs an `Idempotency-Key`** (section 8) | Yes |
| `PATCH` | Partial update (JSON Merge Patch). Only the fields you send change | Should be. Requires `If-Match` (section 9) | Yes |
| `PUT` | Full replacement. Used **only** for singleton settings, e.g. `PUT /tenants/current/settings` | Yes | Yes |
| `DELETE` | Delete or archive a resource | Yes | None |

- A `GET` never changes data.
- Business records with legal or financial meaning (issued invoices, payments, finalized
  pay runs) are **never deleted**. They are voided or reversed through an action.
  `DELETE` on them returns `409`.

### 4. Status codes

Use **only** these codes:

| Code | When |
|------|------|
| `200 OK` | Successful `GET`, `PATCH` or `PUT`, or an action that returns the updated resource |
| `201 Created` | A `POST` created a resource. Includes a `Location` header and the resource in the body |
| `202 Accepted` | A long-running job was started (e.g. a pay-run calculation). The body contains a job ID to check its status |
| `204 No Content` | A successful `DELETE` |
| `400 Bad Request` | Malformed JSON, an unknown query parameter, or an invalid header format |
| `401 Unauthorized` | Missing, invalid or expired token |
| `403 Forbidden` | Authenticated but not allowed: missing permission, tenant not entitled, or tenant suspended (writes) |
| `404 Not Found` | The resource doesn't exist **or belongs to another tenant** (ADR-0006, rule 8) |
| `405 Method Not Allowed` | The method isn't supported on this path |
| `409 Conflict` | The request conflicts with the current state: e.g. issuing an already issued invoice, a duplicate invoice number, or the same `Idempotency-Key` still in progress |
| `412 Precondition Failed` | The `If-Match` version is out of date (someone else changed the record) |
| `415 Unsupported Media Type` | The body isn't JSON |
| `422 Unprocessable Content` | Valid JSON that fails validation (a required field is missing, a value is out of range), or an `Idempotency-Key` reused with a different body |
| `428 Precondition Required` | A `PATCH` without `If-Match`, or a `POST` without `Idempotency-Key` where one is required |
| `429 Too Many Requests` | Rate limit hit. Includes a `Retry-After` header |
| `500 Internal Server Error` | An unexpected error. Never exposes stack traces or internal details |
| `503 Service Unavailable` | Maintenance mode or overload. Includes `Retry-After` |

### 5. Error format

All errors use **RFC 9457 Problem Details** (`application/problem+json`) with a few
standard extensions:

| Field | Required | Meaning |
|-------|----------|---------|
| `type` | Yes | A URL identifying the error type, e.g. `https://errors.varanasi.app/validation-failed` |
| `title` | Yes | A short, human-readable summary that doesn't change between occurrences |
| `status` | Yes | The HTTP status code |
| `code` | Yes | A stable, machine-readable error code in `snake_case`. **Clients branch on this**, never on `title` or `detail` |
| `detail` | No | An explanation for this occurrence. Safe to show users; no internal data |
| `instance` | No | The request path |
| `correlation_id` | Yes | Same as the `X-Correlation-ID` response header. Used by support to find the logs |
| `errors` | For 422 | A list of field errors: `{ "field", "code", "message" }` |

Standard `code` values: `validation_failed`, `not_found`, `unauthenticated`,
`permission_denied`, `not_entitled`, `tenant_suspended`, `conflict`,
`invalid_state_transition`, `version_mismatch`, `idempotency_key_reused`,
`idempotency_key_in_progress`, `rate_limited`, `internal_error`. Modules may add their own
codes (e.g. `invoice_already_issued`), and must document them in their OpenAPI spec.

### 6. Pagination

All list endpoints use **cursor pagination**. Offset/page-number pagination is **not**
used, because it becomes slow and inaccurate as data changes.

| Parameter | Default | Rule |
|-----------|---------|------|
| `limit` | `50` | Maximum `200`. Higher values return `400` |
| `cursor` | none | The opaque `next_cursor` value from the previous response. Clients must not build or parse it |

Response shape for **every** list:

```json
{
  "data": [ … ],
  "page": {
    "limit": 50,
    "next_cursor": "eyJpc3N1ZV9kYXRlIjoiMjAyNi0wOS0yMCIsImlkIjoi…",
    "has_more": true
  }
}
```

- `next_cursor` is `null` and `has_more` is `false` on the last page.
- A cursor is tied to the same filters and sort. Changing them requires starting from
  the first page.
- Total counts are **not** returned by default, because they're expensive. An endpoint
  that really needs one exposes `?include=total_count` and documents it.

### 7. Filtering and sorting

**Filtering**

```
?status=issued                          equals
?status=draft,issued                    any of (comma-separated)
?issue_date[gte]=2026-09-01             greater than or equal
?issue_date[lt]=2026-10-01              less than
?total_amount[gte]=1000.00
?customer_id=0192f1a4-…
?q=acme                                 free-text search (only where documented)
```

- Operators: `[eq]` (default), `[ne]`, `[gt]`, `[gte]`, `[lt]`, `[lte]`. Comma-separated
  values mean "any of".
- **Only fields listed in the endpoint's OpenAPI spec can be filtered.** Unknown filter
  fields return `400`. They are never silently ignored.
- Filters are always applied **inside** the tenant context. They can never widen access.

**Sorting**

```
?sort=-issue_date,invoice_number
```

- A comma-separated list. A `-` prefix means descending.
- Only documented fields can be sorted on. Anything else returns `400`.
- Every endpoint documents its **default sort**. `id` is always added as a final
  tie-breaker, so pagination is stable.

### 8. Idempotency

Networks fail, and clients retry. A retried "create invoice" or "record payment" must
**not** create a duplicate.

- `Idempotency-Key` is **required** on every `POST` that creates a resource or runs an
  action. A `POST` without it returns `428`.
- The client generates the key: a **UUID v4**, new for each distinct operation, and the
  **same** for retries of that operation.
- The server stores `(tenant_id, user_id, key)` → the request fingerprint (method + path +
  body hash) and the response, for **24 hours**.

| Situation | Server response |
|-----------|-----------------|
| New key | Process normally and store the response |
| Same key, same request, already completed | **Replay the original response** (same status and body) with the header `Idempotent-Replayed: true`. Nothing is created twice |
| Same key, still in progress | `409` with code `idempotency_key_in_progress`. The client retries later |
| Same key, **different** body or path | `422` with code `idempotency_key_reused` |

`PUT`, `PATCH` and `DELETE` are naturally idempotent and do not need the header.

### 9. Concurrency (optimistic locking)

- Every single-resource response includes an `ETag` header (a version), e.g.
  `ETag: "7"`.
- `PATCH` and state-changing actions **must** send `If-Match: "7"`. If someone else has
  changed the record in the meantime, the response is `412` and the client reloads.
- `PATCH` without `If-Match` returns `428`.

### 10. Correlation ID

- The client **may** send `X-Correlation-ID`: 8–64 characters, `A–Z a–z 0–9 - _`.
- If it's missing or invalid, the server generates one.
- The server **always** returns it in the `X-Correlation-ID` response header and in every
  error body.
- It is carried through everything the request causes: logs, contract calls between
  modules, and the `correlation_id` of every event published (ADR-0004). One ID traces an
  action end to end.

### 11. Authentication

- **Platform is the only issuer of identity** (ADR-0001).
- Clients send an access token on every request:
  `Authorization: Bearer <access_token>`.
- **Token format:** a signed JWT (asymmetric keys, e.g. ES256/RS256), valid for **15
  minutes**. Key claims:

  | Claim | Meaning |
  |-------|---------|
  | `sub` | Platform `user_id` |
  | `tid` | The **active `tenant_id`** (ADR-0006: the only source of tenant) |
  | `sid` | Session ID, used for logout and revocation |
  | `exp`, `iat`, `iss`, `aud` | Standard expiry, issue time, issuer and audience |

- **Refresh tokens** are long-lived, rotated on every use, and revocable. For the web
  app they are stored in a `Secure; HttpOnly; SameSite=Strict` cookie, never in
  JavaScript-accessible storage.
- **Switching tenant** means calling `POST /api/v1/auth/switch-tenant`, which issues a
  new token with the new `tid`.
- **Machine / integration clients** (later): OAuth 2.0 client credentials, each client
  bound to **one tenant** and a limited set of permissions.
- Only `POST /api/v1/auth/login`, `POST /api/v1/auth/refresh` and health checks are
  reachable without a token.
- Never put tokens, passwords or sensitive data in URLs or query strings.

### 12. Authorization

Every request passes these checks **in order**:

| # | Check | On failure |
|---|-------|------------|
| 1 | Token valid and not expired | `401 unauthenticated` |
| 2 | The user is still an active member of the token's tenant | `401 unauthenticated` |
| 3 | The tenant has the **entitlement** for this product/feature (ADR-0001) | `403 not_entitled` |
| 4 | Tenant is not suspended (writes only; reads are still allowed) | `403 tenant_suspended` |
| 5 | The user has the required **permission** | `403 permission_denied` |
| 6 | The resource exists **in this tenant** | `404 not_found` (even if it exists in another tenant) |
| 7 | Business rules / state allow the action | `409` / `422` |

- **Permission naming:** `<module>.<resource>.<action>`, e.g.
  `billing.invoice.create`, `billing.invoice.issue`, `hrms.employee.read`,
  `hrms.leave_request.approve`, `hrms.payroll.read_sensitive`.
- Each module **registers** its permissions with Platform (ADR-0002) and enforces them in
  its own endpoints.
- **Every operation in the OpenAPI spec declares its permission** with the extension
  `x-permission: billing.invoice.create`. The CI lint fails if one is missing.
  Endpoints without a permission must be explicitly marked `x-public: true`.
- Sensitive fields (salary, bank details, government IDs) need an **extra** permission
  (e.g. `hrms.payroll.read_sensitive`). Without it they are left out of the response.

### 13. Versioning and deprecation

- The major version is in the URL: `/api/v1/`.
- **Non-breaking changes stay in v1:** adding an endpoint, adding an optional request
  field, or adding a response field. **Clients must ignore unknown fields.**
- **Breaking changes need v2 of that resource:** removing or renaming a field, changing a
  type, adding a required field, or changing a meaning or status code.
- A deprecated endpoint returns `Deprecation: true` and a `Sunset: <date>` header, with
  at least **6 months** notice for external clients.

### 14. Rate limiting

- Limits apply per tenant and per user. Exact numbers are set in M1 after load testing.
- Responses include `RateLimit-Limit`, `RateLimit-Remaining` and `RateLimit-Reset`. When
  the limit is exceeded: `429` plus `Retry-After`.
- Login and token endpoints have stricter limits per IP address and per account.

### 15. Standard headers

| Header | Direction | Required | Purpose |
|--------|-----------|----------|---------|
| `Authorization: Bearer …` | Request | Yes (except public endpoints) | Authentication |
| `Content-Type: application/json` | Request | On requests with a body | |
| `Idempotency-Key` | Request | On `POST` creates/actions | Section 8 |
| `If-Match` | Request | On `PATCH` and actions | Section 9 |
| `X-Correlation-ID` | Both | Optional in the request, always in the response | Section 10 |
| `ETag` | Response | Single-resource responses | Section 9 |
| `Location` | Response | On `201` | URL of the new resource |
| `Idempotent-Replayed: true` | Response | On a replayed response | Section 8 |
| `RateLimit-*`, `Retry-After` | Response | Always / on `429` and `503` | Section 14 |
| `Deprecation`, `Sunset` | Response | On deprecated endpoints | Section 13 |

## Examples

### Example 1: Create an invoice (draft)

**Request**

```http
POST /api/v1/invoices HTTP/1.1
Host: api.varanasi.app
Authorization: Bearer eyJhbGciOiJFUzI1NiIs…
Content-Type: application/json
Idempotency-Key: 5b8f2c1e-3d4a-4f6b-9c7e-1a2b3c4d5e6f
X-Correlation-ID: req-7f3a9c2e

{
  "customer_id": "0192f1a4-7c3e-7b21-9d8a-00000000c001",
  "issue_date": "2026-09-27",
  "due_date": "2026-10-27",
  "currency": "INR",
  "lines": [
    {
      "description": "Consulting services - September",
      "quantity": "10",
      "unit_price": { "amount": "1000.00", "currency": "INR" },
      "tax_code": "GST18"
    }
  ],
  "notes": "Thank you for your business."
}
```

**Response**

```http
HTTP/1.1 201 Created
Location: /api/v1/invoices/0192f1b0-1111-7aaa-8bbb-00000000i001
ETag: "1"
X-Correlation-ID: req-7f3a9c2e
Content-Type: application/json

{
  "id": "0192f1b0-1111-7aaa-8bbb-00000000i001",
  "invoice_number": null,
  "status": "draft",
  "customer_id": "0192f1a4-7c3e-7b21-9d8a-00000000c001",
  "issue_date": "2026-09-27",
  "due_date": "2026-10-27",
  "lines": [
    {
      "line_no": 1,
      "description": "Consulting services - September",
      "quantity": "10",
      "unit_price": { "amount": "1000.00", "currency": "INR" },
      "tax_code": "GST18",
      "line_total": { "amount": "10000.00", "currency": "INR" }
    }
  ],
  "subtotal": { "amount": "10000.00", "currency": "INR" },
  "tax_total": { "amount": "1800.00", "currency": "INR" },
  "total": { "amount": "11800.00", "currency": "INR" },
  "notes": "Thank you for your business.",
  "created_at": "2026-09-27T10:15:30.123Z",
  "updated_at": "2026-09-27T10:15:30.123Z"
}
```

### Example 2: The client retries the same request (network timeout)

The same `Idempotency-Key` and the same body as Example 1:

```http
HTTP/1.1 201 Created
Location: /api/v1/invoices/0192f1b0-1111-7aaa-8bbb-00000000i001
Idempotent-Replayed: true
X-Correlation-ID: req-7f3a9c2e
```

The body is identical to Example 1. **No second invoice is created.**

### Example 3: Issue the invoice (an action with optimistic locking)

```http
POST /api/v1/invoices/0192f1b0-1111-7aaa-8bbb-00000000i001/issue HTTP/1.1
Authorization: Bearer eyJhbGciOiJFUzI1NiIs…
Idempotency-Key: 9d1e7a3b-2c4f-4e8a-b6d0-7f1e2a3b4c5d
If-Match: "1"
X-Correlation-ID: req-8a4b0d3f
```

```http
HTTP/1.1 200 OK
ETag: "2"
X-Correlation-ID: req-8a4b0d3f
Content-Type: application/json

{
  "id": "0192f1b0-1111-7aaa-8bbb-00000000i001",
  "invoice_number": "INV-2026-000123",
  "status": "issued",
  "issued_at": "2026-09-27T10:20:02.456Z",
  "total": { "amount": "11800.00", "currency": "INR" },
  "…": "other fields as in Example 1"
}
```

This publishes `billing.invoice.issued.v1` with `correlation_id: "req-8a4b0d3f"`
(ADR-0004).

### Example 4: List invoices with filtering, sorting and pagination

```http
GET /api/v1/invoices?status=issued,paid&issue_date[gte]=2026-09-01&sort=-issue_date&limit=2 HTTP/1.1
Authorization: Bearer eyJhbGciOiJFUzI1NiIs…
X-Correlation-ID: req-9b5c1e40
```

```http
HTTP/1.1 200 OK
X-Correlation-ID: req-9b5c1e40
Content-Type: application/json

{
  "data": [
    {
      "id": "0192f1b0-1111-7aaa-8bbb-00000000i001",
      "invoice_number": "INV-2026-000123",
      "status": "issued",
      "customer_id": "0192f1a4-7c3e-7b21-9d8a-00000000c001",
      "issue_date": "2026-09-27",
      "due_date": "2026-10-27",
      "total": { "amount": "11800.00", "currency": "INR" }
    },
    {
      "id": "0192f1b0-1111-7aaa-8bbb-00000000i000",
      "invoice_number": "INV-2026-000122",
      "status": "paid",
      "customer_id": "0192f1a4-7c3e-7b21-9d8a-00000000c002",
      "issue_date": "2026-09-25",
      "due_date": "2026-10-25",
      "total": { "amount": "4500.00", "currency": "INR" }
    }
  ],
  "page": {
    "limit": 2,
    "next_cursor": "eyJpc3N1ZV9kYXRlIjoiMjAyNi0wOS0yNSIsImlkIjoiMDE5MmYxYjAtLi4uIn0",
    "has_more": true
  }
}
```

### Example 5: Validation error

```http
POST /api/v1/employees HTTP/1.1
Authorization: Bearer eyJhbGciOiJFUzI1NiIs…
Content-Type: application/json
Idempotency-Key: 3e2d1c0b-4a5f-4e6d-8c7b-9a0f1e2d3c4b
X-Correlation-ID: req-aa11bb22

{
  "display_name": "",
  "joining_date": "2026-13-01"
}
```

```http
HTTP/1.1 422 Unprocessable Content
Content-Type: application/problem+json
X-Correlation-ID: req-aa11bb22

{
  "type": "https://errors.varanasi.app/validation-failed",
  "title": "Validation failed",
  "status": 422,
  "code": "validation_failed",
  "detail": "3 fields are invalid.",
  "instance": "/api/v1/employees",
  "correlation_id": "req-aa11bb22",
  "errors": [
    { "field": "display_name", "code": "required", "message": "Display name is required." },
    { "field": "joining_date", "code": "invalid_date", "message": "Must be a valid date (YYYY-MM-DD)." },
    { "field": "department_id", "code": "required", "message": "Department is required." }
  ]
}
```

### Example 6: Another tenant's record (returns 404, not 403)

```http
GET /api/v1/employees/0192f1c9-9999-7fff-8eee-0000000000b1 HTTP/1.1
Authorization: Bearer <token for Tenant A>
```

```http
HTTP/1.1 404 Not Found
Content-Type: application/problem+json
X-Correlation-ID: 4c1f9e7a2b3d

{
  "type": "https://errors.varanasi.app/not-found",
  "title": "Resource not found",
  "status": 404,
  "code": "not_found",
  "instance": "/api/v1/employees/0192f1c9-9999-7fff-8eee-0000000000b1",
  "correlation_id": "4c1f9e7a2b3d"
}
```

This response is identical whether the employee exists in Tenant B or doesn't exist at
all (ADR-0006).

### Example 7: The tenant hasn't bought HRMS

```http
HTTP/1.1 403 Forbidden
Content-Type: application/problem+json

{
  "type": "https://errors.varanasi.app/not-entitled",
  "title": "Feature not included in your plan",
  "status": 403,
  "code": "not_entitled",
  "detail": "Your organization's plan does not include HRMS.",
  "correlation_id": "req-cc33dd44"
}
```

### Example 8: Concurrent edit conflict

```http
PATCH /api/v1/employees/0192f1c9-2222-7bbb-8ccc-00000000e042 HTTP/1.1
Authorization: Bearer eyJhbGciOiJFUzI1NiIs…
Content-Type: application/merge-patch+json
If-Match: "4"

{ "department_id": "0192f1a4-7c3e-7b21-9d8a-000000000011" }
```

```http
HTTP/1.1 412 Precondition Failed
Content-Type: application/problem+json

{
  "type": "https://errors.varanasi.app/version-mismatch",
  "title": "The record was changed by someone else",
  "status": 412,
  "code": "version_mismatch",
  "detail": "Reload the employee and apply your change again.",
  "correlation_id": "req-ee55ff66"
}
```

## Options considered

| Option | Verdict | Why |
|--------|---------|-----|
| **REST + OpenAPI (chosen)** | ✅ | Widely understood, great tooling, easy for customer integrations, cacheable, and maps cleanly onto our resources |
| GraphQL | ❌ for now | Flexible for the UI, but authorization per field, rate limiting, caching and tenant-safe query cost control are harder. Could be added later as a layer for the UI only |
| gRPC | ❌ externally | Excellent for service-to-service, but poor for browsers and customer integrations. Internal calls already use in-process contracts (ADR-0003) |
| Offset pagination | ❌ | Slow on large tables, and pages shift when data changes |
| Custom error format | ❌ | RFC 9457 is a standard with client support; custom formats drift |

## Consequences

- **Positive**
  - One predictable style across all three products. Client code (errors, paging,
    retries) is written once.
  - Idempotency keys and `If-Match` prevent the two most common data bugs: duplicate
    creates and lost updates.
  - The correlation ID links a click in the UI to logs, events and consumers.
  - Authorization is declared in the spec, so it can be checked automatically.
- **Negative / trade-offs**
  - Clients must generate idempotency keys and handle `ETag`/`If-Match`.
  - The server must store idempotency records (24 h).
  - Cursor pagination can't jump to "page 7". The UI uses "load more" or infinite scroll
    instead.
  - Contract-first OpenAPI means writing the spec before the code.
- **Follow-ups**
  - ADR-0008: pick the framework, the OpenAPI tooling and the Spectral ruleset.
  - ADR-0009: API contract tests and the cross-tenant test suite (ADR-0006).
  - ADR-0010: add API standard checks to the review checklist.
  - M1: shared middleware for authentication, tenant context, correlation IDs,
    idempotency, error mapping and rate limiting.

## References

- RFC 9110 HTTP Semantics
- RFC 9457 Problem Details for HTTP APIs
- RFC 7396 JSON Merge Patch
- IETF draft: The Idempotency-Key HTTP Header Field
- IETF draft: RateLimit header fields for HTTP
- ADR-0002 Service Boundaries
- ADR-0003 Module Contracts
- ADR-0004 Event Taxonomy
- ADR-0006 Tenant Isolation
