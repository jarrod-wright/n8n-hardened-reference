#!/usr/bin/env bash
# make verify-selftest: prove that `make verify` can fail.
#
# Builds throwaway copies of this repository, breaks one posture property in
# each copy, and runs scripts/verify.sh on it. A case passes only when verify
# exits non-zero AND the failing assertion is exactly the one that guards the
# broken property. An unmodified copy must pass verify. A check that cannot
# fail proves nothing, so every assertion in verify has a case here.
#
# Needs the same tools as verify: bash, the docker compose v2 CLI, jq, openssl.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
# shellcheck source=scripts/lib-throwaway.sh
. "$here/lib-throwaway.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# rewrite FILE COMMAND...   Filter FILE through COMMAND in place (portable, no sed -i).
rewrite() {
  local f="$1"
  shift
  "$@" < "$f" > "$f.new" && mv "$f.new" "$f"
}

# --- Mutations: each takes a stack directory and breaks one property. -------

# Assertion 1: a second service publishes a port.
publish_n8n_port() {
  rewrite "$1/docker-compose.yml" awk '
    { print }
    $0 == "  n8n:" { print "    ports:"; print "      - \"5678:5678\"" }'
}

# Assertion 2: an image reference has no digest.
strip_redis_digest() {
  rewrite "$1/docker-compose.yml" sed -E 's#^(    image: redis:[^@]+)@sha256:[0-9a-f]{64}#\1#'
}

# Assertion 3: n8n and the runners carry different version tags.
runners_previous_patch() {
  local f="$1/docker-compose.runners.yml" v ma mi pa prev
  v="$(sed -nE 's#^ *image: n8nio/runners:([0-9]+\.[0-9]+\.[0-9]+)@.*#\1#p' "$f" | head -n 1)"
  [ -n "$v" ] || { echo "no n8nio/runners:X.Y.Z image found in $f" >&2; return 1; }
  IFS=. read -r ma mi pa <<< "$v"
  if [ "$pa" -gt 0 ]; then prev="$ma.$mi.$((pa - 1))"
  elif [ "$mi" -gt 0 ]; then prev="$ma.$((mi - 1)).0"
  else prev="$((ma - 1)).0.0"; fi
  rewrite "$f" sed "s#n8nio/runners:${v//./\\.}@#n8nio/runners:$prev@#"
}

# Assertion 4: a service loses cap_drop: ALL.
worker_without_cap_drop() {
  rewrite "$1/docker-compose.yml" awk '
    /^  [a-z0-9-]+:$/ { svc = $1 }
    svc == "n8n-worker:" && $0 == "    cap_drop:" { skip = 1; next }
    skip && $0 == "      - ALL" { skip = 0; next }
    { skip = 0; print }'
}

# Assertion 5: a service loses no-new-privileges.
caddy_without_no_new_privileges() {
  rewrite "$1/docker-compose.yml" awk '
    /^  [a-z0-9-]+:$/ { svc = $1 }
    svc == "caddy:" && $0 == "    security_opt:" { skip = 1; next }
    skip && $0 == "      - no-new-privileges:true" { skip = 0; next }
    { skip = 0; print }'
}

# Assertion 6: NODES_EXCLUDE no longer excludes anything.
empty_nodes_exclude() {
  rewrite "$1/docker-compose.yml" sed "s#^  NODES_EXCLUDE: .*#  NODES_EXCLUDE: '[]'#"
}

# Assertion 7: n8n can read environment variables in nodes.
allow_env_access() {
  rewrite "$1/docker-compose.yml" sed \
    's#N8N_BLOCK_ENV_ACCESS_IN_NODE: "true"#N8N_BLOCK_ENV_ACCESS_IN_NODE: "false"#'
}

# Assertion 8: n8n connects to Postgres as the superuser.
connect_as_superuser() {
  rewrite "$1/docker-compose.yml" sed \
    's#DB_POSTGRESDB_USER: ${POSTGRES_NON_ROOT_USER:-n8n}#DB_POSTGRESDB_USER: ${POSTGRES_USER:-postgres}#'
}

# Assertion 9: postgres joins a network that is not internal.
postgres_on_backend() {
  rewrite "$1/docker-compose.yml" awk '
    /^  [a-z0-9-]+:$/ { svc = $1 }
    { print }
    svc == "postgres:" && $0 == "    networks:" { print "      - backend" }'
}

# --- Runner -------------------------------------------------------------------

pass=0
total=0

# run_case DESCRIPTION EXPECTED_FAILURE MUTATION
#   EXPECTED_FAILURE is the assertion number verify must fail on, or "none".
#   MUTATION is one of the functions above, or "none" for the unmodified copy.
run_case() {
  local desc="$1" expect="$2" mutation="$3" dir out rc failed
  total=$((total + 1))
  dir="$work/case-$total"
  mkdir -p "$dir"
  copy_stack "$repo" "$dir"

  if [ "$mutation" != none ]; then
    mkdir -p "$dir.orig" && copy_stack "$repo" "$dir.orig"
    "$mutation" "$dir"
    if diff -r "$dir.orig" "$dir" > /dev/null; then
      printf 'FAIL  %s: the mutation changed nothing\n' "$desc"
      return
    fi
  fi

  set +e
  out="$(bash "$here/verify.sh" "$dir" 2>&1)"
  rc=$?
  set -e
  failed="$(printf '%s\n' "$out" | sed -nE 's/^FAIL +[a-z]+ +([0-9]+|render).*/\1/p' | sort -u | tr '\n' ' ')"
  failed="${failed% }"

  if [ "$expect" = none ]; then
    if [ "$rc" -eq 0 ] && [ -z "$failed" ]; then
      pass=$((pass + 1))
      printf 'PASS  %s: verify passed (%s)\n' "$desc" "$(printf '%s\n' "$out" | tail -n 1)"
      return
    fi
  elif [ "$rc" -ne 0 ] && [ "$failed" = "$expect" ]; then
    pass=$((pass + 1))
    printf 'PASS  %s: verify failed on assertion %s only\n' "$desc" "$expect"
    return
  fi

  printf 'FAIL  %s: expected failing assertion(s) [%s], got [%s], exit %s\n' \
    "$desc" "$expect" "${failed:-none}" "$rc"
  printf '%s\n' "$out" | sed 's/^/      | /'
}

run_case "unmodified copy"                          none none
run_case "n8n publishes a port"                     1    publish_n8n_port
run_case "redis image without a digest"             2    strip_redis_digest
run_case "runners on the previous patch release"    3    runners_previous_patch
run_case "n8n-worker without cap_drop ALL"          4    worker_without_cap_drop
run_case "caddy without no-new-privileges"          5    caddy_without_no_new_privileges
run_case "NODES_EXCLUDE set to an empty list"       6    empty_nodes_exclude
run_case "N8N_BLOCK_ENV_ACCESS_IN_NODE=false"       7    allow_env_access
run_case "n8n connects as the Postgres superuser"   8    connect_as_superuser
run_case "postgres also on the backend network"     9    postgres_on_backend

echo "verify-selftest: $pass/$total passed"
[ "$pass" -eq "$total" ]
