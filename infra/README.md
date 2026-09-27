# infra/

**Owner:** Platform/DevOps (`@varanasi/devops`). Architecture reviewers must approve changes (ADR-0010 §4).

| Path | What |
|------|------|
| [`postgres/init/`](postgres/init/) | Creates the ADR-0006 database roles in the local dev database |
| [`web/`](web/) | nginx image serving the three Flutter web apps and proxying the API (staging) |
| [`staging/`](staging/) | Docker Compose file + deploy script run on the staging server |
| [`terraform/staging/`](terraform/staging/) | AWS staging environment in `ap-south-1` (ADR-0011) |

Deploying to staging: see [`docs/runbooks/staging-deploy.md`](../docs/runbooks/staging-deploy.md).
