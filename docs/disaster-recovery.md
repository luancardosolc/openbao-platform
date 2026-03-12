# Disaster Recovery

## Recovery Path

1. Provision a new server with `make deploy`.
2. Restore the latest encrypted backup with `make restore`.
3. Re-run OpenBao bootstrap validation.
4. Confirm `/v1/sys/health` and UI reachability.

## Failure Domains

- Host loss
- Persistent volume corruption
- Misconfiguration introduced in automation

## Recovery Objectives

- RTO: under 1 hour with credentials and backup passphrase available
- RPO: 24 hours under the default daily backup schedule

## Preconditions

- Provider credentials available
- SSH key access available
- Backup encryption passphrase available
