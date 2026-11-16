# Operação segura do servidor Hetzner existente

Esta camada começa em modo somente leitura e não usa o provisionador genérico da raiz. Ela consulta o host vivo por SSH via NetBird, usando `luan`, chave já existente, `BatchMode` e validação estrita de `known_hosts`. Não instala pacotes, não chama `sudo`, não altera Docker/Compose, firewall, APT ou serviços e não reinicia o host.

## Health check do host

```powershell
$env:HETZNER_SSH_KEY = 'C:\Users\luanc\.ssh\ed25519_hetzner_acer_2026'
python ops/hetzner_health.py --json --output artifacts/before.json
# após uma mudança autorizada e pós-checks funcionais:
python ops/hetzner_health.py --json --output artifacts/after.json
python ops/compare_health.py artifacts/before.json artifacts/after.json
```

O relatório mede SO, uptime, load, memória, disco, reboot pendente, serviços systemd essenciais, units em falha, endpoint local de saúde do OpenBao e endpoint HTTPS público do painel NetBird. Ele informa claramente quando a leitura privilegiada do Docker foi negada. Código de saída `0` significa que nenhum check crítico observado falhou; avisos e cobertura incompleta continuam visíveis. `2` indica falha de conexão ou configuração; `1`, falha crítica de saúde.

## Limites atuais

- O endpoint HTTP do OpenBao retorna estado de serviço, mas não prova que esteja unsealed, que autenticação/policies funcionem ou que os dados possam ser restaurados.
- O socket Docker exige privilégio, então lista de containers, imagens, volumes e healthchecks não é observável por `luan` ainda.
- Não existe alerta independente quando este PC está desligado. O próximo passo de alerta externo depende de escolher/provisionar um provedor e guardar token/chat em cofre; nenhuma mensagem de teste será enviada por esta rotina.
- A rotina não aplica upgrades/reboot. São pré-condições um backup íntegro fora do VPS, restore testado, inventário privilegiado, health checks das aplicações e janela/rollback.

`compare_health.py` compara dois JSONs e sinaliza checks críticos/avisos novos e quedas acima dos limites configurados para load, memória e disco. “no_regression_detected” cobre apenas os dados coletados e não substitui testes funcionais de cada aplicação.

## Verificação

```powershell
python -m unittest discover -s tests -p 'test_*.py' -v
```
