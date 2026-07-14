#!/bin/bash
# =============================================================================
# postgres/init-data.sh
#
# Creates a NON-ROOT PostgreSQL user for n8n so the application never connects
# as the superuser. Runs ONCE, on first cluster init, via the official Postgres
# image's /docker-entrypoint-initdb.d hook.
#
# Written to be safe whether the entrypoint executes OR sources this file
# (no `set -e`; psql fails hard via ON_ERROR_STOP=1).
#
# NOTE: make this file executable before deploy:  chmod +x postgres/init-data.sh
#       (`make deploy` does this for you.)
# =============================================================================

if [ -n "${POSTGRES_NON_ROOT_USER:-}" ] && [ -n "${POSTGRES_NON_ROOT_PASSWORD_FILE:-}" ]; then
  NON_ROOT_PW="$(cat "${POSTGRES_NON_ROOT_PASSWORD_FILE}")"
  psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<EOSQL
CREATE USER "${POSTGRES_NON_ROOT_USER}" WITH PASSWORD '${NON_ROOT_PW}';
GRANT ALL PRIVILEGES ON DATABASE "${POSTGRES_DB}" TO "${POSTGRES_NON_ROOT_USER}";
ALTER DATABASE "${POSTGRES_DB}" OWNER TO "${POSTGRES_NON_ROOT_USER}";
GRANT ALL ON SCHEMA public TO "${POSTGRES_NON_ROOT_USER}";
EOSQL
  echo "init-data: created non-root user '${POSTGRES_NON_ROOT_USER}' and assigned DB ownership."
else
  echo "init-data: POSTGRES_NON_ROOT_USER / _PASSWORD_FILE not set; skipping non-root user creation." >&2
fi
