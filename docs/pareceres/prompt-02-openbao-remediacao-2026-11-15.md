# Prompt 02 — Remediação do OpenBao (sair do modo dev, bind só na VPN, rotacionar root, apagar bootstrap)

**Data:** 15/11/2026 (America/Sao_Paulo, UTC−3 / BRT)  
**Destinatário:** Claude Code nesta mesma aba (permissões de bypass já ligadas)  
**Repositório de trabalho:** `C:\Users\luanc\projects\conectores\whatsapp-business-mcp`  
**Aprovação:** o Luan (Luan Cardoso) aprovou esta remediação em 15/11/2026, com uma condição inegociável: **tudo que for segredo e que possamos precisar de novo deve ser copiado para o Bitwarden antes de qualquer alteração, e nunca perdido.**  
**Instrução:** leia este arquivo por completo e execute-o integralmente, **na ordem abaixo**. Não peça um resumo do prompt; comece a trabalhar. Se algum passo for arriscado, ambíguo ou divergir do que está aqui, **pare e relate nesta aba** — não improvise.

---

## 0. Papel, autonomia e limites

Você implementa a remediação do OpenBao no servidor Hetzner. O Luan acompanha nesta aba. Outro agente (Zeca / Grok Bot) só precisa intervir em parede de login, 2FA ou ferramenta que você não consiga usar daqui.

**Autonomia máxima no que for reversível e no que já foi aprovado neste prompt** (backup no Bitwarden, OpenSpec, inspeção, a própria remediação na ordem das seções 1–6, commits e tags locais). **Nunca imprima segredos**: unseal keys, recovery keys, root tokens, senhas, `BW_SESSION`, conteúdo de `bootstrap.json`, export do cofre, hashes só podem ser usados in-process (para conferência) e no máximo você relata “hash conferido, N caracteres, tipo X” — nunca o valor.

**Não faça e não peça:**

- `git push` (commit e tag locais são livres; **sem push** até o Luan pedir).
- `/aprovar` ou um “ok” em nome do Luan.
- `bw lock` ou `bw logout` (regra inegociável da máquina; o cofre deve permanecer utilizável pelos agentes).
- Alterar DNS, Cloud Firewall, ACL NetBird, ou o webhook da Meta neste prompt.
- Publicar wiki no Hetzner.
- “Corrigir” o arquivo `C:\Users\luanc\.ssh\config` (o OpenSSH recusa por ACL de `CodexSandboxUsers`; use um config temporário, por exemplo em `%TEMP%\ssh-vps-readonly.conf`, e não altere o config oficial).

**Ambiente (obrigatório):**

- PC do Luan, **PowerShell**. **Proibido WSL.** **Proibido Cursor.**
- cwd do repo: `C:\Users\luanc\projects\conectores\whatsapp-business-mcp` (esta aba pode ter começado em `C:\Users\luanc\projects`).
- SSH: usuário `luan`, Host típico `vps`, HostName NetBird `100.102.58.164`, IdentityFile `C:\Users\luanc\.ssh\ed25519_hetzner_acer_2026`, `IdentitiesOnly yes`. Se o Python for 32-bit, use `C:\Windows\Sysnative\OpenSSH\ssh.exe` (não `System32`, por causa do WOW64).
- Comandos privilegiados: **`su` com PTY**, senha root lida do Bitwarden item **`luan/hetzner-openbao-root`** (não da memória, não de arquivo temporário antigo). Não imprima a senha. Não altere a senha do usuário `luan` neste prompt, a menos que seja estritamente necessário para um passo aprovado — e, se trocar qualquer senha, grave no Bitwarden **antes/na hora**.
- Bitwarden CLI: obtenha sessão **somente** com:

```powershell
$env:BW_SESSION = & 'C:\Users\luanc\agent-tools\bw-auto-unlock\Get-BwSession.ps1'
```

  (atribua o resultado; não rode o script solto no terminal, para a sessão não ir para a tela). Nunca imprima `BW_SESSION`. Pasta do cofre para estes itens: **Hetzner**.

