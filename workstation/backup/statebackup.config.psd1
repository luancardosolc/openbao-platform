# Backup do ESTADO: projects (codigo + bancos + .env) e estado das apps pedidas pelo Luan (Hermes, MeuBot, Codex/Claude/agy/Orca, ssh, agent-tools, WhatsApp/Telegram) + servidor Hetzner. Pastas pessoais amplas do perfil ficam de fora por decisao do Luan. Tokens {HOME} {LOCALAPPDATA} {APPDATA} sao expandidos.
# Fica de fora tudo que se reinstala (binarios, venvs, node_modules, runtimes/caches); o manifesto de reinstalacao cobre isso.
@{
  Includes = @(
    '{HOME}\projects'
    '{LOCALAPPDATA}\hermes'
    '{APPDATA}\Hermes'
    '{HOME}\.codex'
    '{HOME}\.claude'
    '{HOME}\.gemini'
    '{APPDATA}\orca'
    '{HOME}\.orca'
    '{HOME}\agent-tools'
    '{HOME}\.ssh'
    '{HOME}\.gitconfig'
    '{APPDATA}\whatsapp-pessoal-mcp'
    '{APPDATA}\telegram-pessoal'
    '{LOCALAPPDATA}\Meubot'
    '{APPDATA}\ComprasBackup'
    '{LOCALAPPDATA}\StateBackup\staging'
  )
  # Nome de pasta em qualquer lugar (case-insensitive)
  ExcludeNames = @(
    'node_modules','.venv','venv','__pycache__','.pytest_cache','.mypy_cache','.ruff_cache','.next','.nuxt','.turbo',
    'bower_components','.gradle','GPUCache','Code Cache','DawnWebGPUCache','DawnGraphiteCache','ShaderCache','GrShaderCache',
    'Crashpad','.sandbox-bin','dist','build','target','obj','.vs','agy_venv',
    # locks/arquivos vivos que o Windows nao deixa ler (sqlite vivo vai pela copia consistente em staging\sqlite)
    '*.lock','LOCK','lockfile','*.guard','*-shm','*-wal','*-journal'
  )
  # Caminhos exatos (pasta ou arquivo)
  ExcludePaths = @(
    '{HOME}\projects\references'
    '{LOCALAPPDATA}\hermes\tools'
    '{LOCALAPPDATA}\hermes\installs'
    '{LOCALAPPDATA}\hermes\hermes-agent'
    '{LOCALAPPDATA}\hermes\cache'
    '{LOCALAPPDATA}\hermes\audio_cache'
    '{LOCALAPPDATA}\hermes\image_cache'
    '{LOCALAPPDATA}\hermes\lsp'
    '{LOCALAPPDATA}\hermes\bin'
    '{LOCALAPPDATA}\hermes\runtime'
    '{LOCALAPPDATA}\hermes\telemetry'
    '{LOCALAPPDATA}\hermes\models_dev_cache.json'
    '{APPDATA}\Hermes\Cache'
    '{APPDATA}\Hermes\Partitions'
    '{APPDATA}\orca\codex-runtime-home\home\packages'
    '{APPDATA}\orca\codex-runtime-home\home\plugins'
    '{APPDATA}\orca\codex-runtime-home\home\cache'
    '{APPDATA}\orca\logs'
    '{APPDATA}\orca\Partitions'
    '{APPDATA}\orca\Cache'
    '{APPDATA}\orca\blob_storage'
    '{HOME}\.codex\plugins'
    '{HOME}\.codex\cache'
    '{HOME}\.codex\.tmp'
    '{HOME}\.codex\tmp'
    '{APPDATA}\orca\Network'
    '{HOME}\.codex\vendor_imports'
    '{HOME}\.claude\plugins'
    '{HOME}\.claude\cache'
    '{HOME}\.claude\paste-cache'
    '{HOME}\.gemini\antigravity-browser-profile'
    '{HOME}\.gemini\tmp'
  )
  RepoSftp     = 'sftp:statebackup-hz:/restic/pc'
  RepoOneDrive = '{HOME}\OneDrive\Backups\restic-state'
  Keep = @{ Daily = 7; Weekly = 4; Monthly = 12 }
  FreshnessHours = 26
  Python = '{HOME}\.pyenv\pyenv-win\versions\3.13.1-win32\python.exe'
  MeubotAlert = '{HOME}\projects\personal\meubot\alerta.py'
  ServerHost = 'statebackup-hz'
}