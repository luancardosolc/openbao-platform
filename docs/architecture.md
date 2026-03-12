# Architecture

## Overview

The platform provisions a single Ubuntu 24.04 VPS and configures it as a minimal-cost OpenBao host. OpenTofu owns infrastructure provisioning, Ansible owns operating system state, Docker Compose owns the OpenBao runtime, and GitHub Actions owns continuous validation.

## Layers

- Provisioning: OpenTofu modules abstract provider differences between Hetzner, AWS, and DigitalOcean.
- Configuration: Ansible installs Docker, hardens SSH, configures host controls, and lays down OpenBao assets.
- Runtime: OpenBao runs in Docker with persistent volumes, TLS, audit logs, and a dedicated bridge network.
- Operations: Shell scripts, Make targets, and Task targets wrap common workflows.
- Governance: Trello tracks every major task from planning through completion.

## Data Flow

1. `make deploy` bootstraps local dependencies and validates IaC.
2. OpenTofu creates networking, firewalling, and the server.
3. OpenTofu renders a local inventory file from module outputs.
4. Ansible connects over SSH, configures the host, and deploys OpenBao.
5. Post-deploy tests confirm API health, container readiness, and security controls.

## Design Tradeoffs

- Single-node OpenBao minimizes cost and complexity but does not provide HA.
- Automated unseal on a single host is implemented with an encrypted local artifact to avoid manual bootstrapping; this is documented as a conscious minimal-cost tradeoff.
- Provider portability is achieved through a normalized module interface, not identical resource topologies.
