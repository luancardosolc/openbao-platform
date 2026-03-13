#!/usr/bin/env bash
set -euo pipefail

OPENBAO_ADDR="${OPENBAO_ADDR:-}"
OPENBAO_TOKEN="${OPENBAO_TOKEN:-}"
OPENBAO_SKIP_VERIFY="${OPENBAO_SKIP_VERIFY:-true}"
TARGET="${1:-}"

if [[ -z "${OPENBAO_ADDR}" || -z "${OPENBAO_TOKEN}" ]]; then
  echo "OPENBAO_ADDR and OPENBAO_TOKEN must be set." >&2
  exit 1
fi

if [[ -z "${TARGET}" ]]; then
  cat >&2 <<'EOF'
Usage:
  ./scripts/export-workstation-secrets.sh github-personal
  ./scripts/export-workstation-secrets.sh github-client
  ./scripts/export-workstation-secrets.sh postman
  ./scripts/export-workstation-secrets.sh trello
  ./scripts/export-workstation-secrets.sh ssh-metadata
  ./scripts/export-workstation-secrets.sh codex-metadata
EOF
  exit 1
fi

case "${TARGET}" in
  github-personal) path="kv/data/workstation/mcp/github-personal" ;;
  github-client) path="kv/data/workstation/mcp/github-client" ;;
  postman) path="kv/data/workstation/mcp/postman" ;;
  trello) path="kv/data/workstation/mcp/trello" ;;
  ssh-metadata) path="kv/data/workstation/ssh/metadata" ;;
  codex-metadata) path="kv/data/workstation/codex/metadata" ;;
  *)
    echo "Unknown target: ${TARGET}" >&2
    exit 1
    ;;
esac

curl_args=(-fsS -H "X-Vault-Token: ${OPENBAO_TOKEN}")
if [[ "${OPENBAO_SKIP_VERIFY}" == "true" ]]; then
  curl_args+=(-k)
fi

response="$(curl "${curl_args[@]}" "${OPENBAO_ADDR%/}/v1/${path}")"

if [[ "${TARGET}" == "ssh-metadata" || "${TARGET}" == "codex-metadata" ]]; then
  jq '.data.data' <<<"${response}"
  exit 0
fi

if [[ "${TARGET}" == "trello" ]]; then
  api_key="$(jq -r '.data.data.api_key' <<<"${response}")"
  token="$(jq -r '.data.data.token' <<<"${response}")"

  if [[ -z "${api_key}" || -z "${token}" || "${api_key}" == "null" || "${token}" == "null" ]]; then
    echo "The selected secret path does not contain api_key/token as expected." >&2
    exit 1
  fi

  printf 'export TRELLO_API_KEY=%q\n' "${api_key}"
  printf 'export TRELLO_TOKEN=%q\n' "${token}"
  exit 0
fi

env_var="$(jq -r '.data.data.env_var' <<<"${response}")"
token="$(jq -r '.data.data.token' <<<"${response}")"

if [[ -z "${env_var}" || -z "${token}" || "${env_var}" == "null" || "${token}" == "null" ]]; then
  echo "The selected secret path does not contain env_var/token as expected." >&2
  exit 1
fi

printf 'export %s=%q\n' "${env_var}" "${token}"