---

## 1. Contexto já inspecionado (confira; não assuma cegamente)

Evidências de 15/11/2026 estão em `pareceres\fase-b-saidas-2026-11-15.md` (seção 6) e no OpenSpec `webhook-hetzner-seguro`. Releia e **reconfirme no servidor** antes de mudar qualquer coisa. Resumo do que já foi visto (pode estar incompleto ou ter mudado):

- Host: `openbao-platform-prod-openbao` (Hetzner id `123556968`, projeto `13778771`). IP público `46.224.228.253`, privado `10.42.0.2`, NetBird `100.102.58.164` (`wt0`).
- Container `openbao` (`openbao/openbao:2.2.0`), compose em `/opt/openbao/docker-compose.yml`, rede `openbao_openbao_net` (`172.18.0.2`). Portas **`8200` e `8201` publicadas em `0.0.0.0` e `::`**.
- Processo dentro do container (usuário `openbao`):

```text
bao server -config=/openbao/config -dev-root-token-id= -dev-listen-address=0.0.0.0:8200
```

  Ou seja: há **flags de modo dev** no processo, mesmo existindo `openbao.hcl` com `storage "file"` (`path = "/openbao/file"`, bind do host `/opt/openbao/data`), `ui = true`, TLS ligado (`/openbao/tls/openbao.crt` e key), `listener` em `0.0.0.0:8200` / cluster `0.0.0.0:8201`, `api_addr = https://46.224.228.253:8200`.

- **Ponto crítico:** modo dev costuma manter dados **em memória**. O `openbao.hcl` sugere storage persistente em arquivo. Você **precisa confirmar o que está de fato em uso** (dev in-memory vs file storage) antes de reiniciar ou trocar o comando. Se os dados vivos estiverem só na memória, um restart mal feito **apaga o cofre**.
- Arquivo de bootstrap no host: **`/opt/openbao/bootstrap/bootstrap.json`** (não está na raiz `/opt/openbao/bootstrap.json`; o diretório `bootstrap` é volume bind em `/openbao/bootstrap`). Contém `unseal_keys_b64` (5 shares), `unseal_keys_hex`, `unseal_shares` / `unseal_threshold`, `recovery_keys_*` e **`root_token`**. Os valores **nunca** devem aparecer em parecer, log, chat ou commit.
- UFW: `8200/tcp` DENY de anywhere e ALLOW de `10.100.0.0/16`; sem regra para `8201`. `DOCKER-USER` está vazia; o DNAT do Docker publica 8200/8201. O **Cloud Firewall** hoje não tem 8200/8201 (sondas externas deram timeout); mesmo assim o bind em `0.0.0.0` é inaceitável.
- `INPUT -i wt0 -j ACCEPT` (VPN liberada no host).
- Senha root Linux já foi resetada no console (sem Rescue e sem power cycle) e gravada no item `luan/hetzner-openbao-root`. Um arquivo temporário local dessa senha **já foi apagado** depois da gravação; não o procure, use o Bitwarden.

O webhook WhatsApp (prompt 01 / OpenSpec `webhook-hetzner-seguro`) **não é o objeto desta remediação**. Não misture deploy de webhook, DNS ou Meta aqui. Você pode (e deve) registrar a remediação como mudança OpenSpec **dentro** de `webhook-hetzner-seguro` ou como **change irmã**, para o rollback e o `tasks.md` ficarem explícitos.

---

## 2. Objetivo

Deixar o OpenBao em **modo servidor não-dev**, com **storage persistente + TLS**, escutando **somente na interface NetBird / rede privada** (sem publish em `0.0.0.0` / `::`), com **root token novo** (o antigo revogado), chaves de unseal/recovery e o bootstrap **fora do disco** — mas **somente depois** de tudo isso estar de backup verificado no Bitwarden, do serviço estar no ar, e de nada que use o OpenBao ter quebrado.

---

## 3. Ordem de trabalho (obrigatória)

