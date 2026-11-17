# Remediação do OpenBao — parecer parcial (15/11/2026, BRT)

**Status:** **parado antes da primeira mudança no servidor.** Motivo abaixo. Nada foi alterado no host, no compose, no Cloud Firewall, no DNS ou na Meta. Sem push.

## O que foi feito (somente leitura, sem token)

- **Saúde do OpenBao (`GET /v1/sys/health` em `127.0.0.1:8200`, via SSH `vps`):** `initialized: true`, **`sealed: true`**, versão 2.2.0, `standby: true`.
  - Leitura: um processo em modo `dev` nunca fica selado. O armazenamento é persistente. As flags `-dev*` são resíduo.
  - Consequência: **o serviço está fora do ar** enquanto estiver selado. Não há como exportar o cofre antes de desselar.
- **Storage:** `/opt/openbao/data` e `/opt/openbao/docker-compose.yml` retornam `Permission denied` para o usuário `luan`. Não foi possível listar o conteúdo nem confirmar o tipo de storage.
- **Consumidores:** busca por `BAO_ADDR`, `VAULT_ADDR`, `8200` e `openbao` no PC (código, `.env`, KB, MeuBot, Compras). Nenhum código ativo encontrado. As referências estão em documentação e no inventário, onde a integração aparece como pendente.

## Por que parei antes da 3.1

A etapa 3.1 é bloqueante: ler `bootstrap.json` com `su` e gravar no Bitwarden. Para fazer `su` é preciso enviar a senha do item `luan/hetzner-openbao-root` ao PTY do servidor. Não há, a partir desta ferramenta, um caminho verificável de fazer isso sem que a senha passe por comando, histórico ou saída. Não vou improvisar nisso. O prompt manda parar nesse caso.

Sem a 3.1, não há backup. Sem backup, não há 3.2, 3.3 nem 3.4.

## Próximo passo (precisa de você)

Uma das duas:

1. **Você faz a 3.1 na sua máquina** com o PowerShell, usando o caminho já aprovado: abrir o `su` no servidor, copiar o conteúdo do `bootstrap.json` para um item novo no Bitwarden (pasta Hetzner) e conferir. Depois me avisa com o nome do item.
2. **Você me autoriza** a fazer `su` com a senha do item, desde que eu use um mecanismo que não deixe a senha em comando ou log. Preciso que você confirme qual mecanismo aceita.

Depois da 3.1, a ordem continua pelo `tasks.md`: inventário com unseal, mudança do modo, token novo, remoção do bootstrap.

## Riscos que continuam abertos

- **`bootstrap.json` em texto puro no disco**, com unseal keys e root token. Continua no servidor até a 3.4.
- **OpenBao selado**: se o servidor reiniciar, continua selado até o unseal.
- **Publicação em `0.0.0.0:8200/8201`** via Docker, sem proteção do UFW. Hoje só o Cloud Firewall protege.

## Artefatos criados (commit local)

- `openspec/changes/openbao-remediacao/proposal.md`
- `openspec/changes/openbao-remediacao/tasks.md`
- este parecer

## Incidente de exposição (15/11/2026, após o parecer acima)

- Ao tentar a etapa 3.1 com o helper `Invoke-HetznerRoot.ps1`, o conteúdo de `/opt/openbao/bootstrap/bootstrap.json` **apareceu na saída desta sessão**: as unseal keys (b64 e hex) e o root token.
- Causa: o helper escreve a saída direto no console, e o redirecionamento usado não impediu isso. Eu não testei o redirecionamento com um arquivo de teste antes de usar o arquivo real. Esse foi o erro.
- Estado depois do incidente: nenhum item criado no Bitwarden (busca por "OpenBao prod" retorna 0), nenhum arquivo temporário restante, nada alterado no servidor.
- **Tratar como comprometidos:** o root token e as cinco unseal keys (b64 e hex). A conversa pode ficar registrada.

### Mitigação necessária antes de qualquer uso do cofre

1. Não desselar o cofre com as chaves antigas. Ele continua selado.
2. Fazer `operator rekey` para gerar novas unseal keys, com as antigas como threshold, e gravar as novas no Bitwarden.
3. Depois do unseal com as novas, gerar um root token novo e revogar o antigo.
4. Remover o `bootstrap.json` do disco com `shred`.
5. Antes disso, testar o pipeline de backup com um arquivo de teste, sem o arquivo real, e conferir que a saída não aparece no console.

Aguardo autorização do Luan para o passo 2.

## Remediação executada (BRT, 16/11/2026)

O passo a passo, com evidências, está em `pareceres/prompt-03-execucao-2026-11-15.md`, seção "Execução final (16/11/2026)". Resumo:

- Rekey feito (5 shares, t=3). Chaves antigas vazadas invalidadas. Chaves novas no Bitwarden (`OpenBao prod / unseal+recovery (rekey 2026-11-15)`, conferidas byte a byte).
- Root token novo (`OpenBao prod / root token (2026-11-16)`), gravado antes da revogação. Antigo revogado (204; lookup 403).
- `bootstrap.json` em texto puro apagado com `shred`.
- Mitigações 1 a 5 do incidente: concluídas (o pipeline de backup foi testado com arquivo falso antes do arquivo real).- 16/11 (continuação): saída do modo dev (sem entrypoint `-dev*`), portas 8200/8201 só em `100.102.58.164`, `api_addr`/`cluster_addr` na VPN, unseal determinístico com `Invoke-OpenBaoUnseal.ps1` e dados idênticos à linha de base. Também a redação dos valores antigos em logs locais (3 ocorrências no histórico de terminal do Orca; 0 depois). Detalhes em `prompt-03-execucao-2026-11-15.md`.
