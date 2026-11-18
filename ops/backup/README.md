# Backup do servidor (Hetzner)

- `server/setup-statebackup.sh`: usuário `statebackup` só para SFTP, com chroot em `/srv/statebackup`, `restrict,from=<IP NetBird do PC>` e `AllowUsers statebackup@<IP>`. Também instala o age e o recipient público.
- `server/server-state-backup.sh` + `.service` + `.timer` (04:30 UTC = 01:30 BRT, Persistent): `docker pause` do OpenBao e do netbird-server durante o tar (segundos, sem selar), depois zstd e `age -r`, saída em `/srv/statebackup/server-state` (mantém 3). O PC puxa às 02:00 e guarda nos dois repos restic.
- `server/openbao-restore-test.sh`: decifra o tar, sobe um OpenBao temporário em 127.0.0.1:18200, faz o unseal com as chaves do Bitwarden, confere o root token, os mounts e as policies, e destrói tudo.
- As imagens diárias da Hetzner continuam ligadas.
