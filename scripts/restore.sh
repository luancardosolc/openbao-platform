#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_PATH="${1:-}"
PASSPHRASE="${BACKUP_PASSPHRASE:-}"

if [[ -z "${ARCHIVE_PATH}" || -z "${PASSPHRASE}" ]]; then
  echo "usage: BACKUP_PASSPHRASE=... $0 /path/to/archive.enc" >&2
  exit 1
fi

TMP_ARCHIVE="$(mktemp /tmp/openbao-restore.XXXXXX.tar.gz)"
openssl enc -d -aes-256-cbc -pbkdf2 -in "${ARCHIVE_PATH}" -out "${TMP_ARCHIVE}" -pass "pass:${PASSPHRASE}"
tar -xzf "${TMP_ARCHIVE}" -C /
rm -f "${TMP_ARCHIVE}"
