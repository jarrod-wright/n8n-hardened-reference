# Changelog

Notable changes to this repository, newest first. One entry per published
change. Versions are dated by the day they published.

## 2026-11-18

- CI now proves the hardening posture end to end: a boot test brings up the full
  stack including Caddy, signing with its internal CA, and serves n8n over HTTPS
  (`make boot-caddy`), and a mutation check re-applies five deliberate regressions
  that `make verify` must catch, with a positive control on the clean stack
  (`make mutation-check`).

## 2026-11-16

- Pinned n8n and the runners image to 2.47.7, the newest stable release at
  publish time, and re-pinned their sha256 digests. No other configuration
  changed.
