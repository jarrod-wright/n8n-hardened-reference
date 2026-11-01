# shellcheck shell=bash
# Helpers sourced by verify.sh, verify-selftest.sh and smoke.sh. Not run directly.
#
# Nothing here writes to the source checkout: every copy, .env and secret lives
# in a temp directory that the caller deletes on exit.

# copy_stack SRC DEST
#   Copy the files that define the stack from SRC into the existing directory DEST.
copy_stack() {
  local src="$1" dest="$2" f
  for f in docker-compose.yml docker-compose.runners.yml Caddyfile .env.example; do
    cp "$src/$f" "$dest/$f"
  done
  cp -R "$src/postgres" "$src/scripts" "$dest/"
}

# throwaway_copy SRC DEST
#   copy_stack, then write DEST/.env from .env.example with fresh random
#   REDIS_PASSWORD and N8N_RUNNERS_AUTH_TOKEN, and generate DEST/secrets/ with
#   the stack's own scripts/init-secrets.sh.
throwaway_copy() {
  local src="$1" dest="$2"
  copy_stack "$src" "$dest"
  sed -e "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -hex 24)|" \
      -e "s|^N8N_RUNNERS_AUTH_TOKEN=.*|N8N_RUNNERS_AUTH_TOKEN=$(openssl rand -hex 32)|" \
      "$dest/.env.example" > "$dest/.env"
  bash "$dest/scripts/init-secrets.sh" > /dev/null
}

# stack_compose DIR CONFIG [compose args...]
#   Run docker compose on the stack in DIR. CONFIG is "base" (docker-compose.yml)
#   or "runners" (docker-compose.yml + docker-compose.runners.yml).
stack_compose() {
  local dir="$1" config="$2"
  shift 2
  case "$config" in
    base)    docker compose --project-directory "$dir" -f "$dir/docker-compose.yml" "$@" ;;
    runners) docker compose --project-directory "$dir" -f "$dir/docker-compose.yml" \
               -f "$dir/docker-compose.runners.yml" "$@" ;;
    *)       echo "unknown config '$config' (expected base or runners)" >&2; return 2 ;;
  esac
}
