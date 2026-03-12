# Automation

## Entry Points

- `make bootstrap`: installs or validates required local tooling
- `make lint`: markdown, shell, yaml, and tofu linting
- `make test`: validation and deployment-oriented tests
- `make deploy`: OpenTofu apply, Ansible provisioning, OpenBao deployment
- `make destroy`: tear down infrastructure

## GitHub Actions

- `ci.yml`: lint, validate, and test
- `security.yml`: Trivy filesystem, IaC, and container image scanning
- `deploy.yml`: workflow-dispatched deployment

## Local Reproducibility

Where host tooling is absent, scripts fall back to containerized execution so the workflow remains deterministic on a clean machine.
