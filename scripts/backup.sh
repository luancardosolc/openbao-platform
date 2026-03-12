#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${ROOT_DIR}/backups"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
ARCHIVE="${BACKUP_DIR}/openbao-${TIMESTAMP}.tar.gz"
ENCRYPTED="${ARCHIVE}.enc"
PASSPHRASE="${BACKUP_PASSPHRASE:-}"

if [[ -z "${PASSPHRASE}" ]]; then
  echo "BACKUP_PASSPHRASE must be set" >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"
tar -czf "${ARCHIVE}" -C /opt openbao
openssl enc -aes-256-cbc -salt -pbkdf2 -in "${ARCHIVE}" -out "${ENCRYPTED}" -pass "pass:${PASSPHRASE}"
rm -f "${ARCHIVE}"
echo "${ENCRYPTED}"
