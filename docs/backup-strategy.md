# Backup Strategy

## Scope

Daily encrypted backups include:

- OpenBao file storage data
- OpenBao configuration files
- TLS assets
- Bootstrap and recovery artifacts

## Implementation

- `scripts/backup.sh` creates a timestamped archive
- `openssl enc` encrypts the archive with an operator-supplied passphrase
- `scripts/restore.sh` restores the archive onto a prepared host

## Retention

- Default daily cadence
- Local retention controlled by operator policy
- Audit logs retained separately on the VPS

## Validation

`tests/deployment-tests.sh` and `tests/security-tests.sh` include checks for backup directories and bootstrap artifacts.
