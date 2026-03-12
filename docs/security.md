# Security

## Host Controls

- SSH key authentication only
- Root login disabled
- Password authentication disabled
- UFW restricts ingress to SSH and OpenBao API/UI
- Fail2ban protects SSH
- Docker bridge is isolated to OpenBao services

## OpenBao Controls

- TLS enabled by default with host-generated certificates
- Audit logging written to a dedicated persistent volume
- File storage kept on encrypted backup rotation
- KV v2 secrets engine enabled during bootstrap
- Baseline policy file included for operator access patterns

## Secrets Handling

- Infrastructure credentials are supplied via environment variables or GitHub Actions secrets.
- The server bootstrap artifact is encrypted before backup.
- Repository contents never include live credentials.

## Known Risk Envelope

This project optimizes for low operational cost on a single VPS. The automated unseal approach is acceptable for a lab, startup, or low-footprint environment, but a higher assurance deployment should replace it with cloud KMS or HSM-backed seal support.
