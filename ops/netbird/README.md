# NetBird: policy do PC para o OpenBao (TCP 8200)

`Set-NetBirdPolicy.ps1` garante, de forma idempotente, a policy `pc-luan -> openbao 8200` (id `dbu3emqtm4ms73cqtg70`):
accept, TCP, so a porta 8200, nao bidirecional, origem `admin-pc` (so `luan-nitro5`, 100.102.188.162) e destino `hetzner-vps`
(so `openbao-platform-prod-openbao`, 100.102.58.164). Nao cria nem apaga grupos e nao mexe em outras policies.

```powershell
$env:BW_SESSION = & 'C:\Users\luanc\agent-tools\bw-auto-unlock\Get-BwSession.ps1'   # nunca bw lock/logout
powershell -NoProfile -ExecutionPolicy Bypass -File .\ops\netbird\Set-NetBirdPolicy.ps1 -CheckOnly   # so confere
powershell -NoProfile -ExecutionPolicy Bypass -File .\ops\netbird\Set-NetBirdPolicy.ps1              # corrige se divergir
# esperado: GROUP_OK src=admin-pc dst=hetzner-vps / POLICY_OK id=dbu3emqtm4ms73cqtg70
curl.exe -sk -o NUL -w "%{http_code}" https://100.102.58.164:8200/v1/sys/health   # 200
```

Token: item Bitwarden `NetBird / API token owner (2026-11-17)` (pasta Hetzner, PAT do dono, 40 chars, validade 365 dias).

## Historico (17/11/2026)

- 07:22 BRT: o primeiro PAT vazou na saida de uma ferramenta do Codex. Foi revogado e saiu da lista de tokens, e a API agora responde 404 a ele.
  O substituto foi do DOM direto para o Bitwarden (sha256 diferente).
- A primeira versao do script (Codex) caiu no array embrulhado do `Invoke-RestMethod` do PS 5.1 e criou 4 grupos com os dois peers
  (`pc-luan`, `openbao-server`, `pc-luan-openbao-8200`, `openbao-server-openbao-8200`). A policy foi corrigida para `admin-pc -> hetzner-vps`;
  os 4 grupos ficaram sem uso.
- 08:47 BRT: o Luan autorizou apagar os 4. `Remove-NetBirdGroups.ps1` (ids explicitos; recusa All/admin-pc/hetzner-vps; checa referencias em 9 endpoints: policies, routes, DNS, setup keys, users, posture checks, accounts, networks) -> `refs=0`, `GROUP_DELETED` x4, 2a execucao `GROUP_ABSENT` x4. Use `-CheckOnly` para simular.
- Os logs locais com o PAT vazado foram redigidos com `Invoke-LeakRedaction.ps1 -DpapiValueFile` (.jsonl do Codex e `thread_history_1.sqlite`, troca de mesmo tamanho). Na nova varredura: 0.
