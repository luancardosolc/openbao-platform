#!/usr/bin/env bash
set -euo pipefail

OPENBAO_ADDR="${OPENBAO_ADDR:-}"
OPENBAO_SKIP_VERIFY="${OPENBAO_SKIP_VERIFY:-false}"
OPENBAO_TOKEN="${OPENBAO_TOKEN:-}"
BOOTSTRAP_FILE="${BOOTSTRAP_FILE:-}"
SMOKE_REQUIRE_TOKEN_CHECKS="${SMOKE_REQUIRE_TOKEN_CHECKS:-false}"

if [[ -z "${OPENBAO_ADDR}" ]]; then
  echo "OPENBAO_ADDR must be set" >&2
  exit 1
fi

curl_args=(-sS)
if [[ "${OPENBAO_SKIP_VERIFY}" == "true" ]]; then
  curl_args+=(-k)
fi

extract_json_field() {
  local field="$1"
  python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "${field}"
}

if [[ -z "${OPENBAO_TOKEN}" && -n "${BOOTSTRAP_FILE}" ]]; then
  if [[ ! -f "${BOOTSTRAP_FILE}" ]]; then
    echo "BOOTSTRAP_FILE does not exist: ${BOOTSTRAP_FILE}" >&2
    exit 1
  fi
  OPENBAO_TOKEN="$(
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1], "r", encoding="utf-8"))["root_token"])' \
      "${BOOTSTRAP_FILE}"
  )"
fi

health_json="$(curl "${curl_args[@]}" "${OPENBAO_ADDR}/v1/sys/health")"
initialized="$(extract_json_field initialized <<<"${health_json}")"
sealed="$(extract_json_field sealed <<<"${health_json}")"

if [[ "${initialized}" != "True" && "${initialized}" != "true" ]]; then
  echo "OpenBao is not initialized" >&2
  exit 1
fi

if [[ "${sealed}" != "False" && "${sealed}" != "false" ]]; then
  echo "OpenBao is sealed" >&2
  exit 1
fi

ui_html="$(curl "${curl_args[@]}" "${OPENBAO_ADDR}/ui/vault/auth?with=token")"
if ! grep -q "<title>OpenBao</title>" <<<"${ui_html}"; then
  echo "OpenBao UI shell was not detected" >&2
  exit 1
fi

if [[ -n "${OPENBAO_TOKEN}" ]]; then
  mounts_json="$(
    curl "${curl_args[@]}" \
      -H "X-Vault-Token: ${OPENBAO_TOKEN}" \
      "${OPENBAO_ADDR}/v1/sys/mounts"
  )"

  if ! grep -q '"kv/"' <<<"${mounts_json}"; then
    echo "kv/ mount was not found" >&2
    exit 1
  fi

  policy_json="$(
    curl "${curl_args[@]}" \
      -H "X-Vault-Token: ${OPENBAO_TOKEN}" \
      "${OPENBAO_ADDR}/v1/sys/policies/acl?list=true"
  )"

  if ! grep -q '"platform-admin"' <<<"${policy_json}"; then
    echo "platform-admin policy was not found" >&2
    exit 1
  fi
elif [[ "${SMOKE_REQUIRE_TOKEN_CHECKS}" == "true" ]]; then
  echo "OPENBAO_TOKEN or BOOTSTRAP_FILE must be provided when SMOKE_REQUIRE_TOKEN_CHECKS=true" >&2
  exit 1
fi

echo "OpenBao smoke verification passed for ${OPENBAO_ADDR}"
