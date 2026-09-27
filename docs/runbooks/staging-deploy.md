# Runbook: staging environment and deploys

Staging lives in AWS `ap-south-1` (ADR-0011). Topology: see ADR-0012 §7.

## One-time setup

**Prerequisites:**
- an AWS account for staging (ADR-0011 accounts);
- an admin who can run Terraform;
- the GitHub repository already set up (see `github-setup.md`).

1. **Terraform state bucket.** Create an S3 bucket
   `varanasi-terraform-state-<account-id>` in `ap-south-1` with versioning on.
2. **Apply the staging stack:**

   ```bash
   cd infra/terraform/staging
   cp backend.hcl.example backend.hcl        # fill in the bucket name
   terraform init -backend-config=backend.hcl
   terraform apply -var github_repository=<owner>/project-varanasi
   #   optional HTTPS: -var domain_name=staging.example.com -var route53_zone_id=Z123…
   terraform output github_variables
   ```

3. **GitHub environment.** In GitHub, go to **Settings → Environments → New
   environment**, name it `staging`, and add **variables** (not secrets) with the six
   values from `terraform output github_variables`:
   - `AWS_REGION`
   - `AWS_DEPLOY_ROLE_ARN`
   - `ECR_REGISTRY`
   - `STAGING_INSTANCE_ID`
   - `STAGING_DEPLOY_BUCKET`
   - `STAGING_URL`

   No AWS keys are stored in GitHub. The workflow assumes the deploy role through OIDC,
   and only for `v*` tags.

## Deploy (M1-FOU-012)

```bash
git switch main && git pull
git tag v0.1.0
git push origin v0.1.0
```

The **Deploy staging** workflow then:

1. runs the full CI;
2. builds the arm64 `varanasi-backend` and `varanasi-web` images and pushes them to ECR;
3. uploads `compose.staging.yml`, `deploy.sh` and `bootstrap.sql` to the deploy bucket;
4. runs `deploy.sh v0.1.0` on the app server via SSM, which:
   - writes `app.env` from Secrets Manager;
   - bootstraps the DB roles;
   - runs migrations for all three modules;
   - starts the containers;
   - checks that `/health/ready` is `ok`;
5. smoke-tests `/health`, `/health/ready`, `/platform/`, `/billing/` and `/hrms/` through
   the load balancer.

The deploy fails, and the previous containers keep running, if migrations fail. If the
readiness check fails, the job goes red and prints the backend logs.

**Nothing is run by hand on the server.**

## Rollback

Re-run the **Deploy staging** workflow for the previous tag: **Actions → Deploy staging →
the older run → Re-run all jobs**. Migrations are forward-only (ADR-0008 §5), so a
rollback that needs a schema change requires a new forward migration.

## Troubleshooting

- **Server shell:** AWS Console → Systems Manager → Session Manager → `varanasi-staging-app`
  (no SSH exists).
- **Logs:** `sudo docker compose -f /opt/varanasi/compose.staging.yml logs -f backend`
- **App config:** `/opt/varanasi/app.env` (root-only, generated on every deploy; do not edit).
