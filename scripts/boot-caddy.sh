#!/usr/bin/env bash
# boot-caddy: boot the FULL stack including Caddy, with an internally-signed
# certificate, and prove HTTPS end to end.
#
#   scripts/boot-caddy.sh
#
# The shipped Caddyfile terminates TLS with automatic public certificates,
# which need public DNS pointing at the host — unavailable on a CI runner or
# a laptop. This boot test copies the stack to a temp directory and rewrites
# ONLY the copy's Caddyfile: the site address becomes `localhost` and the
# certificate mode becomes `tls internal` (Caddy's own local CA). Everything
# else — the reverse proxy, the headers, the request-size guard — is the
# shipped file, unmodified. The shipped Caddyfile is never touched.
#
# The test then:
#   1. docker compose up -d --wait (postgres, redis, n8n, n8n-worker, caddy)
#   2. polls https://localhost/healthz/readiness through Caddy until 200
#      (TLS terminated by Caddy with its internal CA; curl -k accepts it)
#   3. asserts the response carries the Caddyfile's HSTS header, so the reply
#      provably went through the proxy rather than straight to n8n
#   4. asserts no container restarted during the boot
# It always runs `docker compose down -v` and deletes the temp directory,
# also on failure.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(cd "${STACK_DIR:-$here/..}" && pwd)"
# shellcheck source=scripts/lib-throwaway.sh
. "$here/lib-throwaway.sh"

timeout="${SMOKE_TIMEOUT:-180}"

work="$(mktemp -d)"
project="n8n-boot-caddy-$$"
trap 'docker compose --project-directory "$work" -f "$work/docker-compose.yml" down -v --remove-orphans > /dev/null 2>&1 || true; rm -rf "$work"' EXIT

throwaway_copy "$src" "$work"

# The single Caddyfile rewrite: site address + internal certificate.
sed -i 's|^{$N8N_HOST} {$|localhost {\n\ttls internal|' "$work/Caddyfile"
grep -q 'tls internal' "$work/Caddyfile" || { echo "boot-caddy: FAIL: the Caddyfile rewrite did not take" >&2; exit 1; }

echo "boot-caddy: booting the full stack (postgres, redis, n8n, n8n-worker, caddy)"
t0=$(date +%s)
docker compose --project-directory "$work" -f "$work/docker-compose.yml" up -d --wait \
  postgres redis n8n n8n-worker caddy > /dev/null

# Poll readiness THROUGH Caddy over TLS.
url="https://localhost/healthz/readiness"
status=""
elapsed=0
while [ "$elapsed" -lt "$timeout" ]; do
  status="$(curl -sk --max-time 5 -o /dev/null -w '%{http_code}' "$url" || true)"
  [ "$status" = "200" ] && break
  sleep 3
  elapsed=$(( $(date +%s) - t0 ))
done
if [ "$status" != "200" ]; then
  echo "boot-caddy: FAIL: readiness over https://localhost not 200 within ${timeout}s (last: ${status:-none})" >&2
  docker compose --project-directory "$work" -f "$work/docker-compose.yml" ps -a || true
  docker compose --project-directory "$work" -f "$work/docker-compose.yml" logs --no-color --tail 60 caddy n8n || true
  exit 1
fi
echo "boot-caddy: PASS  readiness 200 over TLS through Caddy (after ${elapsed}s)"

# The reply must carry the Caddyfile's HSTS header — proof it went through
# the proxy, not straight to n8n's port.
if curl -skI "$url" | grep -qi '^strict-transport-security:'; then
  echo "boot-caddy: PASS  HSTS header present (reply came through Caddy)"
else
  echo "boot-caddy: FAIL: no HSTS header — the reply did not come through Caddy" >&2
  exit 1
fi

# No container may have restarted during the boot.
bad=""
for id in $(docker compose --project-directory "$work" -f "$work/docker-compose.yml" ps -q); do
  name="$(docker inspect --format '{{.Name}}' "$id")"
  count="$(docker inspect --format '{{.RestartCount}}' "$id")"
  [ "$count" = "0" ] || bad="$bad $name(restarts=$count)"
done
if [ -n "$bad" ]; then
  echo "boot-caddy: FAIL: containers restarted during boot:$bad" >&2
  exit 1
fi
echo "boot-caddy: PASS  no container restarted"
echo "boot-caddy: OK — full stack boots and serves n8n over internally-signed TLS"
