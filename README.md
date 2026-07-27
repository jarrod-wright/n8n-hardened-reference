# n8n-hardened-reference

I build production automation infrastructure for clients who need their n8n instance treated like a real system, not a docker-compose tutorial. This repo is the reference deployment I bring to that work: security-hardened, legible, and one command to stand up.

> Status: hardened reference and template. Read the threat model and [SECURITY.md](SECURITY.md), then adapt it to your host and your workflows. Do not run it blind.

## Scope and roadmap

**What this repo covers today: the container and stack plane.** The n8n services, their network boundaries, TLS termination, secret handling, database privileges, capability drops and task-runner isolation — everything inside the Compose file and the reverse proxy in front of it. Every claim in the threat model below is about that plane, and is readable in the shipped configuration.

**What it does not cover: the host and OS plane.** SSH policy, kernel and sysctl parameters, host firewall, package and patch posture, auditd, filesystem mount options, unattended upgrades. A hardened stack on an unhardened host is still an unhardened host. This repo makes no claim about the machine underneath it, and you should not read one into it.

**What is being built.** A portable host-hardening assertion suite — CIS Level 1 Server for Ubuntu 24.04, with every exception publicly justified — that runs standalone against any fresh host, not only this fixture. It will publish here as executable assertions and a red/green baseline runner, so you can measure your own server rather than take my word for the posture of mine.

**Why the split is what it is.** The assertions will be public; the automation that remediates what they find will not. The suite tells you, precisely and in your own environment, what is wrong. Fixing it at scale — the roles, the client tailoring, the migration runbooks — is the engagement. That is a stated position, not an omission: where the value lives in the work rather than the artifact, I publish the artifact generously. Detection is not remediation.

## How I approach a migration

Standing up a hardened stack is one skill. Moving a client's live automations onto it without breaking anything is a different one — and it's the part that actually matters to a business depending on those workflows.

That work is an engagement, not a script in this repo. **None of the migration tooling described below ships here.** What I hold to:

- **Inventory and node-equivalence first.** Every existing workflow, trigger and credential is mapped before anything is touched.
- **Parallel run, never a cold cutover.** The new stack runs alongside the existing automation and is validated against real inputs, with production side effects duplicated or disabled.
- **Ordered credential repoint.** Integrations move one at a time, each verified, with the previous instance kept warm.
- **Rollback as a repoint, not a rebuild.** The old instance stays warm until the new one has earned the traffic.

The repo gives you the target stack. The migration is the service.

## Why the hardening matters

Self-hosting n8n places an automation engine — holding credentials to everything it touches — directly on the public internet. Many community compose files expose the editor on port 5678, run every service as root on one flat network, and skip the environment flags that actually change the security posture. This repo takes the opposite default: a small, legible stack where the hardened choice is the built-in one, and the reasoning is written down next to it.

## Threat model

What an internet-facing n8n exposes, and how this deployment answers each item.

| Exposure | Mitigation |
|---|---|
| Editor and API reachable on the public internet | Only Caddy publishes ports 80 and 443. n8n, PostgreSQL and Redis are reachable only on internal Docker networks. |
| Missing or self-signed TLS | Caddy issues and renews Let's Encrypt certificates automatically, with HSTS and modern security headers. |
| Arbitrary command or code execution through nodes | The `executeCommand` and `ssh` nodes are excluded. Code-node execution is isolated in dedicated task-runner containers (external-mode overlay). |
| Container breakout or privilege escalation | Every service runs with `cap_drop: ALL` plus a minimal capability set, `no-new-privileges`, and a read-only root filesystem where the image allows it. |
| Database compromise blast radius | n8n connects as a non-root PostgreSQL user, never the superuser. |
| Secret leakage | The encryption key and both database passwords are Docker file-secrets, never baked into the image or the environment. `.env` and `secrets/` are gitignored. |
| Credential theft via node file or env access | Environment access from nodes is blocked; node file access is restricted to a dedicated sandbox directory. |
| Disk exhaustion from logs or execution history | Bounded json-file logging and automatic execution-data pruning. |
| Lost encryption key means lost credentials | Key handling and backup are called out explicitly, in the deploy flow and in SECURITY.md. |

Full list: [hardening-checklist.md](hardening-checklist.md). Rationale: [SECURITY.md](SECURITY.md).

## Architecture

```
                       Internet
                          |
                    :80 / :443   (the only published ports)
                          |
                  +---------------+
                  |     Caddy     |   automatic TLS, HSTS, security headers
                  +---------------+
                          |  proxy network
                  +---------------+
                  |   n8n (main)  |   UI / API / webhooks, task broker
                  +---------------+
                          |  backend network (internal only)
        +-----------------+----------+-------------------+
        |                 |          |                   |
  +-----------+   +--------------+   +--------+   (external-runners overlay)
  | PostgreSQL|   |    Redis     |   |  n8n   |   +---------------------+
  |  (data)   |   | (Bull queue) |   | worker |   | task-runner sidecar |
  +-----------+   +--------------+   +--------+   | JS / Python, per     |
                                                  | broker, isolated     |
                                                  +---------------------+
```

Queue mode splits the UI and webhook process (main) from execution (worker), coordinated through Redis. In the external-runners overlay, user Code-node execution runs in separate `n8nio/runners` sidecars, one per broker, isolated from n8n itself.

## Quick start

1. Point a DNS A record at the server. Ports 80 and 443 must be reachable for certificate issuance.
2. Copy the environment file and set your values:
   ```bash
   cp .env.example .env
   # set N8N_HOST, ACME_EMAIL, REDIS_PASSWORD
   # (and N8N_RUNNERS_AUTH_TOKEN if you use the runners overlay)
   ```
3. Deploy:
   ```bash
   make deploy            # base stack (internal task runners)
   # or
   make deploy-runners    # adds external task-runner isolation (recommended for production)
   ```
4. Open `https://<N8N_HOST>` and create the owner account.

`make deploy` runs `make init-secrets` for you, which generates the encryption key and database passwords into `secrets/`. Back up `secrets/n8n_encryption_key.txt` immediately and keep it somewhere safe. If it is lost, every stored credential becomes undecryptable.

Every image is pinned to a `sha256` digest in the shipped compose files, so a moved tag can't silently change what you deploy. Re-run `make pin-digests` if you bump a version and want to re-pin.

## Hardening

The security posture is documented, not implied.

- [hardening-checklist.md](hardening-checklist.md): the official n8n production checklist, mapped to exactly where each item is applied in this repo.
- [SECURITY.md](SECURITY.md): the reasoning behind the container, network, secret and task-runner choices, and how to report an issue.

## Backup and restore

```bash
make backup                          # pg_dump (custom format) + n8n data, with retention
make restore SRC=backups/<timestamp> # stop, pg_restore, start
```

Restores require the same encryption key that was in place when the backup was taken. The key is intentionally not bundled into the backup archives. Store it separately and securely.

## What this is, and is not

- It is a hardened, legible starting point that I use in client delivery, and that you're welcome to adapt to your own host and workflows.
- It is not a managed service, a one-click appliance, or a reason to skip reading SECURITY.md.

## License

MIT. See [LICENSE](LICENSE).

---

I build and deliver self-hosted automation infrastructure for clients. If that's what you need: **jarrod@jwmkwild.com**