Não pule etapas. Não apague `bootstrap.json`, não reinicie o container, não troque o `command` e não rode `operator generate-root` / `token revoke` antes dos backups verificados das seções 3.1 e 3.2.

### 3.0 OpenSpec e plano de rollback (antes de mudar o servidor)

Crie ou estenda uma change OpenSpec para esta remediação: ou um item claro dentro de `webhook-hetzner-seguro`, ou uma change **irmã** (nome explícito, por exemplo `openbao-remediacao`). Inclua:

- Motivação e estado atual (dev flags, bind `0.0.0.0`, bootstrap no disco, Cloud Firewall vs UFW vs `DOCKER-USER`).
- Alvo: modo `server` sem flags `-dev*`, storage persistente alinhado ao `openbao.hcl` (se a inspeção confirmar), TLS, listener/publish **somente** no IP NetBird (`100.102.58.164`) e, se fizer sentido após inspeção, o IP privado da LAN — **nunca** `0.0.0.0`. Não abra 8200/8201 no Cloud Firewall.
- Rotação do root token e destino das chaves no Bitwarden (pasta **Hetzner**).
- Remoção do `bootstrap.json` do disco só no final.
- **Plano de rollback** concreto: como voltar o compose/hcl anteriores, como unseal com as chaves antigas (que estarão no Bitwarden), como republicar as portas se precisar, cópias dos arquivos de config que você vai alterar (`docker-compose.yml`, `openbao.hcl`, unit se houver). Guarde essas cópias em um lugar seguro no host (não no git com segredos) e anote o caminho no parecer.
- Critérios de verificação (sondas externas e checagens internas).

Deixe o OpenSpec commitado localmente quando estiver coerente; não espere o fim da remediação para isso.

### 3.1 ANTES de qualquer mudança no OpenBao: backup do bootstrap no Bitwarden

Esta seção é bloqueante. Sem ela, **não altere o servidor**.

