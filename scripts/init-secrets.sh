#!/usr/bin/env bash
# Generate Docker file-secrets if absent. Idempotent - safe to re-run.
# Secrets are written WITHOUT a trailing newline so the value read by n8n /
# Postgres matches exactly.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mkdir -p secrets && chmod 700 secrets
[ -f secrets/n8n_encryption_key.txt ]         || openssl rand -hex 32 | tr -d '\n' > secrets/n8n_encryption_key.txt
[ -f secrets/postgres_password.txt ]          || openssl rand -base64 36 | tr -d '\n' > secrets/postgres_password.txt
[ -f secrets/postgres_non_root_password.txt ] || openssl rand -base64 36 | tr -d '\n' > secrets/postgres_non_root_password.txt
# Files 0444 (not 600): each secret is bind-mounted to /run/secrets/<name> and must
# be readable by the NON-root container user that consumes it (n8n runs as 'node',
# UID 1000). The secrets/ dir stays 700 so the host is still locked down while Docker
# (root) mounts the files directly. 600 here crash-loops n8n with EACCES.
chmod 0444 secrets/*.txt

echo "secrets ready."
echo "IMPORTANT: back up secrets/n8n_encryption_key.txt securely & separately - it is UNRECOVERABLE."
