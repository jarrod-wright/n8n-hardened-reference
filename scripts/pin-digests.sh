#!/usr/bin/env bash
# Pull the pinned images and print their sha256 digests, so you can replace
# 'repo:tag' with 'repo:tag@sha256:...' in docker-compose*.yml for immutability.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

IMAGES=(
  caddy:2-alpine
  docker.n8n.io/n8nio/n8n:2.29.10
  postgres:16-alpine
  redis:7-alpine
  n8nio/runners:2.29.10
)

for img in "${IMAGES[@]}"; do
  docker pull -q "$img" >/dev/null 2>&1 || true
  digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "$img" 2>/dev/null || echo '(pull failed)')"
  printf '%-42s %s\n' "$img" "$digest"
done
