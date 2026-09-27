# ADR-0011: Cloud Platform (A-016)

- **Status:** Accepted. **FROZEN (A-016)**
- **Date:** 2026-09-27
- **Milestone:** M0. Frozen before M0 exit
- **Decision ID:** A-016
- **Deciders:** Project owner (see `docs/architecture/M0-APPROVAL.md`)
- **Supersedes / Superseded by:** — (hosting details amended by ADR-0012 §7)

> **Freeze rule:** the cloud provider and primary region are frozen. Changing either one
> requires a new ADR that supersedes this one and an architecture review (ADR-0010).
> Items marked *adjustable* below (instance sizes, retention numbers) can be tuned
> without a new ADR.

## Context

Earlier ADRs already fix the shape of the system:

| Already decided | Source |
|-----------------|--------|
| One modular application on a **dedicated server** | ADR-0001 |
| **PostgreSQL**, one database, a schema per module, RLS | ADR-0003, ADR-0006 |
| **RabbitMQ 4.x** as a container next to the app, with an outbox | ADR-0005 |
| An external payment provider for SaaS subscriptions (e.g. Razorpay) | ADR-0001 |
| Enterprise **dedicated deployments**, possibly with data-residency needs | ADR-0006 |
| Secrets passed to the app as files; a staging env for nightly security scans | ADR-0008, ADR-0009 |

The product targets **Indian businesses**: INR, GST tax codes, PAN/Aadhaar in HR data,
Indian payment providers. HRMS holds sensitive personal and salary data. India's
**Digital Personal Data Protection Act, 2023** (DPDP Act) and customer expectations make
**keeping data in India** the safe default.

## Decision drivers

| Driver | Weight | Notes |
|--------|--------|-------|
| **Data residency in India** | Must | Primary data *and* backups stay in India |
| A disaster-recovery copy in a **second Indian region** | Must | So backups survive a region-wide outage without leaving India |
| **Managed PostgreSQL** with point-in-time restore, custom roles and RLS | Must | ADR-0006 depends on custom roles with no `BYPASSRLS` |
| Low latency for Indian users | High | |
| Small-team friendliness: documentation, hiring pool, mature Terraform support | High | |
| Cost for a single-server start | High | |
| Separate accounts for dedicated tenants | Medium | ADR-0006 |

## Options considered

| Option | Indian regions | Managed PostgreSQL | Fit | Verdict |
|--------|----------------|--------------------|-----|---------|
| **AWS** | **Mumbai (`ap-south-1`)** + **Hyderabad (`ap-south-2`)** | RDS for PostgreSQL: PITR, cross-region backup copy, custom roles, RLS | The largest ecosystem and hiring pool, the most mature Terraform provider, AWS Organizations for per-tenant accounts, and an Indian billing entity | ✅ **Chosen** |
| Azure | Central India (Pune), South India (Chennai), West India (Mumbai) | Azure Database for PostgreSQL Flexible Server | Strong, especially for Microsoft-centric enterprises. A smaller Python/startup community and a less familiar Terraform setup for this team | Rejected (a close second) |
| GCP | Mumbai (`asia-south1`), Delhi (`asia-south2`) | Cloud SQL for PostgreSQL | Good, but the enterprise customer base in India and the hiring pool are smaller | Rejected |
| An Indian VPS / bare-metal host | Various | Usually self-managed | Cheapest, but we'd run backups, PITR, failover and security ourselves | Rejected: too much operations work for a small team |

## Decision

> **Cloud provider: Amazon Web Services (AWS)**
>
> **Primary region: Asia Pacific (Mumbai), `ap-south-1`**
>
> **Disaster-recovery / backup region: Asia Pacific (Hyderabad), `ap-south-2`**
>
> **All customer data, including backups, stays in India.**

### Baseline hosting

