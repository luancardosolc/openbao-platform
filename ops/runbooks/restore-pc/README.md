# Runbook: recuperar o PC do Luan depois de um desastre

Escopo: **estado das aplicações**, não o Windows. O backup cobre `C:\Users\luanc\projects` (código com `.git`, bancos de cada projeto e `.env`, sem dependências reinstaláveis) e o estado de Hermes (com as conversas), MeuBot, Codex, Claude, agy/Gemini, Orca, `~/.ssh`, `agent-tools` e WhatsApp/Telegram pessoais. Também cobre o servidor Hetzner (OpenBao + NetBird + configs, num tar cifrado com age).

## Onde está

| Cópia | Local | Acesso |
| --- | --- | --- |
| Repo restic A | Hetzner `sftp:statebackup@100.102.58.164:/restic/pc` (chroot `/srv/statebackup`) | só pela NetBird, chave `Backup estado / SSH key statebackup sftp (2026-11-18)` |
| Repo restic B | OneDrive `Backups\restic-state` | conta Microsoft do Luan (2FA) |
| Imagens Hetzner | backup diário automático da VPS (7 dias) | console Hetzner |
| Tar do servidor | dentro dos 2 repos restic (`StateBackup\staging\server-state`) e em `/srv/statebackup/server-state` (últimos 3) | identidade age no Bitwarden |

Segredos (Bitwarden, pasta **Hetzner**):

- `Backup estado / restic repo password (2026-11-18)`: senha dos dois repos restic
- `Backup estado / age identity backup servidor (2026-11-18)`: decifra o tar do servidor
- `Backup estado / SSH key statebackup sftp (2026-11-18)`: SFTP restrito no Hetzner
- `OpenBao prod / unseal+recovery (rekey 2026-11-15)` e `OpenBao prod / root token (2026-11-16)`
- `Chave backup Compras (7z AES-256)`, `whatsapp-pessoal/chave-backup`

## Passo a passo (PC novo, Windows limpo)

1. Instalar o Bitwarden CLI (`winget install Bitwarden.CLI`), fazer login e destravar.
2. **Reinstalar tudo pelo manifesto.** Ele está no backup em `StateBackup\staging\manifest\` e uma cópia de referência fica na KB privada em `organizacao/manifesto-reinstalacao/<data>/` (não fica aqui porque este repo é público: o manifesto lista repos privados e tarefas).
   1. `winget import -i winget.json --accept-package-agreements --accept-source-agreements`
   2. scoop: instalar o scoop e depois `scoop import scoop.json`. Inclui o nvm; depois `nvm install` para as versões de `nvm.txt`.
   3. pyenv-win: `pyenv install 3.13.1-win32` e `pyenv global 3.13.1-win32`; depois `pip install` com os pacotes de `python.txt`.
   4. npm global: os pacotes de `npm-global.json` (codex, gemini-cli, openspec, opencode-ai, wrangler, chrome-devtools-mcp).
   5. uv tools: os de `uv-tools.txt`.
   6. As CLIs e versões de `clis.json`: claude (instalador nativo), agy, orca, hermes, netbird, gh, restic, age.
3. Entrar na NetBird (`netbird up`, conta dona) para chegar ao Hetzner.
4. Restaurar o estado:

   ```powershell
   $env:RESTIC_PASSWORD = '<do Bitwarden, sem exibir>'   # ou bw get ... direto na variável
   restic -r C:\...\OneDrive\Backups\restic-state snapshots --tag state
   restic -r C:\...\OneDrive\Backups\restic-state restore latest --target C:\restore
   ```

   (ou o repo A: salvar a chave SFTP em `~/.ssh/id_ed25519_statebackup` e usar `-o sftp.command="ssh -i ... statebackup@100.102.58.164 -s sftp"`)
5. Copiar de `C:\restore\C\Users\luanc\...` para os lugares originais: `projects`, `%LOCALAPPDATA%\hermes`, `%APPDATA%\Hermes`, `~\.codex`, `~\.claude`, `~\.gemini`, `%APPDATA%\orca`, `~\.orca`, `agent-tools`, `~\.ssh`, `%APPDATA%\whatsapp-pessoal-mcp`, `%APPDATA%\telegram-pessoal`, `%LOCALAPPDATA%\Meubot`.
6. **Bancos SQLite:** usar as cópias consistentes de `StateBackup\staging\sqlite\C\...` por cima dos arquivos vivos (Hermes `state.db`/`kanban.db`, MeuBot `fila_duravel.sqlite3`, Codex, Orca, Compras) e apagar os `-wal`/`-shm` antigos.
7. **Dependências dos projetos:** `npm ci` / `uv sync` / `pip install -r` em cada repo. Os repos de `references\` voltam com `git clone`, usando `repos.json`.
8. **Logins que não migram** (DPAPI, presos ao PC antigo): parear o WhatsApp de novo, fazer login no Telegram de novo, `setup-bw-master.ps1` (auto-unlock do Bitwarden), `gh auth login`, Codex/Claude/agy, NetBird.
9. **Tarefas agendadas:** `workstation/backup/Register-StateBackupTasks.ps1`. As do MeuBot/Compras/WhatsApp/Hermes estão em `scheduled-tasks.json` (recriar com os mesmos comandos).
10. **Conferir:** status do MeuBot no Telegram, o Hermes abrindo as conversas antigas, `Set-NetBirdPolicy.ps1 -CheckOnly` = `POLICY_OK`, health do OpenBao = 200, e `Invoke-StateBackup.ps1 -Mode RestoreTest`.

## Servidor Hetzner perdido

1. Criar a VPS (ou restaurar a imagem de backup da Hetzner, que é o caminho mais rápido).
2. Sem imagem: pegar o tar mais novo nos repos restic, decifrar com `age -d -i <identidade>`, `zstd -d` e `tar -C / -xf`. Ele traz `/opt/openbao`, `/opt/netbird`, os volumes do NetBird, `/etc/ssh`, `/etc/ufw` e `/home/luan/backups`. Depois `docker compose up -d` em `/opt/openbao` e `/opt/netbird`, e fazer o unseal com `Invoke-OpenBaoUnseal.ps1`.
3. O teste disso roda em `ops/backup/server/openbao-restore-test.sh` (container temporário em 127.0.0.1, destruído no fim).

## Testes automáticos

- Todo dia às 02:00: backup nos dois repos e retenção 7/4/12 (prune aos domingos).
- Domingo: `restic check --read-data-subset=5%`. No 1º domingo do mês também roda `RestoreTest`: amostra restaurada para uma pasta temporária, com hashes, `integrity_check` dos SQLite, o tar do servidor (sha256 + age) e o manifesto.
- De hora em hora: um aviso no Telegram (via `alerta.py` do MeuBot) se algum repo passar de 26h sem backup bom.
