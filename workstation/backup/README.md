# Backup de estado do PC (restic)

- `statebackup.config.psd1`: o que entra e o que sai (sem binários, venvs, node_modules nem caches).
- `Invoke-StateBackup.ps1 -Mode Init|Backup|Check|RestoreTest|Freshness`.
- `sqlite_snapshot.py`: cópias consistentes dos SQLite (API de backup), em `%LOCALAPPDATA%\StateBackup\staging\sqlite`.
- `sqlite_check.py`: `integrity_check` nos testes de restore.
- `Register-StateBackupTasks.ps1`: tarefas Nightly (02:00), Check (domingo) e Freshness (de hora em hora).
- Segredos em DPAPI em `%LOCALAPPDATA%\StateBackup\` (`restic-pass.dpapi`, `age-identity.dpapi`). A fonte da verdade é o Bitwarden.
- Runbook de recuperação: `ops/runbooks/restore-pc/README.md`.
