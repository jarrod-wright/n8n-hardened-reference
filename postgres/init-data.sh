#!/bin/bash
# =============================================================================
# postgres/init-data.sh
#
# Creates a NON-ROOT PostgreSQL user for n8n so the application never connects
# as the superuser. Runs ONCE, on first cluster init, via the official Postgres
# image's /docker-entrypoint-initdb.d hook.
#
# The user name, password and database are passed to psql as bound variables
# (-v), so the password is never string-interpolated into the SQL text.
#
# Written to be safe whether the entrypoint executes OR sources this file
# (no `set -e`; psql fails hard via ON_ERROR_STOP=1).
#
# NOTE: make this file executable before deploy:  chmod +x postgres/init-data.sh
#       (`make deploy` does this for you.)
# =============================================================================

if [ -n "${POSTGRES_NON_ROOT_USER:-}" ] && [ -n "${POSTGRES_NON_ROOT_PASSWORD_FILE:-}" ]; then
  NON_ROOT_PW="$(cat "${POSTGRES_NON_ROOT_PASSWORD_FILE}")"
  psql -v ON_ERROR_STOP=1 \
    --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" \
    -v nonroot_user="${POSTGRES_NON_ROOT_USER}" \
    -v nonroot_pw="${NON_ROOT_PW}" \
    -v dbname="${POSTGRES_DB}" <<'EOSQL'
CREATE USER :"nonroot_user" WITH PASSWORD :'nonroot_pw';
GRANT ALL PRIVILEGES ON DATABASE :"dbname" TO :"nonroot_user";
ALTER DATABASE :"dbname" OWNER TO :"nonroot_user";
GRANT ALL ON SCHEMA public TO :"nonroot_user";
EOSQL
  echo "init-data: created non-root user '${POSTGRES_NON_ROOT_USER}' and assigned DB ownership."
else
  echo "init-data: POSTGRES_NON_ROOT_USER / _PASSWORD_FILE not set; skipping non-root user creation." >&2
fi
