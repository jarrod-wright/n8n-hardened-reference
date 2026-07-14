#!/usr/bin/env bash
# Restore from a backup directory produced by scripts/backup.sh.
#   Usage: scripts/restore.sh backups/<timestamp>
#
# The SAME encryption key (secrets/n8n_encryption_key.txt) that was in place when
# the backup was taken MUST be present, or restored credentials cannot be decrypted.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

[ $# -eq 1 ] || { echo "usage: $0 backups/<timestamp>"; exit 1; }
SRC="$1"

set -a; [ -f .env ] && . ./.env; set +a
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"

DUMP="$(ls "${SRC}"/n8n-db-*.dump 2>/dev/null | head -n1 || true)"
[ -n "${DUMP:-}" ] || { echo "no db dump (n8n-db-*.dump) found in ${SRC}"; exit 1; }

echo "[restore] stopping n8n + worker ..."
docker compose stop n8n n8n-worker

echo "[restore] pg_restore from ${DUMP} ..."
docker compose exec -T postgres pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists < "$DUMP"

echo "[restore] restarting n8n + worker ..."
docker compose start n8n n8n-worker
echo "[restore] done. Confirm the encryption key matches the backup source."
