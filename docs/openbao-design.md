# OpenBao Design

## Runtime

OpenBao runs in Docker Compose with a dedicated bridge network and persistent host mounts for:

- `/opt/openbao/data`
- `/opt/openbao/config`
- `/opt/openbao/logs`
- `/opt/openbao/tls`

## Configuration

- Listener bound to `0.0.0.0:8200` with TLS
- Cluster listener on `8201`
- File storage backend
- Audit device configured to write JSON logs
- UI enabled

## Bootstrap

The first deployment runs a bootstrap helper that:

1. Initializes OpenBao if it has not been initialized.
2. Unseals using generated Shamir keys.
3. Enables the KV v2 secrets engine.
4. Writes baseline policies.
5. Stores an encrypted recovery artifact on disk for backup.

## Operational Posture

The platform favors deterministic automation over manual console steps. Higher-security production environments should replace local bootstrap artifacts with externalized seal and secret escrow services.
