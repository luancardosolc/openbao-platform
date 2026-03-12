#!/usr/bin/env bash
set -euo pipefail

OPENBAO_ADDR="${OPENBAO_ADDR:-}"
REQUIRE_DEPLOYMENT_TESTS="${REQUIRE_DEPLOYMENT_TESTS:-false}"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
  && docker ps --format '{{.Names}}' | grep -q '^openbao$'; then
  docker ps --format '{{.Names}} {{.Status}}' | grep -q '^openbao '
elif [[ "${REQUIRE_DEPLOYMENT_TESTS}" == "true" ]]; then
  echo "docker daemon is not available for deployment validation" >&2
  exit 1
fi

if [[ -n "${OPENBAO_ADDR}" ]] && command -v curl >/dev/null 2>&1; then
  status_code="$(curl -k -s -o /dev/null -w '%{http_code}' "${OPENBAO_ADDR}/v1/sys/health" || true)"
  case "${status_code}" in
    200|429|472|473|501|503) ;;
    *)
      echo "unexpected health status: ${status_code}" >&2
      exit 1
      ;;
  esac
elif [[ "${REQUIRE_DEPLOYMENT_TESTS}" == "true" ]]; then
  echo "OPENBAO_ADDR must be set when REQUIRE_DEPLOYMENT_TESTS=true" >&2
  exit 1
fi
