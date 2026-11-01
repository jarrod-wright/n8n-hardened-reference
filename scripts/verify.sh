#!/usr/bin/env bash
# make verify: check the hardening posture of the stack as Docker Compose sees it.
#
#   scripts/verify.sh [STACK_DIR]      (default STACK_DIR: this repository)
#
# Renders `docker compose config --format json` for the two shipped
# configurations, base (docker-compose.yml) and runners (docker-compose.yml +
# docker-compose.runners.yml), from a throwaway copy of STACK_DIR with a
# throwaway .env and secrets. The checks read the rendered model, so anchors,
# merge keys, the overlay and variable substitution are already applied.
#
# Prints one line per assertion per configuration, then "verify: N/N passed".
# Exits non-zero if any assertion fails. Needs bash, the docker compose v2 CLI,
# jq and openssl. It does not start containers or contact a registry.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(cd "${1:-$here/..}" && pwd)"
# shellcheck source=scripts/lib-throwaway.sh
. "$here/lib-throwaway.sh"

command -v jq > /dev/null || { echo "verify: jq is required" >&2; exit 2; }
docker compose version > /dev/null 2>&1 || { echo "verify: the docker compose v2 CLI is required" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
throwaway_copy "$src" "$work"

# Each filter prints "ok", "ok <detail>", or a failure detail.
# $config is "base" or "runners".
read -r -d '' F1 <<'JQ' || true
  ([.services | to_entries[]
    | select(((.value.ports // []) | length) > 0 or .value.network_mode == "host") | .key]) as $pub
  | ([(.services.caddy.ports // [])[] | "\(.published)/\(.protocol // "tcp")"] | sort) as $cp
  | if $pub != ["caddy"] then
      "services publishing ports: " + (if $pub == [] then "none" else $pub | join(", ") end)
    elif $cp != (["80/tcp", "443/tcp", "443/udp"] | sort) then
      "caddy publishes " + ($cp | join(" "))
    else "ok" end
JQ

read -r -d '' F2 <<'JQ' || true
  [.services | to_entries[]
   | select((.value.image // "") | test("@sha256:[0-9a-f]{64}$") | not) | .key]
  | if length == 0 then "ok" else "no @sha256 digest: " + join(", ") end
JQ

read -r -d '' F3 <<'JQ' || true
  def repo: sub("@.*$"; "") | sub(":[^/:]*$"; "");
  def tag: sub("@.*$"; "") | if test(":[^/:]+$") then sub("^.*:"; "") else "(none)" end;
  [.services | to_entries[]
   | select(.key == "n8n" or .key == "n8n-worker"
            or ((.value.image // "") | repo | test("(^|/)n8nio/runners$")))
   | {name: .key, tag: (.value.image // "" | tag),
      runner: ((.value.image // "") | repo | test("(^|/)n8nio/runners$"))}] as $s
  | ($s | map(.tag) | unique) as $tags
  | if ([$s[].name] | (any(.[]; . == "n8n") and any(.[]; . == "n8n-worker")) | not) then
      "n8n or n8n-worker service missing"
    elif $config == "runners" and ([$s[] | select(.runner)] | length) == 0 then
      "no n8nio/runners service in the runners overlay"
    elif ($tags | length) != 1 then
      "tags differ: " + ([$s[] | "\(.name)=\(.tag)"] | join(" "))
    else "ok " + $tags[0] end
JQ

read -r -d '' F4 <<'JQ' || true
  [.services | to_entries[] | select((.value.cap_drop // []) | any(.[]; . == "ALL") | not) | .key]
  | if length == 0 then "ok" else "missing cap_drop ALL: " + join(", ") end
JQ

read -r -d '' F5 <<'JQ' || true
  [.services | to_entries[]
   | select((.value.security_opt // []) | any(.[]; . == "no-new-privileges:true") | not) | .key]
  | if length == 0 then "ok" else "missing no-new-privileges:true: " + join(", ") end
JQ

read -r -d '' F6 <<'JQ' || true
  . as $root
  | [("n8n", "n8n-worker") as $k
   | ($root.services[$k].environment.NODES_EXCLUDE // null) as $v
   | select(($v // "") | (try fromjson catch null)
            | (type == "array" and length > 0 and all(.[]; type == "string" and . != "")) | not)
   | "\($k)=\($v // "unset")"]
  | if length == 0 then "ok " + $root.services.n8n.environment.NODES_EXCLUDE
    else "unset, empty or not a JSON list of node types: " + join(" ") end
JQ

read -r -d '' F7 <<'JQ' || true
  [("n8n", "n8n-worker") as $k
   | (.services[$k].environment.N8N_BLOCK_ENV_ACCESS_IN_NODE // null) as $v
   | select($v != "true") | "\($k)=\($v // "unset")"]
  | if length == 0 then "ok" else "not \"true\": " + join(" ") end
JQ

read -r -d '' F8 <<'JQ' || true
  # The official postgres image uses "postgres" as the superuser when POSTGRES_USER is unset.
  (.services.postgres.environment.POSTGRES_USER // "postgres") as $su
  | [("n8n", "n8n-worker") as $k
     | {name: $k, user: (.services[$k].environment.DB_POSTGRESDB_USER // "")}] as $u
  | if any($u[]; .user == "" or .user == $su) then
      "DB_POSTGRESDB_USER unset or equal to the superuser: "
      + ([$u[] | "\(.name)=\(if .user == "" then "unset" else .user end)"] | join(" "))
      + " superuser=\($su)"
    else "ok " + ([$u[].user] | unique | join(",")) + " vs superuser " + $su end
JQ

read -r -d '' F9 <<'JQ' || true
  .networks as $nets
  | [("postgres", "redis") as $k | .services[$k] as $s
     | if $s == null then "\($k) missing"
       elif ($s.network_mode // "") != "" then "\($k) network_mode=\($s.network_mode)"
       elif (($s.networks // {}) | length) == 0 then "\($k) on the default network"
       else ($s.networks | keys[] | select(($nets[.].internal // false) != true) | "\($k) on \(.)")
       end] as $bad
  | if ($bad | length) == 0 then
      "ok " + ([("postgres", "redis") as $k | .services[$k].networks | keys[]] | unique | join(","))
    else "not internal-only: " + ($bad | join(", ")) end
JQ

pass=0
total=0

# check CONFIG NUMBER DESCRIPTION FILTER
check() {
  local config="$1" n="$2" desc="$3" filter="$4" out
  total=$((total + 1))
  if ! out="$(jq -r --arg config "$config" "$filter" "$work/$config.json" 2>&1)"; then
    out="jq error: $out"
  fi
  case "$out" in
    ok)     pass=$((pass + 1)); printf 'PASS  %-7s %s. %s\n' "$config" "$n" "$desc" ;;
    "ok "*) pass=$((pass + 1)); printf 'PASS  %-7s %s. %s (%s)\n' "$config" "$n" "$desc" "${out#ok }" ;;
    *)      printf 'FAIL  %-7s %s. %s: %s\n' "$config" "$n" "$desc" "$out" ;;
  esac
}

for config in base runners; do
  if ! stack_compose "$work" "$config" config --format json > "$work/$config.json" 2> "$work/$config.err"; then
    total=$((total + 9))
    printf 'FAIL  %-7s render: docker compose config failed\n' "$config"
    sed 's/^/      | /' "$work/$config.err"
    continue
  fi
  check "$config" 1 "only caddy publishes ports, exactly 80/tcp 443/tcp 443/udp" "$F1"
  check "$config" 2 "every service image is pinned by @sha256 digest" "$F2"
  check "$config" 3 "n8n, n8n-worker and runners images share one version tag" "$F3"
  check "$config" 4 "every service drops all capabilities (cap_drop ALL)" "$F4"
  check "$config" 5 "every service sets no-new-privileges:true" "$F5"
  check "$config" 6 "n8n and n8n-worker set NODES_EXCLUDE to a non-empty list" "$F6"
  check "$config" 7 "n8n and n8n-worker set N8N_BLOCK_ENV_ACCESS_IN_NODE=true" "$F7"
  check "$config" 8 "n8n and n8n-worker connect to Postgres as a non-superuser" "$F8"
  check "$config" 9 "postgres and redis are only on internal networks" "$F9"
done

echo "verify: $pass/$total passed"
[ "$pass" -eq "$total" ]
