#!/usr/bin/env bash
# Deploys one image tag on the staging app server (M1-FOU-012).
# Run by the "Deploy staging" GitHub workflow through AWS SSM; never by hand in normal use.
#
#   deploy.sh <image-tag>
#
# Steps: log in to ECR -> write app.env from Secrets Manager -> bootstrap DB roles ->
# run migrations -> start containers -> wait until /health/ready is ok (else exit 1).
set -euo pipefail

TAG="${1:?usage: deploy.sh <image-tag>}"
DIR=/opt/varanasi
# shellcheck source=/dev/null
source "$DIR/infra.env"   # written by Terraform user_data: region, registry, RDS host, …

export IMAGE_TAG="$TAG" ECR_REGISTRY
COMPOSE=(docker compose -f "$DIR/compose.staging.yml")
log() { echo "[deploy $(date -u +%H:%M:%S)] $*"; }

log "Deploying $TAG"
aws ecr get-login-password --region "$AWS_REGION" |
  docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null

log "Writing app.env from Secrets Manager"
app_secret=$(aws secretsmanager get-secret-value --region "$AWS_REGION" \
  --secret-id "$APP_SECRET_ARN" --query SecretString --output text)
pw() { jq -r --arg k "$1_password" '.[$k]' <<<"$app_secret"; }
db_url() { echo "postgresql://varanasi_$1:$2@$DB_HOST:5432/$DB_NAME?sslmode=require"; }

umask 077
cat > "$DIR/app.env" <<EOF
VARANASI_ENV=staging
VARANASI_LOG_LEVEL=INFO
VARANASI_LOG_FORMAT=json
VARANASI_DB_MIGRATOR_URL=$(db_url migrator "$(pw migrator)")
VARANASI_DB_PLATFORM_URL=$(db_url platform_app "$(pw platform)")
VARANASI_DB_BILLING_URL=$(db_url billing_app "$(pw billing)")
VARANASI_DB_HRMS_URL=$(db_url hrms_app "$(pw hrms)")
VARANASI_REDIS_URL=redis://redis:6379/0
VARANASI_STORAGE_BUCKET=$FILES_BUCKET
VARANASI_STORAGE_REGION=$AWS_REGION
VARANASI_CORS_ALLOWED_ORIGINS=$PUBLIC_ORIGIN
EOF

log "Bootstrapping database roles"
master=$(aws secretsmanager get-secret-value --region "$AWS_REGION" \
  --secret-id "$DB_MASTER_SECRET_ARN" --query SecretString --output text)
docker run --rm -i \
  -e PGHOST="$DB_HOST" -e PGDATABASE="$DB_NAME" -e PGSSLMODE=require \
  -e PGUSER="$(jq -r .username <<<"$master")" \
  -e PGPASSWORD="$(jq -r .password <<<"$master")" \
  postgres:17.11 psql -q \
  -v migrator_pw="$(pw migrator)" -v platform_pw="$(pw platform)" \
  -v billing_pw="$(pw billing)" -v hrms_pw="$(pw hrms)" -v dbname="$DB_NAME" \
  -f - < "$DIR/bootstrap.sql"

log "Pulling images"
"${COMPOSE[@]}" --profile migrate pull --quiet

log "Running migrations"
"${COMPOSE[@]}" --profile migrate run --rm migrate

log "Starting containers"
"${COMPOSE[@]}" up -d --remove-orphans --wait --wait-timeout 120

log "Checking readiness"
for _ in $(seq 1 30); do
  if body=$(curl -fsS http://127.0.0.1/health/ready 2>/dev/null); then
    log "Ready: $body"
    docker image prune -af --filter "until=168h" >/dev/null || true
    log "Deployed $TAG"
    exit 0
  fi
  sleep 2
done

log "Readiness check failed"
curl -sS http://127.0.0.1/health/ready || true
"${COMPOSE[@]}" logs --tail 50 backend
exit 1
