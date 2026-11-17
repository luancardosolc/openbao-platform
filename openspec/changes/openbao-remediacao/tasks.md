# Tarefas: openbao-remediacao

Ordem obrigatória. Não pular etapas. Cada tarefa marcada **[BLOQUEIA]** precisa ser concluída antes da seguinte.

## 3.0 OpenSpec e rollback

- [x] Proposta, estado verificado e riscos (`proposal.md`).
- [x] Plano de rollback com cópias de `docker-compose.yml`, `openbao.hcl` e unit, guardadas em caminho fora do git (anotar o caminho no parecer).
- [x] Critérios de verificação externos e internos.

## 3.1 Backup do bootstrap no Bitwarden **[BLOQUEIA]**

- [x] Ler `/opt/openbao/bootstrap/bootstrap.json` com `su`, só em processo. (15/11, `Invoke-HetznerSecretToBitwarden.ps1`)
- [x] Criar item `OpenBao prod / unseal+recovery+root (bootstrap 2026-03)` (criado como `OpenBao prod / bootstrap antigo (comprometido 2026-11-15)`) na pasta Hetzner, com as unseal keys, recovery keys (ou registro de "vazio"), `unseal_shares`, `unseal_threshold` e o root token atual.
- [x] Anexo cifrado do `bootstrap.json`. (`.enc` em base64: `OpenBao prod / bootstrap.json.enc antigo base64 (2026-11-15)`)
- [x] `bw sync` e conferência de hash in-process (sem imprimir valor).

## 3.2 Inventário e export (com o processo atual) **[BLOQUEIA]**

- [x] Confirmar se o storage é `file` (não dev). Confirmado: `storage_type: file`. Evidência já obtida: `sealed:true` com `initialized:true`.
- [x] Como o cofre está **selado**, o inventário de mounts, policies e secrets só é possível depois do unseal. Ordem: unseal com as chaves do item da 3.1, depois inventário.
- [ ] Export em item irmão `OpenBao prod / export pré-remediação 2026-11-15`, com conferência de hash.
- [ ] Mapa de consumidores: nenhum consumidor ativo encontrado no código. Confirmar com o Luan se há outro uso fora do repositório.

## 3.3 Sair do modo dev **[LUAN APROVA CADA PASSO]**

- [x] Ajustar `command` do compose para `server`, sem `-dev*`. (16/11: entrypoint `su-exec openbao bao`, `server -config=/openbao/config`)
- [x] `openbao.hcl`: `api_addr` e `cluster_addr` para o IP da VPN.
- [x] Remover publicação `8200:8200` e `8201:8201` do compose. Bind só em `100.102.58.164`.
- [x] Subir, unseal com chaves do Bitwarden. (`Invoke-OpenBaoUnseal.ps1`)
- [x] Gerar root token novo, gravar no Bitwarden **antes** de revogar o antigo. (16/11, `OpenBao prod / root token (2026-11-16)`)
- [x] Revogar o root antigo. (16/11: revoke 204, lookup antigo 403)

## 3.4 Remover bootstrap do disco **[BLOQUEIA: só após 3.1–3.3 confirmadas]**

- [x] `shred` em `/opt/openbao/bootstrap/bootstrap.json`. (16/11) Não apagar config, TLS nem storage.
- [x] Remover o volume `/opt/openbao/bootstrap` do compose (backup `docker-compose.yml.bak-20261116-2242`), `shred` em `bootstrap.json.enc` (backup Bitwarden conferido por sha256) e `bootstrap-openbao.sh` (idêntico ao template versionado) e remover a pasta. Recreate + unseal + `BASELINE_OK`. (16/11, 22:42 BRT; `ops/runbooks/verify-baseline/`)

## 3.5 Verificação e parecer

- [x] Sondas externas: 8200 e 8201 inacessíveis.
- [x] Checagens internas: bind, TLS, `sys/health`, consumidores.
- [x] Parecer redigido em `pareceres/fase-openbao-remediacao-2026-11-15.md`, sem segredos.
- [x] Commit local e tag BRT. Sem push.

## Extra (incidente 15/11)

- [x] Rekey (5 shares, t=3) com as chaves antigas como threshold; chaves novas em `OpenBao prod / unseal+recovery (rekey 2026-11-15)`, conferidas byte a byte (16/11).
- [x] Redação dos valores antigos em logs locais (Orca terminal-history: 3 → 0; sessão Claude: 0) (16/11).

## Local

- 16/11/2026: movido de `conectores/whatsapp-business-mcp` para `personal/openbao-platform`. Pendente: política do NetBird para TCP 8200 da estação (ver parecer).
