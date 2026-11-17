# Runbook: rekey do OpenBao prod (Hetzner), só com marcadores

Usado em 16/11/2026 depois do vazamento das chaves antigas. Nenhum segredo aparece na tela: toda saída do servidor passa por `Invoke-HetznerRoot.ps1 -MarkersOnly`, e segredo só vai servidor → Bitwarden (ou Bitwarden → arquivo root no servidor, que é apagado com `shred` logo depois).

Scripts: `workstation/hetzner-root/` (cópia de execução em `C:\Users\luanc\agent-tools\hetzner-root\`). PowerShell no Windows, sem WSL.

## 0. Pré-requisitos

```powershell
$env:BW_SESSION = & 'C:\Users\luanc\agent-tools\bw-auto-unlock\Get-BwSession.ps1'   # nunca bw lock/logout
$H = 'C:\Users\luanc\agent-tools\hetzner-root'
```

## 1. Backup do estado atual no Bitwarden (antes de mudar)

```powershell
& "$H\Invoke-HetznerBitwardenToRemoteFile.ps1" -ItemName 'OpenBao prod / unseal+recovery (rekey 2026-11-15)' -RemotePath /root/hzroot-unseal.json
# esperado: PATH, BYTES, SHA256_PREFIX, OK
```

Em 15/11, a fonte era `/opt/openbao/bootstrap/bootstrap.json`. Ela foi salva com `Invoke-HetznerSecretToBitwarden.ps1 -Command 'cat …' -ItemName 'OpenBao prod / bootstrap antigo (comprometido 2026-11-15)'` e depois apagada com `shred`.

## 2. Rekey (5 shares, threshold 3)

Copie `rekey-openbao.sh` para `/tmp/rekey-openbao.sh` no servidor (não tem segredo) e rode:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$H\Invoke-HetznerRoot.ps1" -MarkersOnly `
  -MarkerPattern '^(STATUS_BEFORE|UNSEAL_OK|REKEY_INIT_OK|NEW_KEYS_FILE_OK|REKEY_COMPLETE|FAIL)\b' `
  -ScriptFile .\ops\runbooks\rekey\rekey-openbao.sh
```

Esperado: `STATUS_BEFORE` → `UNSEAL_OK` → `REKEY_INIT_OK shares=5 threshold=3` → `NEW_KEYS_FILE_OK count=5` → `REKEY_COMPLETE`.
Variáveis (env, opcionais): `SRC` (padrão `/root/hzroot-unseal.json`), `RESOLVE` (padrão `46.224.228.253:8200:100.102.58.164`, para validar o TLS pelo CN público e conectar pela VPN) e `ORIGEM`.

## 3. Chaves novas → Bitwarden, conferidas

```powershell
& "$H\Invoke-HetznerSecretToBitwarden.ps1" -Command 'cat /root/openbao-rekey-work/new-keys.json' -ItemName 'OpenBao prod / unseal+recovery (rekey AAAA-MM-DD)'
```

Confira de volta com `Invoke-HetznerBitwardenToRemoteFile.ps1` para `/root/hzroot-check.json` e rode `cmp` com o original, imprimindo só `CMP_OK`/`FAIL` em `-MarkersOnly`. Só depois disso:

```sh
shred -u /root/openbao-rekey-work/* /root/hzroot-* /tmp/rekey-openbao.sh
```

## 4. Root token novo e revogação do antigo

Feito em 16/11, na ordem abaixo. Os comandos exatos não foram versionados; aqui está o procedimento equivalente:

1. Com o root atual (arquivo root via `Invoke-HetznerBitwardenToRemoteFile.ps1`, header com `curl -H @arquivo`, nunca em argv): `POST /v1/auth/token/create-orphan` com `{"policies":["root"]}`. Grave o JSON em `/root/openbao-rekey-work/new-root.json` (modo 600).
2. `Invoke-HetznerSecretToBitwarden.ps1 -Command 'cat /root/openbao-rekey-work/new-root.json' -ItemName 'OpenBao prod / root token (AAAA-MM-DD)'` e conferência com `cmp`.
3. Com o token novo, `POST /v1/auth/token/revoke` no token antigo. Esperado: 204. Depois `lookup-self` com o antigo deve dar 403 e com o novo, 200 (marcadores).
4. `shred` em todos os arquivos.

## 5. Unseal depois de restart

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$H\Invoke-OpenBaoUnseal.ps1"
# UNSEAL_BEFORE sealed=true health=503 ... UNSEAL_DONE sealed=false health=200, UNSEAL_SHRED ok, OK
```

## 6. Vazamento local (se algo aparecer na tela)

```powershell
& "$H\Invoke-LeakRedaction.ps1" -ItemName '<item com os valores vazados>' -Roots "$env:USERPROFILE\.claude","$env:APPDATA\orca" -Since 'AAAA-MM-DD HH:MM'          # conta
& "$H\Invoke-LeakRedaction.ps1" ... -Apply                                                                                                              # redige
```

Evidências da execução de 15–16/11: `docs/pareceres/prompt-03-execucao-2026-11-15.md`.
