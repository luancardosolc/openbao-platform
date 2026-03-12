#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/infra/tofu"

test -f "${TF_DIR}/providers.tf"
test -f "${TF_DIR}/variables.tf"
test -d "${ROOT_DIR}/infra/modules/vps"
test -d "${ROOT_DIR}/infra/modules/network"
test -d "${ROOT_DIR}/infra/modules/firewall"

if command -v tofu >/dev/null 2>&1; then
  (cd "${TF_DIR}" && tofu fmt -check -recursive)
  (cd "${TF_DIR}" && tofu init -backend=false -input=false)
  (cd "${TF_DIR}" && tofu validate)
else
  echo "tofu not installed; structural checks completed"
fi
