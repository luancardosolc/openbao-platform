#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/infra/tofu"
ANSIBLE_DIR="${ROOT_DIR}/infra/ansible"

export TF_VAR_cloud_provider="${PLATFORM_PROVIDER:-hetzner}"
export TF_VAR_project_name="${PLATFORM_PROJECT_NAME:-openbao-platform}"
export TF_VAR_environment="${PLATFORM_ENVIRONMENT:-prod}"
export TF_VAR_hetzner_token="${PLATFORM_HETZNER_TOKEN:-}"
export TF_VAR_aws_region="${PLATFORM_AWS_REGION:-us-east-1}"
export TF_VAR_aws_access_key_id="${PLATFORM_AWS_ACCESS_KEY_ID:-}"
export TF_VAR_aws_secret_access_key="${PLATFORM_AWS_SECRET_ACCESS_KEY:-}"
export TF_VAR_do_token="${PLATFORM_DO_TOKEN:-}"
export TF_VAR_hetzner_ssh_key_ids="${PLATFORM_HETZNER_SSH_KEY_IDS:-[]}"
export TF_VAR_ssh_private_key_path="${PLATFORM_SSH_PRIVATE_KEY:-$HOME/.ssh/id_ed25519}"
SSH_PUBLIC_KEY_CONTENT="$(cat "${PLATFORM_SSH_PUBLIC_KEY:-$HOME/.ssh/id_ed25519.pub}")"
export SSH_PUBLIC_KEY_CONTENT
export TF_VAR_ssh_public_key="${SSH_PUBLIC_KEY_CONTENT}"
export TF_VAR_ssh_user="${PLATFORM_SSH_USER:-ubuntu}"
export TF_VAR_allowed_ssh_cidrs="${PLATFORM_ALLOWED_SSH_CIDRS:-[\"0.0.0.0/0\"]}"
export TF_VAR_allowed_api_cidrs="${PLATFORM_ALLOWED_API_CIDRS:-[\"0.0.0.0/0\"]}"
export TF_VAR_hetzner_location="${PLATFORM_HETZNER_LOCATION:-nbg1}"
export TF_VAR_server_size="${PLATFORM_HETZNER_SERVER_TYPE:-cpx21}"
export TF_VAR_server_image="${PLATFORM_HETZNER_IMAGE:-ubuntu-24.04}"
export TF_VAR_aws_instance_type="${PLATFORM_AWS_INSTANCE_TYPE:-t3.medium}"
export TF_VAR_aws_ami="${PLATFORM_AWS_AMI:-}"
export TF_VAR_aws_key_name="${PLATFORM_AWS_KEY_NAME:-}"
export TF_VAR_do_region="${PLATFORM_DO_REGION:-fra1}"
export TF_VAR_do_size="${PLATFORM_DO_SIZE:-s-2vcpu-4gb}"
export TF_VAR_do_image="${PLATFORM_DO_IMAGE:-ubuntu-24-04-x64}"
export TF_VAR_domain="${PLATFORM_DOMAIN:-openbao.example.com}"

if ! command -v tofu >/dev/null 2>&1; then
  echo "opentofu is required for deploy.sh" >&2
  exit 1
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ansible-playbook is required for deploy.sh" >&2
  exit 1
fi

pushd "${TF_DIR}" >/dev/null
tofu init -input=false
tofu apply -auto-approve -input=false
popd >/dev/null

ansible-galaxy collection install community.crypto community.docker community.general
ansible-playbook -i "${TF_DIR}/inventory.ini" "${ANSIBLE_DIR}/playbooks/install-docker.yml"
ansible-playbook -i "${TF_DIR}/inventory.ini" "${ANSIBLE_DIR}/playbooks/security-hardening.yml"
ansible-playbook -i "${TF_DIR}/inventory.ini" "${ANSIBLE_DIR}/playbooks/install-openbao.yml"
