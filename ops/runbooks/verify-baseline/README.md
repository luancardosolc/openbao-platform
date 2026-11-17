# Runbook: conferir o baseline do OpenBao prod (só marcadores)

Use depois de qualquer recreate/restart + unseal (`Invoke-OpenBaoUnseal.ps1`). Nenhum segredo aparece na tela.

```powershell
$env:BW_SESSION = & 'C:\Users\luanc\agent-tools\bw-auto-unlock\Get-BwSession.ps1'   # nunca bw lock/logout
$H = 'C:\Users\luanc\agent-tools\hetzner-root'
& "$H\Invoke-HetznerBitwardenToRemoteFile.ps1" -ItemName 'OpenBao prod / root token (2026-11-16)' -RemotePath /root/hzroot-root.tok
powershell -NoProfile -ExecutionPolicy Bypass -File "$H\Invoke-HetznerRoot.ps1" -MarkersOnly `
  -MarkerPattern '^(BASELINE_|FAIL)' -ScriptFile .\ops\runbooks\verify-baseline\verify-openbao-baseline.sh
```

Esperado (16/11/2026): `BASELINE_SEAL sealed=false health=200`, `BASELINE_TOKEN lookup_self=200`,
`BASELINE_MOUNTS cubbyhole,identity,kv,sys`, `BASELINE_POLICIES count=5`, `BASELINE_KV keys=3`, `BASELINE_OK`, `BASELINE_SHRED ok`.
O script faz `shred` do arquivo do token e do header no `trap EXIT`. Ajuste `EXP_*` por env se o baseline mudar.

## Limpeza do bootstrap (16/11/2026, 22:42 BRT)

`/opt/openbao/bootstrap/` foi removida do servidor:

- `docker-compose.yml` copiado para `docker-compose.yml.bak-20261116-2242` (sha256 `7aad28cccfb3…`) e o volume `/opt/openbao/bootstrap:/openbao/bootstrap` removido; `docker compose config -q` ok; `up -d --force-recreate openbao`.
- Unseal com `Invoke-OpenBaoUnseal.ps1` (sealed=false, health=200) e baseline acima = `BASELINE_OK`.
- `bootstrap.json.enc` (912 B, sha256 `dc7e00a944e0…`): `shred -u`. Backup no Bitwarden `OpenBao prod / bootstrap.json.enc antigo base64 (2026-11-15)` conferido antes (base64 1216 chars → 912 B, mesmo sha256).
- `bootstrap-openbao.sh` (2505 B, sha256 `ebf4705424d0…`): `shred -u`. É byte a byte o template `infra/ansible/templates/openbao/bootstrap-openbao.sh.j2` renderizado com `46.224.228.253:8200`, já versionado.
- Pasta removida (`rmdir`).

Rollback: `cp -p /opt/openbao/docker-compose.yml.bak-20261116-2242 /opt/openbao/docker-compose.yml && mkdir -p /opt/openbao/bootstrap && docker compose up -d --force-recreate openbao` e unseal.
