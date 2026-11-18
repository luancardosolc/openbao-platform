# Proposta: backup-estado

## Por quê

O Luan precisa recuperar as aplicações (código, bancos, conversas do Hermes, MeuBot, sessões dos agentes) e o servidor Hetzner se o PC for perdido, sem backup do Windows inteiro.

## O que muda

- O PC passa a ter restic com dois repos: Hetzner (SFTP restrito pela NetBird) e OneDrive (2FA). Backup diário às 02:00, retenção 7/4/12, check semanal, teste de restore mensal automático e alerta de 26h no Telegram do MeuBot.
- Antes de cada snapshot rodam as cópias consistentes dos SQLite e o manifesto de reinstalação (`workstation/manifest`).
- O servidor ganha um tar noturno cifrado com age (OpenBao, NetBird, configs), que o PC puxa e versiona.
- Segredos são gerados direto no Bitwarden (sem exibir), com cópia DPAPI só para as tarefas.

## Fora do escopo

Imagem do Windows, Downloads/Desktop/Documents e apps reinstaláveis (cobertos pelo manifesto).
