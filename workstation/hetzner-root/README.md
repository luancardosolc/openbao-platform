# Helpers root no Hetzner

SSH como `luan` (NetBird `100.102.58.164`) e `su` com PTY. A senha root sai so da memoria, do item Bitwarden `luan/hetzner-openbao-root` (sessao via `Get-BwSession.ps1`). Nao altere `C:\Users\luanc\.ssh\config`. Nao rode `bw lock` nem `bw logout`.

## Comandos normais (saida redigida)

`Invoke-HetznerRoot.ps1` imprime a saida do comando, mas redige tokens (`hvs.` / `s.`), unseal keys, campos JSON com key/token/secret/password, PEM e blobs hex/base64 longos. Recusa ler `bootstrap.json`, `*.key` e arquivos `unseal*`. Para isso, use o script secreto.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-HetznerRoot.ps1 -Command 'id'

powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-HetznerRoot.ps1 -Command 'docker ps'
```

## Segredos para o Bitwarden (nunca imprime o payload)

`Invoke-HetznerSecretToBitwarden.ps1` captura a saida so em memoria, grava na pasta `Hetzner` (nota + anexo), faz `bw sync` e confere o SHA-256 em processo. Imprime apenas `ITEM`, `BYTES`, `SHA256_PREFIX` (8 chars) e `OK`/`FAIL`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-HetznerSecretToBitwarden.ps1 -Command 'cat /opt/openbao/bootstrap/bootstrap.json' -ItemName 'OpenBao prod / bootstrap antigo (comprometido 2026-11-15)'
```

## Segredos do Bitwarden para um arquivo no servidor

`Invoke-HetznerBitwardenToRemoteFile.ps1` le o item em memoria e grava um arquivo so de root no servidor (para unseal/rekey). Imprime apenas `PATH`, `BYTES`, `SHA256_PREFIX` e `OK`/`FAIL`. Apague o arquivo com `shred` depois de usar.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-HetznerBitwardenToRemoteFile.ps1 -ItemName 'OpenBao prod / unseal+recovery (rekey 2026-11-15)' -RemotePath /root/hzroot-keys-from-bw.json
```

## Python 64-bit obrigatorio (fix 2026-11-15)

Os helpers usam um `python.exe` 64-bit real (padrao `%LOCALAPPDATA%\Programs\Python\Python312\python.exe`, ou `$env:HZ_PYTHON`).
O shim do pyenv (`python.bat` -> 3.13.1-win32) era 32-bit: sob WOW64 o `C:\Windows\System32\OpenSSH\ssh.exe` fica invisivel,
o `run-capture.py` dava `WinError 2` e saia com rc=2 (`helper upload rc=2`). Tambem: stdout agora e lido em bytes crus,
o envio para arquivo root faz staging em `/tmp` e `install -m 600`, e os arquivos de captura em `/tmp` tem nome fixo e sempre sao apagados.

## Modo -MarkersOnly (2026-11-15)

`Invoke-HetznerRoot.ps1 -MarkersOnly [-MarkerPattern <regex>]` guarda toda a saida so em memoria e imprime APENAS as linhas que casam com o padrao
(case-sensitive; padrao `^(STATUS_BEFORE|UNSEAL_OK|REKEY_INIT_OK|NEW_KEYS_FILE_OK|REKEY_COMPLETE|FAIL)\b`), cortadas em 120 chars e redigidas,
mais `[markers-only] markers=N dropped_lines=M`. Neste modo a recusa de caminhos secretos e liberada. O exit code do comando remoto e repassado.

## Unseal deterministico (2026-11-16)

`Invoke-OpenBaoUnseal.ps1` faz o unseal do OpenBao prod depois de qualquer restart/recreate (o cofre volta selado):
grava o item `OpenBao prod / unseal+recovery (rekey 2026-11-15)` em `/root/hzroot-unseal.json` (so root), envia 3 chaves
via `jq -c | curl --data @-` (sem argv), imprime so `UNSEAL_*` e faz `shred` do arquivo (trap EXIT). Termina com `OK` ou `FAIL`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-OpenBaoUnseal.ps1
```

Padrao `-ApiAddr https://100.102.58.164:8200` (desde 16/11 a API so escuta no IP NetBird). Rollback para o compose antigo: use `-ApiAddr https://127.0.0.1:8200`.
Obs.: `Invoke-HetznerRoot.ps1` escreve via `[Console]::Out`; para capturar a saida em variavel, chame-o num processo `powershell -File` filho.

## Redacao de vazamentos locais (2026-11-16)

`Invoke-LeakRedaction.ps1` le os valores vazados SO em memoria de um item Bitwarden e procura (tolerando espaco, `\n` e ANSI entre caracteres)
em logs locais. Sem `-Apply` so conta. Com `-Apply`: copia `.pre-redact.bak`, troca atomica, confere 0 ocorrencias e JSON valido, zera e apaga o backup.
Nunca imprime valores, so caminho e contagens.
Desde 17/11: `-ValueMode Raw` (notes do item = 1 valor, ex. PAT) ou `-DpapiValueFile <arq>` (valor cifrado com DPAPI do usuario, util depois de trocar o item);
arquivos travados sao lidos com FileShare.ReadWrite; `.sqlite`/`.db` usam troca de mesmo tamanho no lugar (confira com `PRAGMA integrity_check`).
## Fonte canonica

A fonte canonica destes scripts e `C:\Users\luanc\projects\personal\openbao-platform\workstation\hetzner-root\` (versionado). `C:\Users\luanc\agent-tools\hetzner-root\` e a copia de execucao: altere no repo e copie para ca.

