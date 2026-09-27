-- Database roles (ADR-0003, ADR-0006). Run with psql variables:
--   migrator_pw, platform_pw, billing_pw, hrms_pw, dbname
-- Shared by the local dev container (10-roles.sh) and the test suite.
-- The .tpl suffix stops the postgres image from running it directly.

CREATE ROLE varanasi_migrator LOGIN PASSWORD :'migrator_pw' NOSUPERUSER NOBYPASSRLS;
CREATE ROLE varanasi_platform_app LOGIN PASSWORD :'platform_pw' NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
CREATE ROLE varanasi_billing_app LOGIN PASSWORD :'billing_pw' NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
CREATE ROLE varanasi_hrms_app LOGIN PASSWORD :'hrms_pw' NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;

-- The migrator creates the module schemas (and the alembic_version_* tables in public).
GRANT CREATE ON DATABASE :"dbname" TO varanasi_migrator;
GRANT CREATE ON SCHEMA public TO varanasi_migrator;
