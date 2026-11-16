# Backup Strategy

## Status: not production-ready

Do not use `make backup` or `make restore` for the live Hetzner server until this section is replaced with an app-aware, offsite workflow and a restore has been tested in isolation.

The live host currently uses OpenBao's `file` storage backend under `/opt/openbao/data`. The repository's `scripts/backup.sh` merely tars `/opt/openbao` into a local checkout, encrypts with AES-CBC using the passphrase as a process argument, has no offsite destination, and omits NetBird state. A live file-backend copy is not proven consistent. `scripts/restore.sh` extracts an archive directly over `/` without path validation or a target confirmation. Neither script proves that a backup is recoverable.

## Required design before production use

1. Inventory the actual OpenBao and NetBird data/configuration paths and identify a consistency method for each. Do not assume a Docker volume name or the repository's sample compose file matches production.
2. Select an app-aware OpenBao backup strategy. A supported storage snapshot or a planned cold backup may require migration or downtime; test it in an isolated environment first.
3. Select an encrypted offsite destination outside the VPS. Get the exact recurring cost and retention confirmed before creating a paid resource. Do not store the only recovery copy on the VPS or inside this Git repository.
4. Encrypt client-side without putting a passphrase in command-line arguments. Separate encryption/recovery material from the backup destination.
5. Verify every artifact with checksum, age/retention metadata, and a restore drill that checks OpenBao initialization/unseal, representative non-secret test data, NetBird connectivity, and measured RTO/RPO.
6. Alert on last successful backup age, failed transfer, verification failure, and restore-drill age.

## Acceptance criteria

- At least one encrypted copy is stored outside Hetzner and can be read without the live OpenBao instance.
- Restore to an isolated host or VM has completed; production paths were not overwritten.
- The restored apps pass functional checks and measured recovery times meet Luan's chosen RTO/RPO.
- A failure alert reaches Meubot independently of the protected server.

Current evidence: [local read-only operations checks](../ops/README.md). Cross-project evidence is in `C:\Users\luanc\projects\projects-knowledge-base\wiki\central-pesquisas-2026-10-26\hetzner-implementacao-2026-10-27.md`.
