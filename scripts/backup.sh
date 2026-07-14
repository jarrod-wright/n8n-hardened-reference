#!/usr/bin/env bash
# Backup: PostgreSQL custom-format dump + n8n data directory.
#
# The n8n ENCRYPTION KEY (secrets/n8n_encryption_key.txt) is required to decrypt
# restored credentials and MUST be backed up separately + securely. It is
# intentionally NOT bundled into these archives.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

set -a; [ -f .env ] && . ./.env; set +a
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"
RETENTION="${BACKUP_RETENTION:-7}"

TS="$(date -u +%Y%m%d-%H%M%S)"
OUT="backups/${TS}"
mkdir -p "$OUT"

echo "[backup] pg_dump ${POSTGRES_DB} (custom format) ..."
docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB" > "${OUT}/n8n-db-${TS}.dump"

echo "[backup] copying n8n data directory ..."
docker compose cp n8n:/home/node/.n8n "${OUT}/n8n-data" >/dev/null
tar czf "${OUT}/n8n-data-${TS}.tar.gz" -C "${OUT}/n8n-data" .
rm -rf "${OUT}/n8n-data"

echo "[backup] complete -> ${OUT}"
echo "[backup] REMINDER: also back up secrets/n8n_encryption_key.txt (UNRECOVERABLE)."

# Retention: keep only the newest N backup directories.
ls -1dt backups/*/ 2>/dev/null | tail -n +"$((RETENTION + 1))" | xargs -r rm -rf || true
echo "[backup] retention: kept newest ${RETENTION}."
