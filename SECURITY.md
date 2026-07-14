# Security

This document explains the reasoning behind the hardening in this repository, and how to report a problem. The goal is that every non-obvious default has a written reason next to it.

## Reporting a vulnerability

If you find a security issue in this reference, please report it privately using GitHub's security advisory feature on this repository, rather than opening a public issue. Include the affected file, the impact, and reproduction steps.

## Design principles

1. Least exposure. Only the reverse proxy is reachable from outside. n8n, PostgreSQL and Redis never publish a host port, and the data tier has no internet egress at all.
2. Least privilege. Containers drop all Linux capabilities and add back only what the image genuinely needs. No process gains privileges it did not start with.
3. Secrets stay out of the image and out of the environment. They live in files mounted at runtime and never committed.
4. Fail closed. If a required secret is missing, the deploy aborts rather than starting with an insecure default.
5. The reasoning is legible. A reviewer should be able to read the compose file and the checklist and understand the posture in a few minutes.

## Network

Three Docker networks:

- `proxy`: Caddy and the n8n main process. This is the only tier with published host ports (80, 443, and 443/udp for HTTP/3).
- `backend`: n8n main and worker, and (with the overlay) the task-runner sidecars. This tier has egress, because workflows and Code nodes legitimately call external APIs.
- `data`: PostgreSQL and Redis, plus n8n main and worker for their database and queue traffic. This network is marked `internal: true`, so PostgreSQL and Redis have no route to the internet.

The effect is layered. A compromise of the edge proxy does not put an attacker on the same segment as the database. A compromise of the database or cache does not give an outbound path to exfiltrate data, because that tier cannot reach the internet.

## Fail-closed configuration

`N8N_HOST`, `ACME_EMAIL` and `REDIS_PASSWORD` (and `N8N_RUNNERS_AUTH_TOKEN` when the runners overlay is used) are required. They are referenced with the `${VAR:?message}` form, so if any is unset the deploy stops with a clear error. This removes the common failure where a missing variable silently becomes an empty string, leaving Redis or the task-runner broker with no password.

## TLS

Caddy obtains and renews certificates from Let's Encrypt automatically. Responses carry HSTS (two years, includeSubDomains, preload-eligible), `X-Content-Type-Options`, `X-Frame-Options`, a restrictive `Referrer-Policy` and `Permissions-Policy`, and the server software is not advertised. For pre-production testing, switch Caddy to the Let's Encrypt staging CA (commented in the `Caddyfile`) to avoid rate limits.

## Container hardening

- `cap_drop: ALL` on every service.
- Minimal `cap_add`: `NET_BIND_SERVICE` for Caddy so it can bind 80 and 443; the entrypoint capability set PostgreSQL and Redis need (`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETGID`, `SETUID`); nothing added for n8n.
- `no-new-privileges: true` on every service.
- Read-only root filesystem on Caddy, with a tmpfs for scratch and named volumes for its state.
- Per-service memory limits and bounded json-file logging, so one service cannot starve the host or fill the disk.

Read-only root filesystems were not applied to n8n, PostgreSQL and Redis because their runtime write paths are broader than Caddy's; the capability and privilege restrictions still apply to them. The capability sets are chosen to match the official images' entrypoint behaviour, and are confirmed at deployment.

## Node file and environment access

Code and file-handling nodes are constrained: `N8N_BLOCK_ENV_ACCESS_IN_NODE` stops nodes reading the process environment, and `N8N_RESTRICT_FILE_ACCESS_TO` limits node file access to a dedicated empty `/files` volume rather than the n8n home directory. `N8N_BLOCK_FILE_ACCESS_TO_N8N_FILES` blocks access to n8n's own sensitive files even within an allowed path.

## Database

The PostgreSQL superuser is used only for cluster initialisation and the healthcheck. On first boot, `postgres/init-data.sh` creates a separate non-root user that owns the n8n database, and n8n connects as that user. The script passes the user name and password to psql as bound variables, so the password is never interpolated into the SQL text. A compromise of the n8n application therefore does not hand an attacker the database superuser.

## Secrets

- The n8n encryption key and both database passwords are Docker file-secrets, mounted under `/run/secrets/` and referenced through n8n's `*_FILE` variables. They are never in the image, the compose environment, or the repository.
- Secret files are written without a trailing newline, so the value read by n8n and PostgreSQL matches exactly.
- `.env` and everything under `secrets/` are gitignored from the first commit.
- The n8n encryption key is unrecoverable. If it is lost, stored credentials cannot be decrypted. Back it up separately from the database, at the moment you generate it.
- Redis authenticates with a password even though it publishes no host port. The healthcheck reads the password from `REDISCLI_AUTH` rather than passing it on the command line. The `--requirepass` value still appears in the Redis container's process arguments; this is visible only inside that container, on the internal-only data network.

## Task runners

n8n Code nodes execute user-provided JavaScript and Python. On n8n 2.x, task runners are enabled by default in internal mode, where the runner shares the uid and gid of n8n. For production, the official guidance is external mode, where each broker (main and each worker) runs a dedicated `n8nio/runners` sidecar isolated from n8n. This repo ships that as `docker-compose.runners.yml`:

```bash
make deploy-runners
```

The runner image version must match the n8n image version. The sidecars connect to the broker on port 5679 using the shared `N8N_RUNNERS_AUTH_TOKEN`. Refer to the official documentation on task runners, and on hardening task runners, for allowlisting built-in and third-party modules.

## Image pinning

Image tags in the compose files are pinned to a specific line for readability, but tags are mutable. Before production, run `make pin-digests` and replace each `repo:tag` with `repo:tag@sha256:...`, so that a moved tag cannot silently change what you deploy.

## Host responsibilities

The stack hardens the containers. The host underneath them is yours to harden:

- A firewall allowing only 80, 443 and your SSH port.
- Brute-force protection (Fail2Ban or equivalent).
- SSH by key only, with root login disabled.
- Two-factor authentication on the n8n owner account, once it is created.
- Scheduled `make backup`, with a restore tested before you rely on it.
