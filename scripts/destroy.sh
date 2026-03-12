#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/infra/tofu"

if ! command -v tofu >/dev/null 2>&1; then
  echo "opentofu is required for destroy.sh" >&2
  exit 1
fi

pushd "${TF_DIR}" >/dev/null
tofu init -input=false
tofu destroy -auto-approve -input=false
popd >/dev/null
