# OpenBao Platform

Open-source infrastructure platform to deploy a hardened single-node OpenBao cluster on a Hetzner VPS with OpenTofu, Ansible, Docker, GitHub Actions, and Trello-backed execution tracking.

## Goals

- Infrastructure as code with OpenTofu modules
- GitOps-friendly workflows with GitHub Actions
- Fully scripted deployment, backup, restore, and validation
- Default Hetzner deployment with AWS and DigitalOcean portability
- Minimal cost, single VPS footprint, open-source tooling only

## Quick Start

1. Copy `.env.example` to `.env` and fill in provider and deployment values.
2. Run `make bootstrap`.
3. Run `make lint`.
4. Run `make test`.
5. Run `make deploy`.
6. Run `make smoke` with `OPENBAO_ADDR` set after deployment.

## Tooling Strategy

Local quality checks run through containers where practical so the project remains reproducible even if the host does not already have `tofu`, `ansible`, `trivy`, or linting binaries installed.

## Operations Docs

- [docs/operator-access.md](docs/operator-access.md)
- [docs/runbook.md](docs/runbook.md)
- [docs/disaster-recovery.md](docs/disaster-recovery.md)
- [docs/backup-strategy.md](docs/backup-strategy.md)
- [docs/security.md](docs/security.md)
