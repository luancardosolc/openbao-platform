# Prompt 03 — Rekey seguro do OpenBao (manter dados) — 15/11/2026

Leia e execute este arquivo **por completo**. Ele substitui o bloqueio do `prompt-02` na etapa de backup/rekey. O Luan escolheu **rekey mantendo os dados**, feito **com segurança** e **sem ele precisar intervir**. Decisão registrada em 15/11/2026 (BRT).

Não rode `/aprovar`, não responda só `ok`, não faça `push`. Não execute `bw lock` nem `bw logout`. Não altere o servidor além do que este prompt autoriza, na ordem abaixo. Se algum passo for arriscado ou ambíguo, **pare e relate** — não improvise.

## Contexto

O `bootstrap.json` do OpenBao (unseal keys e root token) vazou na sessão desta aba ao usar `Invoke-HetznerRoot.ps1`: o helper só redigia a senha root, não a saída do comando. Trate essas chaves e o root token antigos como **comprometidos**. O cofre continua **selado**. O arquivo ainda está no disco. Nenhum item de backup válido ficou no Bitwarden na tentativa anterior.

O helper foi corrigido. Use os scripts novos. **Nunca** imprima, `cat`, registre em parecer ou cole no chat nenhum segredo (unseal keys, recovery keys, root token, conteúdo de `bootstrap.json`, sessão do Bitwarden).

## Ferramentas (já testadas com arquivo dummy em `/tmp`, depois apagado)

Tudo em `C:\Users\luanc\agent-tools\hetzner-root\`. Sessão Bitwarden via `Get-BwSession.ps1`. Pasta do cofre: `Hetzner`.

1. **Comandos não secretos** (saída redigida; recusa `bootstrap.json`, `*.key` e arquivos `unseal*`):

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-HetznerRoot.ps1 -Command 'id'
   ```

2. **Qualquer coisa secreta** (captura só em memória, grava no Bitwarden, `bw sync`, confere SHA-256 em processo; imprime apenas `ITEM`, `BYTES`, `SHA256_PREFIX` de 8 caracteres e `OK`/`FAIL`):

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-HetznerSecretToBitwarden.ps1 -Command 'cat /opt/openbao/bootstrap/bootstrap.json' -ItemName 'OpenBao prod / bootstrap antigo (comprometido 2026-11-15)'
   ```

3. **Trazer um item do Bitwarden para um arquivo só de root no servidor** (unseal/rekey no servidor, sem passar chaves pela tela; imprime apenas `PATH`, `BYTES`, `SHA256_PREFIX`, `OK`/`FAIL`). Depois use e faça `shred`:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-HetznerBitwardenToRemoteFile.ps1 -ItemName 'OpenBao prod / unseal+recovery (rekey 2026-11-15)' -RemotePath /root/hzroot-keys-from-bw.json
   ```

A conferência que vale é o SHA-256 das notas do item (e o prefixo impresso). O anexo do Bitwarden é tentativa extra; se o plano não aceitar anexo, as notas verificadas bastam. Não tente “confirmar” o conteúdo imprimindo-o.

## Ordem obrigatória

### (a) Backup do bootstrap atual (antes de qualquer rekey)

Com o script secreto, copie `/opt/openbao/bootstrap/bootstrap.json` (ou o caminho real, se for outro) para o Bitwarden, pasta `Hetzner`, item:

`OpenBao prod / bootstrap antigo (comprometido 2026-11-15)`

Faça `bw sync` (já é feito pelo script) e só prossiga se a saída for `OK`, com `BYTES` plausível e `SHA256_PREFIX` de 8 caracteres. Não abra o item no terminal. Anote no parecer só o nome do item, o tamanho e o prefixo do hash.

### (b) Unseal + rekey inteiramente no servidor

Não rode `operator rekey` no seu terminal com chaves visíveis. Suba e execute **como root**, no servidor, um script que:

