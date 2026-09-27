-- Idempotent database-role bootstrap for RDS (ADR-0006). Safe to run on every deploy.
-- Run with psql as the RDS master user and these variables:
--   migrator_pw, platform_pw, billing_pw, hrms_pw, dbname
-- (Local dev uses infra/postgres/init/roles.sql.tpl, which runs once on an empty volume.)
\set ON_ERROR_STOP on

SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE', r)
FROM unnest(ARRAY['varanasi_migrator', 'varanasi_platform_app',
                  'varanasi_billing_app', 'varanasi_hrms_app']) AS r
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r)
\gexec

-- Passwords are (re)applied every time so rotating them in Secrets Manager just works.
ALTER ROLE varanasi_migrator PASSWORD :'migrator_pw';
ALTER ROLE varanasi_platform_app PASSWORD :'platform_pw';
ALTER ROLE varanasi_billing_app PASSWORD :'billing_pw';
ALTER ROLE varanasi_hrms_app PASSWORD :'hrms_pw';

GRANT CREATE ON DATABASE :"dbname" TO varanasi_migrator;
GRANT CREATE ON SCHEMA public TO varanasi_migrator;
