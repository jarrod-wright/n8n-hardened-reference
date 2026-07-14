#!/usr/bin/env bash
# Generate Docker file-secrets if absent. Idempotent - safe to re-run.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mkdir -p secrets
[ -f secrets/n8n_encryption_key.txt ]         || openssl rand -hex 32 > secrets/n8n_encryption_key.txt
[ -f secrets/postgres_password.txt ]          || openssl rand -base64 36 | tr -d '\n' > secrets/postgres_password.txt
[ -f secrets/postgres_non_root_password.txt ] || openssl rand -base64 36 | tr -d '\n' > secrets/postgres_non_root_password.txt
chmod 600 secrets/*.txt

echo "secrets ready."
echo "IMPORTANT: back up secrets/n8n_encryption_key.txt securely & separately - it is UNRECOVERABLE."
