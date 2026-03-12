#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -q "PermitRootLogin no" "${ROOT_DIR}/infra/ansible/playbooks/security-hardening.yml"
grep -q "PasswordAuthentication no" "${ROOT_DIR}/infra/ansible/playbooks/security-hardening.yml"
grep -q "fail2ban" "${ROOT_DIR}/infra/ansible/playbooks/security-hardening.yml"
grep -q "user: \"{{ openbao_container_user }}\"" "${ROOT_DIR}/infra/ansible/templates/openbao/docker-compose.yml.j2"
grep -q "audit enable file" "${ROOT_DIR}/infra/ansible/templates/openbao/bootstrap-openbao.sh.j2"