1. Obtenha a sessão do `bw` com `Get-BwSession.ps1` (comando da seção 0). Nunca `bw lock` / `bw logout`.
2. Com `su` (senha de `luan/hetzner-openbao-root`), leia `/opt/openbao/bootstrap/bootstrap.json` **só em memória/processo**. Não copie o arquivo em claro para o repo, para `pareceres\`, para o chat, para o histórico do PowerShell nem para um caminho mundano no Desktop. Se precisar de arquivo de trabalho no PC, use `%TEMP%` com ACL só do usuário `luanc`, e apague com overwrite depois.
3. Grave no Bitwarden, pasta **Hetzner**, um item com nome explícito, no espírito de:

   **`OpenBao prod / unseal+recovery+root (bootstrap 2026-03)`**

   (ajuste o nome só se já existir item equivalente; não duplique chaves em dois itens sem deixar o vínculo claro nas notas.)

   O item deve conter, em campos ocultos ou notas estruturadas (sem logar valores):

   - todas as **unseal keys** (b64 e hex, se existirem);
   - todas as **recovery keys**, se existirem (mesmo que vazias, registre o fato “recovery vazio” sem inventar chaves);
   - `unseal_shares` e `unseal_threshold` (e equivalentes de recovery);
   - o **root token** atual;
   - notas: data 2026-11-15, origem `/opt/openbao/bootstrap/bootstrap.json`, host `openbao-platform-prod-openbao`, “backup pré-remediação; a senha/token antigos ficam no histórico do Bitwarden se forem trocados depois”.

4. Anexe também uma **cópia cifrada** do `bootstrap.json` (anexo do item). O anexo no cofre já é cifrado pelo Bitwarden; ainda assim, não deixe uma cópia em claro no disco depois de anexar.
5. `bw sync`.
6. **Verifique a leitura de volta in-process:** baixe/leia o item e o anexo e compare **hash** (SHA-256) com o arquivo original, no mesmo processo, sem imprimir conteúdo nem o hash completo se ele puder vazar material (prefira “hashes iguais, N bytes, M shares”). Só avance se a conferência passar.
7. Registre no parecer apenas: nome do item, pasta, prefixo do id, quantidade de shares/campos, “sync ok”, “hash conferido”. Sem valores.

### 3.2 Inventário e export do que está VIVO no OpenBao (modo dev pode estar só na memória)

**Faça isto ainda com o processo atual no ar**, antes de reiniciar, trocar flags `-dev*` ou recriar o container.

1. Confirme se o storage persistente do `openbao.hcl` **está mesmo sendo usado**: o que há em `/opt/openbao/data` (montado em `/openbao/file`)? O processo está em modo dev de verdade (dados voláteis) ou o `-dev-listen-address` / `-dev-root-token-id=` (vazio) são só resíduos do entrypoint com storage file? Use status/sela, `bao status` (sem vazar token), inspeção de mounts, mtime dos arquivos de storage, e a API se autenticar com o root token **sem imprimi-lo**.
2. Se houver qualquer dúvida de que os dados vivos não estejam 100% no disco, trate como **volátil**: o export desta seção é a única cópia.
3. Inventarie e exporte **tudo** que possa ser necessário de novo:
   - mounts (`secret/`, `kv`, auth methods, audit devices);
   - policies e ACL;
   - auth methods e suas configs (sem despejar credenciais no chat);
   - secrets/engines e o conteúdo acessível com o token atual (kv, etc.);
   - entidades, grupos, leases relevantes, certificados emitidos se houver;
   - qualquer coisa que MeuBot, compras, backup, NetBird ou outro serviço do Luan possa estar usando.
4. Grave o export no Bitwarden (mesmo item ou item irmão na pasta **Hetzner**, nome claro, ex. **`OpenBao prod / export pré-remediação 2026-11-15`**), de preferência como anexo cifrado, mais notas do que foi coberto. `bw sync` e conferência de hash in-process, como na 3.1.
5. **Mapeie consumidores** no PC e no servidor, só leitura: MeuBot (`personal/meubot`), backups de compras, NetBird, conectores, KB (`wiki/infra`, inventários), `.env` e itens Bitwarden que apontem para `8200`, `8201`, `openbao`, `VAULT_ADDR`, `BAO_ADDR`. Não quebre ninguém: anote URL/endereço hoje (público `46.224.228.253:8200` vs VPN `100.102.58.164:8200`) e o que precisará passar a usar o bind novo. Se um consumidor só alcança o OpenBao pelo IP público, **pare e relate** antes de tirar o `0.0.0.0` — não deixe serviço órfão no silêncio.

### 3.3 Sair do modo dev, bind só na VPN, restaurar, unseal, rotacionar root

Só depois das seções 3.1 e 3.2 verificadas.

1. Ajuste compose/`command`/entrypoint para **`bao server`** (ou equivalente) **sem** `-dev`, `-dev-listen-address` e `-dev-root-token-id`. Mantenha storage persistente + TLS. Alinhe `openbao.hcl` ao que a inspeção confirmou (listener no endereço da VPN, não `0.0.0.0`; `api_addr` / `cluster_addr` coerentes com o bind novo, provavelmente `https://100.102.58.164:8200` — confirme antes de gravar).
2. Remova o publish `8200:8200` / `8201:8201` em todas as interfaces. O bind deve ser **somente** no IP NetBird (e, se o plano/rollback e a inspeção justificarem, no IP privado). Sem `0.0.0.0`, sem `[::]`.
3. Suba o serviço, **restaure** os dados se a troca de modo exigir (use o export e/ou o storage em arquivo, conforme o que você comprovou na 3.2). Faça **unseal** com as chaves que estão no Bitwarden, sem imprimi-las.
4. **Gere um root token novo**. Grave **imediatamente** no Bitwarden (item claro na pasta Hetzner, notas 2026-11-15: token novo pós-remediação; o histórico conserva o antigo). Se o unseal/init gerar **unseal ou recovery keys novas**, grave-as também **na hora**, no mesmo espírito do item da 3.1 (não deixe chaves novas só na tela ou num arquivo temporário). Só então **revogue o root token antigo**.
5. Confira: serviço no ar, unsealed, TLS ok, UI/API respondendo **só** no endereço previsto, consumidores conhecidos ainda autenticam (ou plano explícito de apontá-los para o novo endereço, se isso for só config local e reversível).

