# ADR-0005: Event Broker

- **Status:** Accepted (M0 approval, 2026-09-27). **FROZEN.** Broker = RabbitMQ.
- **Date:** 2026-09-27
- **Milestone:** M0
- **Task:** M0-ARC-005
- **Deciders:** Project owner (see `docs/architecture/M0-APPROVAL.md`)
- **Depends on:** ADR-0001 Product Separation, ADR-0003 Module Contracts, ADR-0004 Event
  Taxonomy, ADR-0011 Cloud Platform (A-016)
- **Supersedes / Superseded by:** —

## Context

ADR-0004 defines *what* an event looks like. This ADR decides *how events are delivered*
between modules.

Our situation, which drives the decision:

| Fact | Source |
|------|--------|
| One modular application (Platform, Billing, HRMS) | ADR-0001 |
| Deployed on **one dedicated server** | ADR-0001 |
| A small team with no dedicated platform/ops engineer (assumed) | — |
| Event volume is low to moderate: business events like invoices, payments, employee changes. Tens to hundreds per minute, not thousands per second | ADR-0004 catalogue |
| Required: at-least-once delivery, retries, a **dead-letter queue**, tenant-safe processing, publish only after the DB commit | ADR-0004 §5–6 |
| Modules may later be extracted into separate services | ADR-0003 |

The playbook compares **RabbitMQ**, **Redis Streams** and **Kafka**. The playbook's
beginner default is RabbitMQ, but that default was **not** assumed here. Each option was
scored against our situation.

## Evaluation

### Factor-by-factor comparison

| Factor | Question | RabbitMQ | Redis Streams | Kafka |
|--------|----------|----------|---------------|-------|
| **Setup** | How hard is it for our team? | **Easy.** One container, a management UI out of the box, mature client libraries in every major language. Concepts (exchange, queue, binding) take a day to learn. | **Easiest to start.** One container, and we may run Redis for caching anyway. But the consumer-group, pending-list and claim logic has to be written by us. | **Hardest.** Even with KRaft (no ZooKeeper), there are partitions, offsets, consumer groups, retention and rebalancing to learn. Tuning it on one server is awkward. |
| **Reliability** | What happens when a consumer fails? | A message isn't removed until the consumer **acks** it. If the consumer crashes, the message goes back to the queue and is redelivered automatically. Durable queues and persistent messages survive a broker restart. | The message stays in the consumer group's **pending list**. Another consumer must explicitly claim it (`XAUTOCLAIM`); we have to build that. Durability depends on AOF/fsync settings, and with default settings the last ~1 s of writes can be lost on a crash. | The offset isn't committed, so the message is re-read after a restart. It is very durable, **but** one failing message blocks everything behind it in that partition until we handle it. |
| **Retry** | How are failed events retried? | **Built in.** A nack/requeue plus a per-queue **delivery limit** (quorum queues). Delayed retries with backoff use retry queues with TTL that route back to the main queue. This is a standard, well-documented pattern. | **Manual.** We track the delivery count from the pending list and re-claim after a timeout. There's no built-in backoff, so all the retry logic is our code. | **Manual.** The usual pattern is separate retry topics (`retry-10s`, `retry-1m`, …) with consumers that wait. It works, but it's more topics, more code and more to monitor. |
| **DLQ** | Can failed messages go to dead-letter storage? | **Yes, natively.** Dead-letter exchanges (DLX) route rejected, expired or over-limit messages to a DLQ automatically, with the reason in the headers. | **No native DLQ.** We have to copy the message to a separate stream ourselves and acknowledge the original. | **No native DLQ in the broker.** It is a convention: consumer code publishes to a `*.dlq` topic. |
| **Operations** | How hard is production maintenance? | **Low to moderate.** Single node is simple. There is a built-in UI, a Prometheus plugin, and clear memory/disk alarms. Main risk: letting queues grow unbounded. This is handled with alerts. | **Low at first, rising later.** The Redis instance is easy, but our custom retry/DLQ code *is* the operations burden. Memory-bound: a large backlog uses RAM. | **High.** Disk and retention sizing, partition planning, JVM tuning, upgrades. It is designed for clusters; on one server we pay the complexity without getting the resilience. |
| **Scale** | Can it grow with our platform? | **Yes, comfortably for our needs.** Tens of thousands of messages per second on modest hardware, far above our expected load. Grows to a 3-node cluster with quorum queues when we leave the single server. | **Moderate.** Fine for our volume, but limited by memory, and clustering Redis for Streams adds complexity. | **Best for very high throughput**, long retention and replay. Far more than we need now. |

