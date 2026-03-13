#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -q "PermitRootLogin no" "${ROOT_DIR}/infra/ansible/playbooks/security-hardening.yml"
grep -q "PasswordAuthentication no" "${ROOT_DIR}/infra/ansible/playbooks/security-hardening.yml"
grep -q "fail2ban" "${ROOT_DIR}/infra/ansible/playbooks/security-hardening.yml"
grep -q 'SKIP_CHOWN: "true"' "${ROOT_DIR}/infra/ansible/templates/openbao/docker-compose.yml.j2"
grep -q '/opt/openbao/data:/openbao/file' "${ROOT_DIR}/infra/ansible/templates/openbao/docker-compose.yml.j2"
grep -q 'openbao_container_uid: "100"' "${ROOT_DIR}/infra/ansible/group_vars/openbao.yml"
grep -q 'openbao_container_gid: "1000"' "${ROOT_DIR}/infra/ansible/group_vars/openbao.yml"
grep -q "audit enable file" "${ROOT_DIR}/infra/ansible/templates/openbao/bootstrap-openbao.sh.j2"
