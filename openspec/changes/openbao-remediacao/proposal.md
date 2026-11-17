# Proposta: openbao-remediacao

## Why

O OpenBao do host `openbao-platform-prod-openbao` roda com flags de modo dev (`-dev-root-token-id=`, `-dev-listen-address=0.0.0.0:8200`), escuta em `0.0.0.0:8200/8201` via `docker-proxy` (o Docker contorna o UFW, e a cadeia `DOCKER-USER` está vazia) e tem `bootstrap.json` em texto puro no disco, com unseal keys e root token.

Estado verificado em 15/11/2026 (somente leitura, sem token):

- `GET /v1/sys/health` local: `initialized: true`, **`sealed: true`**, versão 2.2.0.
- Um processo `dev` nunca fica selado. Logo, o armazenamento é persistente (arquivo), e as flags `-dev*` são resíduo. O serviço está **fora do ar** enquanto selado.
- `/opt/openbao/data` e o compose não são legíveis pelo usuário `luan`. Não foi possível confirmar o conteúdo sem root.
- Busca no repositório e na KB: nenhum código ativo do MeuBot, do Compras ou do webhook consome o OpenBao. Há menções em documentação e inventário, e a integração estava marcada como pendente.

## What Changes

1. Backup do `bootstrap.json` no Bitwarden (pasta Hetzner), com anexo e conferência de hash, antes de qualquer mudança.
2. Inventário e export do que estiver no cofre, feitos **depois** de desselar, com as chaves do backup.
3. Sair do modo dev: `bao server` com `storage "file"`, TLS e listener no IP da VPN (`100.102.58.164`), sem `-dev*` e sem `0.0.0.0`.
4. Publicação das portas `8200/8201` removida do compose. Bind só no IP da VPN.
5. Unseal com as chaves do Bitwarden. Root token novo gravado no Bitwarden antes de revogar o antigo.
6. Remoção de `bootstrap.json` do disco com `shred`, depois de tudo confirmado.

## What Does Not Change

- Cloud Firewall: nenhuma regra para 8200/8201 é criada.
- Traefik, NetBird e webhook: não são tocados.
- DNS e Meta: não são tocados.
- Sem push, sem `bw lock`.

## Riscos

- **Serviço selado hoje.** Sem as chaves de unseal, nada volta. Por isso o backup no Bitwarden é a condição zero.
- **Dados de `secret/` podem não estar exportados.** Só dá para exportar com o cofre desselado. Se o backup do arquivo de storage for a única cópia, ele precisa ser protegido antes de qualquer restart.
- **Consumidores.** Não encontrei consumidor ativo no código, mas a inspeção não pôde listar o conteúdo do cofre.
- **Acesso root.** Depende da senha do item `luan/hetzner-openbao-root`, usada via `su` com PTY. Não é possível fazer isso de forma verificável daqui sem expor a senha.
