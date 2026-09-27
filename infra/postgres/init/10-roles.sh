#!/usr/bin/env bash
# Creates the database roles from ADR-0006 on first start of the LOCAL dev database.
# (In AWS the same roles are created by infra/terraform + infra/postgres/bootstrap.sql.)
#
#   varanasi_migrator        owns the module schemas; runs Alembic only
#   varanasi_<module>_app    runtime role per module; no superuser, no BYPASSRLS, owns nothing
set -euo pipefail

: "${VARANASI_DB_MIGRATOR_PASSWORD:?set in .env}"
: "${VARANASI_DB_PLATFORM_PASSWORD:?set in .env}"
: "${VARANASI_DB_BILLING_PASSWORD:?set in .env}"
: "${VARANASI_DB_HRMS_PASSWORD:?set in .env}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v migrator_pw="$VARANASI_DB_MIGRATOR_PASSWORD" \
  -v platform_pw="$VARANASI_DB_PLATFORM_PASSWORD" \
  -v billing_pw="$VARANASI_DB_BILLING_PASSWORD" \
  -v hrms_pw="$VARANASI_DB_HRMS_PASSWORD" \
  -v dbname="$POSTGRES_DB" \
  -f /docker-entrypoint-initdb.d/roles.sql.tpl
