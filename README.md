# OpenBao Platform

Open-source infrastructure platform to deploy a hardened single-node OpenBao cluster on a Hetzner VPS with OpenTofu, Ansible, Docker, GitHub Actions, and Trello-backed execution tracking.

## Goals

- Infrastructure as code with OpenTofu modules
- GitOps-friendly workflows with GitHub Actions
- Fully scripted deployment, backup, restore, and validation
- Default Hetzner deployment with AWS and DigitalOcean portability
- Minimal cost, single VPS footprint, open-source tooling only

## Quick Start

1. Read [ops/README.md](ops/README.md) and the backup/DR status before operating any host.
2. Run the offline test suite with `make test` in an environment with Bash.
3. For the current Hetzner host, run only the read-only check: `python ops/hetzner_health.py`.

The live host is not managed by this generic provisioning workflow yet. `make deploy` and `make destroy` are blocked by default; do not set their explicit confirmation gates for the production host. The old Ansible, backup, and restore examples do not match the live configuration.

## Tooling Strategy

Local quality checks run through containers where practical so the project remains reproducible even if the host does not already have `tofu`, `ansible`, `trivy`, or linting binaries installed.

## Operations Docs

- [ops/README.md](ops/README.md) — read-only checks for the existing Hetzner host
- [docs/operator-access.md](docs/operator-access.md)
- [docs/runbook.md](docs/runbook.md)
- [docs/disaster-recovery.md](docs/disaster-recovery.md)
- [docs/backup-strategy.md](docs/backup-strategy.md)
- [docs/security.md](docs/security.md)
- [docs/workstation-bootstrap.md](docs/workstation-bootstrap.md)