### Summary score for our situation

Scores run 1 (poor) to 5 (excellent), **for a small team, one server, and business-event
volume**. They are not general rankings.

| Factor | RabbitMQ | Redis Streams | Kafka |
|--------|:--------:|:-------------:|:-----:|
| Setup | 4 | 4 | 2 |
| Reliability | 5 | 3 | 5 |
| Retry | 5 | 2 | 3 |
| DLQ | 5 | 2 | 3 |
| Operations | 4 | 3 | 2 |
| Scale (for our needs) | 4 | 3 | 5 |
| **Total** | **27** | **17** | **20** |

### Why not Redis Streams?

It is easy to start with and we might run Redis anyway. However, **retry, backoff, claim
and DLQ would all be our own code**, and those are exactly the parts that must be
reliable. Its durability also depends on fsync settings. We would be building half a
message broker ourselves.

### Why not Kafka?

Kafka is excellent at what it's designed for: very high-throughput streams, long
retention and replaying history. **We don't need any of that now**, it has no native
retry or DLQ, and a single-server deployment gets none of its resilience benefits while
keeping all of its operational cost. It remains the right choice if we later build a
high-volume analytics or data pipeline.

### Also considered: no broker (a PostgreSQL outbox table used as the queue)

For a modular monolith, one legitimate option is to have consumers poll the outbox table
directly (`SELECT … FOR UPDATE SKIP LOCKED`), with no broker at all. It has the fewest
moving parts.

**Rejected** because we would again hand-build routing to several consumers,
per-consumer retry and backoff, a DLQ and monitoring. It also doesn't give extracted
services a ready-made path. We **do** keep the outbox table; it becomes the reliable
hand-off to RabbitMQ (see below).

## Decision

> **We will use RabbitMQ as the event broker, combined with a transactional outbox in
> the application database.**
>
> **This choice is FROZEN for M0.** Changing it requires a superseding ADR and an
> architecture review (ADR-0010).

**Why RabbitMQ:** it is the only option of the three that provides **acks, redelivery,
retry limits and dead-lettering natively**. Those are the reliability features ADR-0004
requires. It also has low setup and operations cost for one server, and a clear path to
a cluster. We chose it because it scored best on our factors, **not** because it is the
playbook default.

### How it works

```
┌──────────── one database transaction ────────────┐
│  Billing writes invoice   +   inserts outbox row │   ← event can't be lost or sent early
└──────────────────────────────────────────────────┘
                     │
            Outbox relay (in the app)
     reads new outbox rows → publishes to RabbitMQ
     (publisher confirms) → marks rows as sent
                     │
                     ▼
         Exchange: "events" (type: topic, durable)
         routing key = event name + version
         e.g. billing.invoice.issued.v1
                     │
     ┌───────────────┼──────────────────┐
     ▼               ▼                  ▼
 queue per consumer + event (durable quorum queues)
 e.g. platform.hrms.employee.created.v1
                     │
       consumer handler (in the consuming module)
       1. validate envelope + schema + tenant_id
       2. skip if event_id already processed
       3. set tenant context → handle → record event_id
       4. ack
```

### Configuration standards

| Item | Standard |
|------|----------|
| RabbitMQ version | Current supported **4.x** release |
| Exchange | One topic exchange called `events` (durable). A dead-letter exchange called `events.dlx` |
| Routing key | `<event_name>.v<event_version>`, e.g. `hrms.employee.terminated.v1` (ADR-0004) |
| Queues | **One queue per consumer module per event**: `<consumer>.<event_name>.v<N>`, e.g. `billing.platform.tenant.suspended.v1`. A failure in one consumer doesn't block the others |
| Queue type | **Quorum queues** (durable, with a native delivery limit and dead-lettering), even on a single node, so the cluster path later needs no changes |
| Messages | Persistent, JSON, `content_type=application/json`. The `message_id` header is set to `event_id` |
| Publishing | Only through the **outbox relay**, with **publisher confirms** enabled. Rows are marked sent only after RabbitMQ confirms |
| Consuming | Manual ack. Prefetch of 10–20 per consumer. Idempotent via a `processed_events` table in each consuming module, keyed on `(consumer, event_id)` |
| Credentials | A separate RabbitMQ user per module, allowed to publish only its own routing keys and consume only its own queues |

