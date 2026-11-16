# Disaster Recovery

## Status: recovery has not been proven

The sample flow below is not approved for the current production host. `make deploy` provisions a generic instance and may create resources; `make restore` extracts files directly over `/`. Do not run either against the live Hetzner environment. The current repository model does not match the live server's operator user, firewall, or NetBird stack.

No offsite, verified backup or isolated restore has been demonstrated. RTO/RPO are therefore **unknown**, not the aspirational values from older examples.

## Recovery prerequisites

- Privileged inventory of OpenBao, NetBird, containers, volumes, configs, firewall, and secret dependencies.
- Encrypted, app-consistent backup outside the Hetzner VPS, plus a separate recovery key path.
- Working Hetzner console/NetBird/SSH access and documented, tested operator identities.
- A disposable isolated Ubuntu environment to restore and exercise both applications.
- Verified console access and an approved maintenance/recovery window before any production restart or restore.

## Drill acceptance

1. Restore to an isolated host/VM; never overlay production paths.
2. Verify OpenBao initialized/unsealed state and test-data read/write using a scoped temporary credential.
3. Verify NetBird management UI, API and a test peer connection.
4. Record actual restore duration, recovery point age, failures, CPU/RAM/disk overhead, and cleanup.
5. Update the backup and health checks with the evidence; set RTO/RPO only after Luan approves them.

See [backup strategy](backup-strategy.md) and the current implementation record at `C:\Users\luanc\projects\projects-knowledge-base\wiki\central-pesquisas-2026-10-26\hetzner-implementacao-2026-10-27.md`.
