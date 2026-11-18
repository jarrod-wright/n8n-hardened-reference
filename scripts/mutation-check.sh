#!/usr/bin/env bash
# mutation-check: prove `make verify` catches real regressions, not just a
# green file. A verification suite that cannot fail is decoration, so this
# script applies deliberate regressions to throwaway copies of the stack and
# requires `verify` to FAIL on each one, naming the right assertion. Finally
# it runs `verify` over an unmutated copy — the positive control that shows
# the failures above came from the mutations, not from the harness.
#
#   scripts/mutation-check.sh
#
# Every mutation runs against its own temp copy; the source checkout and the
# shipped compose files are never touched. Exits non-zero if any mutation
# survives (verify stays green) or if the positive control fails.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(cd "${STACK_DIR:-$here/..}" && pwd)"
# shellcheck source=scripts/lib-throwaway.sh
. "$here/lib-throwaway.sh"

failures=0
run_mutation() {
  local name="$1" expect="$2" sedexpr="$3" work out
  work="$(mktemp -d)"
  throwaway_copy "$src" "$work"
  sed -i "$sedexpr" "$work/docker-compose.yml"
  if out="$(bash "$here/verify.sh" "$work" 2>&1)"; then
    echo "mutation-check: FAIL  $name — verify stayed GREEN on a regressed stack"
    failures=$((failures + 1))
  elif printf '%s' "$out" | grep -q "$expect"; then
    printf 'mutation-check: PASS  %-38s caught: %s\n' "$name" "$(printf '%s' "$out" | grep "$expect" | head -1 | cut -c1-80)"
  else
    echo "mutation-check: FAIL  $name — verify failed, but not with the expected assertion ($expect)"
    printf '%s\n' "$out" | grep FAIL | head -3
    failures=$((failures + 1))
  fi
  rm -rf "$work"
}

# 1. A second service publishes a host port (F1: only caddy may publish).
run_mutation "n8n publishes a host port" "FAIL" \
  's|^  n8n-worker:$|    ports:\n      - "127.0.0.1:5678:5678"\n  n8n-worker:|'

# 2. The n8n image loses its sha256 digest (F2: every image digest-pinned).
run_mutation "n8n image loses its digest" "FAIL" \
  's|image: \(docker.n8n.io/n8nio/n8n:[0-9.]*\)@sha256:[0-9a-f]*|image: \1|'

# 3. The n8n service drops cap_drop ALL (F4: least-privilege containers).
run_mutation "n8n drops cap_drop ALL" "FAIL" \
  '/^  n8n:$/,/^  n8n-worker:$/ { /^    cap_drop:$/d; /^      - ALL$/d; }'

# 4. Code nodes can read the environment again (F7: env access blocked).
run_mutation "env access unblocked in Code nodes" "FAIL" \
  's|N8N_BLOCK_ENV_ACCESS_IN_NODE: "true"|N8N_BLOCK_ENV_ACCESS_IN_NODE: "false"|'

# 5. n8n connects to PostgreSQL as the superuser (F8: non-root DB user).
run_mutation "n8n connects as the DB superuser" "FAIL" \
  's|DB_POSTGRESDB_USER: .*|DB_POSTGRESDB_USER: postgres|'

# Positive control: the unmutated stack must pass.
work="$(mktemp -d)"
throwaway_copy "$src" "$work"
if out="$(bash "$here/verify.sh" "$work" 2>&1)" && printf '%s' "$out" | grep -q "passed"; then
  printf 'mutation-check: PASS  %-38s verify green on the clean stack\n' "positive control (no mutation)"
else
  echo "mutation-check: FAIL  positive control — verify is red on an UNMUTATED stack:"
  printf '%s\n' "$out" | tail -3
  failures=$((failures + 1))
fi
rm -rf "$work"

if [ "$failures" -gt 0 ]; then
  echo "mutation-check: $failures mutation(s) survived — the verification suite has a hole"
  exit 1
fi
echo "mutation-check: OK — every regression is caught, the clean stack stays green"