- leia as chaves antigas **só** de `bootstrap.json` no disco (já copiado no passo a);
- faça o unseal;
- rode `operator rekey` (init/update até o threshold), **escrevendo as chaves novas** em um arquivo temporário só de root (por exemplo `/root/hzroot-rekey-new.json`, modo 600);
- não imprima as chaves novas no stdout que volte para esta sessão (o script deve escrever só códigos de saída e talvez hashes).

Em seguida, **mova** as chaves novas para o Bitwarden com o script secreto, item:

`OpenBao prod / unseal+recovery (rekey 2026-11-15)`

Confira `OK` (tamanho + prefixo SHA-256). Só então faça `shred` do arquivo temporário no servidor. As chaves antigas ficam inválidas depois do rekey; o backup do passo (a) permanece como registro do material comprometido, não para reutilizar.

### (c) Root token novo e revogação do antigo

Gere um root token novo no servidor (`generate-root` ou o fluxo equivalente do OpenBao), **direto para arquivo só de root**, e grave no Bitwarden com o script secreto (item claro, por exemplo `OpenBao prod / root token (rekey 2026-11-15)`). Não imprima o token.

Revogue o root token antigo. Confira que o token antigo **falha** (uma chamada inócua de API deve retornar erro de autenticação). Não cole o token antigo nem o novo em lugar nenhum. Se o token antigo só existir dentro do `bootstrap.json`, o script no servidor deve usá-lo lá, não nesta aba.

### (d) Resto do prompt-02 (só depois de a–c conferidos)

Siga o `prompt-02-openbao-remediacao-2026-11-15.md` e o OpenSpec `openbao-remediacao`, **mantendo os dados**:

- sair das flags `-dev*`;
- listener só na interface NetBird/privada (sem publish em `0.0.0.0`);
- storage persistente + TLS;
- teste de seal/unseal com as **chaves novas**, feitas **no servidor** (traga as chaves do Bitwarden com `Invoke-HetznerBitwardenToRemoteFile.ps1`, unseal/seal no host, `shred` do arquivo);
- `shred` do `bootstrap.json` **somente** depois de o backup no Bitwarden estar conferido e o serviço funcionar com as chaves novas.

Não apague o bootstrap antes dessa conferência.

### (e) Redigir o transcript local desta aba

Em `~\.claude\projects` (arquivos jsonl desta conversa), substitua as strings secretas vazadas por `[REDACTED]`. Faça isso **em processo**, com o mesmo tipo de redacção (tokens `hvs.`/`s.`, chaves, JSON de key/token/secret/password), **sem imprimir** as strings, **sem colar diffs** e **sem deixar cópia de backup** do arquivo ainda com os segredos. Escreva o arquivo já redigido no lugar (um temporário redigido, substitui o original, apaga o temporário). Relatar só: quantos arquivos, quantas substituições, e que não ficou backup.

### (f) Probes, parecer, commit local

Refaça os probes externos e as checagens internas (sem imprimir segredos). Acrescente evidências a um parecer (pode ser `pareceres\fase-openbao-remediacao-2026-11-15.md` ou um parecer novo desta data). Commit local + tag BRT + `CHANGELOG`, **sem push**.

## Regras inegociáveis

- Nunca `cat` / `Write-Output` / parecer / chat com o conteúdo de chaves, tokens ou `bootstrap.json`.
- Nunca use `Invoke-HetznerRoot.ps1` para ler arquivos secretos; ele deve recusar. Use só o script secreto.
- Nunca `bw lock` / `bw logout`.
- Sem `/aprovar`, sem `ok` como atalho, sem `push`.
- Pare e relate se o unseal, o rekey, o generate-root ou o bind da interface não estiverem claros no ambiente real (caminhos, binário `bao`/`docker exec`, número de keys do threshold, etc.).

Quando terminar (ou ao parar), relate o que foi feito, os nomes dos itens Bitwarden, tamanhos e prefixos SHA-256, o que falta, e o estado do serviço — sem segredos.