### Retry and DLQ policy

| Failure type | Example | Handling |
|--------------|---------|----------|
| **Temporary** | DB timeout, a dependency briefly down | Retry with backoff: **10 s → 1 min → 5 min → 30 min → 2 h** (5 attempts) through TTL retry queues, then send to the **DLQ** |
| **Permanent** | Invalid schema, missing or unknown `tenant_id`, unknown event version | **No retry.** Send to the DLQ immediately |
| **Bug in the handler** | An unexpected exception | Treat as temporary. After 5 attempts it ends up in the DLQ |

**DLQ**

- Each consumer queue has its own DLQ: `<queue>.dlq`.
- Messages keep the reason, the original routing key and the attempt count in their
  headers.
- **Any message in a DLQ triggers an alert.** Nothing sits there silently.
- A small admin tool (M1) lets an operator **view, replay after a fix, or discard (with
  an audit entry)** DLQ messages. Replay is safe because consumers are idempotent.
- DLQ messages are kept for **14 days**.

### Failure scenarios

| What fails | What happens | Data lost? |
|------------|--------------|------------|
| A consumer crashes mid-processing | No ack, so RabbitMQ redelivers the message | No |
| A consumer keeps failing on one message | It retries 5 times with backoff, goes to the DLQ, and an alert fires. Other messages keep flowing | No |
| RabbitMQ is down | The app keeps working. Events **accumulate in the outbox table**, and the relay publishes them when RabbitMQ is back | No |
| The app crashes after the DB commit but before publishing | The outbox row is still unsent, so the relay publishes it on restart | No |
| The relay publishes but crashes before marking the row as sent | The event is published twice. Consumers skip the duplicate `event_id` | No |
| The app server (and RabbitMQ's disk) is lost | The database is on RDS, separate from the server (ADR-0011), so the business data and the outbox survive. The server is rebuilt from Terraform + the image. Unsent outbox rows are published as normal; messages that were already sent but not yet consumed are **republished from the outbox** (kept 7 days). Consumers skip duplicates | No |
| The database is lost | Point-in-time restore from RDS backups (ADR-0011) | Up to the RPO (≤ 15 min) |

### Operations

- Runs as a container on the dedicated server, next to the app (ADR-0011).
- The **Prometheus plugin** is enabled. Alerts fire on:
  - DLQ depth > 0
  - a queue with no consumers
  - the oldest unacked message is older than 5 min
  - a memory or disk alarm
  - the outbox has unsent rows older than 2 min
- Queue and exchange definitions are kept in the repo and applied at deploy time. They
  are never hand-created in the UI.
- Sent outbox rows are kept for **7 days** for debugging and replay, then purged.

### When to revisit (the freeze can be lifted by a new ADR if…)

- sustained load goes above ~5,000 events/second, or
- we need long-term event history and replay (e.g. an analytics or data pipeline, where
  Kafka or RabbitMQ Streams should be considered **for that pipeline**), or
- we move off the single server and need a managed broker from the chosen cloud (ADR-0011).

## Consequences

- **Positive**
  - Native retry, delivery limits and DLQ. Failure handling is configuration, not
    custom code.
  - The outbox means **no event is lost or sent early**, even when RabbitMQ is down.
  - A per-consumer-queue design keeps one module's failures from blocking others.
  - A clear path to a cluster, or to services extracted from the monolith.
- **Negative / trade-offs**
  - Another component to run, monitor, back up (its definitions) and upgrade.
  - RabbitMQ is **not a replay log**. Once a message is acked it's gone. Replay comes
    from the outbox (7 days) or the owner's API.
  - On one server, RabbitMQ shares the app's single point of failure. The outbox limits
    the impact to delay, not loss.
- **Follow-ups**
  - ADR-0006: consumers set the tenant context from `tenant_id` before handling.
  - ADR-0008: pick the RabbitMQ client library and outbox implementation for the chosen
    stack.
  - ADR-0009: tests for idempotency, retry-to-DLQ and outbox-relay recovery.
  - ADR-0011: host RabbitMQ on the dedicated server, with backups and monitoring.
  - M1: build the outbox relay and the DLQ admin tool.

## References

- ADR-0001 Product Separation
- ADR-0003 Module Contracts
- ADR-0004 Event Taxonomy
- ADR-0006 Tenant Isolation
- ADR-0011 Cloud Platform (A-016)