| Component | Choice | Notes |
|-----------|--------|-------|
| **Application server** ("dedicated server", ADR-0001) | **One Amazon EC2 instance** in `ap-south-1`, running the app, the outbox relay and **RabbitMQ** as Docker containers (Docker Compose) | Starting size: `m7g.xlarge` (4 vCPU, 16 GB, Graviton/ARM). *Adjustable* after load testing. EBS `gp3`, encrypted |
| **PostgreSQL** | **Amazon RDS for PostgreSQL**, current major version (17 at the time of writing), Single-AZ at launch | Kept **off** the app server, so a server failure can't take the data with it. Starting size `db.m7g.large`. *Adjustable.* Multi-AZ is enabled before GA or on the first enterprise contract |
| **RabbitMQ** | Self-hosted container on the app server (ADR-0005) | Definitions come from `deploy/rabbitmq/definitions.json`. Amazon MQ is kept as an option if we move off the single server |
| **Load balancer / TLS** | **Application Load Balancer** + **ACM** certificates | TLS terminates at the ALB, and health checks live there. The ALB makes it easy to add more servers later |
| **DNS** | **Route 53** | |
| **Object storage** (files, exports, ADR-0006 `tenants/{tenant_id}/…`) | **Amazon S3** in `ap-south-1`: SSE-KMS encryption, versioning on, public access blocked | |
| **Container registry** | **Amazon ECR** | The same image is used for E2E, staging and production (ADR-0009) |
| **Secrets** | **AWS Secrets Manager** | Fetched at deploy time and mounted as files under `/run/secrets/` (ADR-0008 `_FILE` variables) |
| **Encryption keys** | **AWS KMS**, customer-managed keys per environment | Used by RDS, EBS, S3 and Secrets Manager |
| **Email** | **Amazon SES** (`ap-south-1`) | Notifications, invites |
| **Logs & metrics** | **CloudWatch Logs** (JSON logs from stdout, ADR-0008 §11) + **CloudWatch Agent** scraping the Prometheus metrics (app + RabbitMQ) + **CloudWatch Alarms** → email/Slack | Alarms for the ADR-0005 alerts (DLQ > 0, outbox backlog, and so on) |
| **Infrastructure as Code** | **Terraform** (or the compatible OpenTofu), state in S3 with locking | Nothing is created by hand in the console |
| **CI/CD** | GitHub Actions → ECR → deploy to EC2 through **SSM** (no SSH open to the internet) | |
| **Network** | One VPC per environment. Private subnets for EC2 and RDS; the ALB alone in public subnets. RDS isn't publicly reachable | Admin access through SSM Session Manager |

### Accounts and environments

- **AWS Organizations** with separate accounts:
  - `management` (billing only)
  - `production`
  - `staging`
  - (later) `security/log-archive`
- **Staging** mirrors production at a smaller size, in the same region. It runs the
  nightly OWASP ZAP scan (ADR-0009).
- **Dedicated tenants** (ADR-0006) each get **their own AWS account**, deployed from the
  same Terraform modules and the same image. They default to `ap-south-1`; another
  region only if their contract requires it.
- Root accounts have MFA and are locked away. People sign in with IAM Identity Center
  (SSO). Engineers have no long-lived access keys.

### Backup and disaster recovery

| Item | Standard |
|------|----------|
| RDS automated backups + point-in-time restore | **14 days** retention (*adjustable*) |
| Cross-region copy | RDS automated backups replicated to **`ap-south-2` (Hyderabad)** |
| S3 | Versioning + **cross-region replication to `ap-south-2`** |
| App server | Stateless apart from RabbitMQ. It's rebuilt from Terraform + the ECR image. RabbitMQ messages that aren't yet consumed can be recovered from the outbox (ADR-0005) |
| **RPO** (maximum data loss) | **≤ 15 minutes** (PITR) |
| **RTO** (time to restore service) | **≤ 4 hours** at launch; tightened when Multi-AZ is enabled |
| Restore drill | A full restore into staging **every quarter**, recorded in `docs/runbooks/` |

### Cost guardrails

- Use AWS Budgets with alerts at 50 / 80 / 100 % of the monthly budget per account.
- Tag every resource with `env`, `module` (where relevant) and `tenant` (for dedicated
  deployments).
- Savings Plans / Reserved Instances are reviewed once usage has been stable for 3
  months.

## Consequences

- **Positive**
  - Data residency in India, including backups and DR, from day one.
  - Managed PostgreSQL with PITR and cross-region backup, and all the ADR-0006 RLS and
    role features.
  - The app server is replaceable: a failure means rebuilding, not losing data.
  - A clear path to scale: add EC2 instances behind the ALB, Multi-AZ RDS, and Amazon
    MQ or a RabbitMQ cluster.
  - Per-account isolation for enterprise dedicated tenants.
- **Negative / trade-offs**
  - AWS lock-in for managed services (RDS, S3, Secrets Manager). This is kept moderate:
    the app itself only needs PostgreSQL, S3-compatible storage and RabbitMQ.
  - The ALB, RDS and NAT add a fixed monthly cost compared with a single VPS.
  - A Single-AZ database at launch means an AZ outage causes downtime (within the RTO)
    until Multi-AZ is enabled.
- **Follow-ups**
  - M1: Terraform for the `staging` and `production` accounts (VPC, EC2, RDS, ALB, S3,
    ECR, Secrets Manager, CloudWatch).
  - M1: runbooks for restore, DLQ, outbox backlog and server rebuild.
  - Before GA: enable Multi-AZ on RDS and do the first restore drill.
  - Before the first dedicated tenant: the ADR-0006 control-plane question.

## Freeze record

- **Frozen on:** 2026-09-27
- **Approved by:** see `docs/architecture/M0-APPROVAL.md`

## References

- ADR-0001 Product Separation
- ADR-0005 Event Broker
- ADR-0006 Tenant Isolation
- ADR-0008 Coding & Repository Conventions
- ADR-0009 Testing Strategy
- Digital Personal Data Protection Act, 2023 (India)
