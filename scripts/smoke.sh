#!/usr/bin/env bash
# make smoke: boot the stack on throwaway secrets and wait for n8n to be ready.
#
#   scripts/smoke.sh [base|runners ...]      (default: base, then runners)
#
# For each configuration it copies the stack to a temp directory with a
# throwaway .env and secrets, then:
#   1. docker compose up -d --wait postgres redis n8n n8n-worker
#      (plus n8n-runner and n8n-worker-runner for the runners overlay).
#      Caddy is left out: it needs public DNS to obtain a certificate.
#   2. Polls GET http://localhost:5678/healthz/readiness from inside the n8n
#      container until it returns 200, up to SMOKE_TIMEOUT seconds (default
#      180) counted from the start of `up`.
#   3. Checks that `n8n --version` inside the container equals the pinned
#      image tag, and that no container has restarted.
# It always runs `docker compose down -v` and deletes the temp directory, also
# on failure. Set STACK_DIR to smoke-test a modified copy of the stack.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(cd "${STACK_DIR:-$here/..}" && pwd)"
# shellcheck source=scripts/lib-throwaway.sh
. "$here/lib-throwaway.sh"

timeout="${SMOKE_TIMEOUT:-180}"
[ $# -gt 0 ] || set -- base runners

cur_dir=""
cur_config=""
cur_project=""

sc() { stack_compose "$cur_dir" "$cur_config" -p "$cur_project" "$@"; }

teardown() {
  if [ -n "$cur_dir" ]; then
    sc down -v --remove-orphans > /dev/null 2>&1 || true
    rm -rf "$cur_dir"
  fi
  cur_dir=""
}
trap teardown EXIT

fail() {
  echo "smoke[$cur_config]: FAIL: $*"
  sc ps -a || true
  sc logs --no-color --tail 60 || true
  exit 1
}

smoke_one() {
  local services want t0 now elapsed status got restarts
  cur_config="$1"
  cur_project="n8n-smoke-$1-$$"
  cur_dir="$(mktemp -d)"
  throwaway_copy "$src" "$cur_dir"

  services=(postgres redis n8n n8n-worker)
  if [ "$cur_config" = runners ]; then
    services+=(n8n-runner n8n-worker-runner)
  fi
  want="$(sc config --format json | jq -r '.services.n8n.image | sub("@.*$"; "") | sub("^.*:"; "")')"

  echo "smoke[$cur_config]: up -d --wait ${services[*]}"
  t0="$(date +%s)"
  sc up -d --quiet-pull --wait --wait-timeout "$timeout" "${services[@]}" ||
    fail "services did not become running/healthy within ${timeout}s"

  while :; do
    status="$(sc exec -T n8n node -e '
      fetch("http://localhost:5678/healthz/readiness")
        .then((r) => console.log(r.status))
        .catch((e) => console.log((e.cause && e.cause.code) || e.message))' 2>&1 | tail -n 1 || true)"
    now="$(date +%s)"
    elapsed=$((now - t0))
    [ "$status" = 200 ] && break
    [ "$elapsed" -lt "$timeout" ] ||
      fail "GET /healthz/readiness did not return 200 within ${timeout}s (last: ${status:-no answer})"
    sleep 2
  done
  echo "smoke[$cur_config]: GET /healthz/readiness -> 200 after ${elapsed}s"

  got="$(sc exec -T n8n n8n --version 2>/dev/null | tr -d '\r' | tail -n 1)"
  echo "smoke[$cur_config]: n8n --version -> $got (pinned tag $want)"
  [ "$got" = "$want" ] || fail "n8n --version is '$got', expected '$want'"

  restarts="$(sc ps -aq | xargs docker inspect -f '{{.Name}} {{.State.Status}} restarts={{.RestartCount}}' | sed 's#^/##')"
  printf '%s\n' "$restarts" | sed "s/^/smoke[$cur_config]:   /"
  if printf '%s\n' "$restarts" | grep -qvE ' running restarts=0$'; then
    fail "a container is not running or has restarted"
  fi

  echo "smoke[$cur_config]: PASS"
  teardown
}

for config in "$@"; do
  case "$config" in
    base | runners) smoke_one "$config" ;;
    *) echo "smoke: unknown config '$config' (expected base or runners)" >&2; exit 2 ;;
  esac
done
echo "smoke: passed ($*)"