### 3.4 Apagar `bootstrap.json` do disco

**Somente depois** de: backups da 3.1 e 3.2 conferidos; serviço no ar e unsealed; token root novo (e quaisquer chaves novas) gravados e relidos do Bitwarden; rollback documentado.

Aí sim, remova de forma segura (`shred` ou equivalente) `/opt/openbao/bootstrap/bootstrap.json` (e cópias óbvias no mesmo diretório, se houver). Confirme que o arquivo não restou no host. **Não apague** o diretório de config, TLS, nem o storage.

### 3.5 Verificar de novo, parecer, git local

1. Sondas **externas** (da internet): 8200 e 8201 devem continuar inacessíveis (timeout/refuse), como hoje via Cloud Firewall — e agora também por não haver publish público. 80/443/3478 não são o alvo desta mudança; não os quebre. SSH da VPN continua ok.
2. Checagens **internas** (via NetBird): `ss`/`docker port`/bind address, `bao status` (sem token no output do parecer), TLS, tentativa de alcançar 8200 a partir do IP público vs do `100.102.58.164`.
3. Anexe evidências **redigidas** a um parecer neste diretório, por exemplo `pareceres\fase-openbao-remediacao-2026-11-15.md` (ou apêndice no `fase-b-saidas` se fizer mais sentido). Sem segredos, sem `bootstrap.json` em claro.
4. Commits locais claros no repo do conector (OpenSpec, parecer, CHANGELOG). Tag no fuso **America/Sao_Paulo**, no espírito `whatsapp-YYYYMMDD-HHMM-openbao-remediacao` (use a hora BRT real). Atualize o handoff da KB `C:\Users\luanc\projects\projects-knowledge-base\organizacao\handoff-zeca-2026-11-15.md` com o estado do OpenBao e os nomes dos itens no Bitwarden (não os valores). Commit + tag BRT na KB (`kb-YYYYMMDD-HHMM-...`). **Sem push** nos dois repositórios. Não adicione a git pastas irrelevantes (`.agents/`, `.claude/`, etc.).

---

## 4. O que não fazer

- Não imprimir e não commitar segredos, `BW_SESSION`, tokens, chaves, trechos de `bootstrap.json` ou do export.
- Não rodar `bw lock` nem `bw logout`.
- Não apagar `bootstrap.json` nem revogar o root antigo antes dos backups verificados e do serviço novo confirmado.
- Não reiniciar o OpenBao no escuro se houver chance de os dados estarem só na memória.
- Não deixar 8200/8201 em `0.0.0.0`. Não abrir essas portas no Cloud Firewall.
- Não mudar DNS, webhook Meta, Traefik do NetBird além do estritamente necessário para esta remediação (em princípio, não precisa).
- Não “consertar” `~\.ssh\config`. Não usar WSL, Docker no PC, nem Cursor.
- Não dar push, `/aprovar`, nem falar em nome do Luan.

---

## 5. Critério de pronto

- OpenSpec da remediação (nesta change ou irmã) com rollback escrito.
- Bootstrap antigo (unseal, recovery, root) no Bitwarden, pasta Hetzner, anexo cifrado, sync + hash conferidos.
- Export/inventário do estado vivo no Bitwarden, e mapa de consumidores, feitos **antes** da troca de modo.
- OpenBao em modo server não-dev, storage persistente + TLS, bind só na VPN/privado, sem publish público.
- Root token novo (e chaves novas, se houver) no Bitwarden; root antigo revogado.
- `bootstrap.json` removido do disco só depois disso.
- Sondas externas e checagens internas no parecer redigido.
- Commits + tags BRT + CHANGELOG locais; **nenhum push**.

Se um passo falhar ou ficar ambíguo, pare e descreva o bloqueio nesta aba, com o que já está seguro no Bitwarden — não avance “para não perder o ritmo”.
