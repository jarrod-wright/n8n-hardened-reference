# NIST SP 800-190 Applicability Statement

This repo is hardened against NIST SP 800-190's container-security threat classes,
but not uniformly — a single-host Docker Compose deployment does not have all five
tiers 800-190 describes, and it would overclaim to imply otherwise. This statement
says plainly which tiers apply here, which don't, and why.

## The five tiers, and where this repo stands on each

| Tier | Applies here? | Current coverage |
|---|---|---|
| **Image** | Yes | Partial — excluded dangerous nodes (`executeCommand`, `ssh`), non-root DB user, task-runner sidecar isolation for Code-node execution. See the [threat model](README.md#threat-model). |
| **Registry** | **Degenerate** | This deployment pulls from public registries (Docker Hub / GHCR) with digest pinning for reproducibility. There is no private registry, no image-signing pipeline, and no registry-access-control layer distinct from "can this host reach the internet." Claiming registry-tier hardening here would describe a control that doesn't exist in this architecture. |
| **Orchestrator** | **Degenerate** | Docker Compose is not an orchestrator in the 800-190 sense — no scheduler, no multi-node placement, no admission control, no orchestrator-level RBAC. This tier does not apply to a single-host Compose deployment and won't until/unless the architecture changes to something like Kubernetes, which is out of scope for this repo. |
| **Container runtime** | Yes | Covered — network isolation (only Caddy publishes ports), `cap_drop: ALL`, `no-new-privileges`, read-only root filesystem where the image allows, Docker file-secrets for credential material. |
| **Host OS** | Yes, **not yet covered** | This is the gap. SSH policy, kernel/sysctl parameters, host firewall, patch posture, auditd, filesystem mount options — none of this is addressed by the current repo content. A portable, standalone-runnable host-hardening assertion suite for exactly this tier is in progress (see [Scope and roadmap](README.md#scope-and-roadmap)). Until it ships, this repo's hardening claims stop at the container/stack boundary. |

## Why this matters

A container stack can be hardened perfectly and still run on a host with default SSH
config, no firewall, and unpatched packages. The inverse is equally true. Neither
condition implies the other, and a threat model that only lists container-tier
mitigations without saying so explicitly can read as a broader security claim than
it is. This statement exists so that gap is named, not implied away.

## Source

Derived from the VPSHR programme's ADR-001 (standards spine) and the threat-model v2
re-mapping exercise (internal governance record, not duplicated here — this statement
is the public-facing summary of that finding, not the full working document).
