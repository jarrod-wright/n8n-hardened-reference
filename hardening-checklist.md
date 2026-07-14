# Hardening checklist

The official n8n production hardening checklist, mapped to exactly where each item is applied in this repository. Source: the n8n production hardening documentation (docs.n8n.io). Every application and infrastructure item below is verifiable by reading `docker-compose.yml`, `docker-compose.runners.yml`, and the files under `scripts/` and `postgres/`.

## Application level (n8n)

| Item | Applied in |
|---|---|
| `N8N_ENCRYPTION_KEY` set before first boot, via the `_FILE` variant, and backed up | `docker-compose.yml` (`N8N_ENCRYPTION_KEY_FILE`), `scripts/init-secrets.sh`, backup guidance in SECURITY.md |
| `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` | `docker-compose.yml` |
| `N8N_RESTRICT_FILE_ACCESS_TO` set, and `N8N_BLOCK_FILE_ACCESS_TO_N8N_FILES=true` | `docker-compose.yml` |
| `N8N_SECURE_COOKIE=true` | `docker-compose.yml` |
| `N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true` | `docker-compose.yml` |
| `EXECUTIONS_DATA_PRUNE=true` with `EXECUTIONS_DATA_MAX_AGE` | `docker-compose.yml` |
| `N8N_DIAGNOSTICS_ENABLED=false` | `docker-compose.yml` |
| `N8N_PUBLIC_API_DISABLED=true` (and the Swagger UI) | `docker-compose.yml` |
| `NODES_EXCLUDE` for high-risk nodes (`executeCommand`, `ssh`) | `docker-compose.yml` |
| Task runners in external mode in production | `docker-compose.runners.yml` (`make deploy-runners`) |
| `_FILE` suffix for secret values | encryption key and both database passwords |
| `N8N_BASIC_AUTH_*` not used (removed in n8n v1.0) | intentionally absent; see the note in `docker-compose.yml` |

## Infrastructure level

| Item | Applied in |
|---|---|
| Reverse proxy terminates TLS; the editor is not exposed directly | Caddy; n8n publishes no host port |
| Least-privilege containers | `cap_drop: ALL` plus minimal `cap_add`, `no-new-privileges` on every service |
| Non-root database user for the application | `postgres/init-data.sh` |
| Immutable image references | `make pin-digests` (resolve tags to `sha256` digests) |
| Bounded logging and resource limits | per-service `logging` and memory limits |

## Host level (your responsibility)

These are outside the compose stack and must be applied on the host itself.

| Item | How |
|---|---|
| Firewall allowing only 80, 443 and SSH | `ufw` or your cloud provider's firewall |
| Brute-force protection | Fail2Ban or equivalent |
| SSH by key only, root login disabled | `sshd_config` |
| Two-factor authentication on the n8n owner account | enable in n8n user settings after first login |

The host-level items are listed here so that nothing is silently assumed. They are the deployer's responsibility, not the stack's.
