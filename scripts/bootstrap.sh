#!/usr/bin/env bash
set -euo pipefail

ensure_command() {
  local cmd="$1"
  if command -v "${cmd}" >/dev/null 2>&1; then
    return 0
  fi
  echo "missing dependency: ${cmd}" >&2
  return 1
}

echo "Checking required host commands..."
ensure_command docker
ensure_command git
ensure_command ssh

cat <<EOF
Bootstrap complete.
This project uses containerized linting and validation where practical.
If you want native tooling as well, install: opentofu, ansible, task, pre-commit, trivy, shellcheck, yamllint, markdownlint-cli2, tflint.
EOF
