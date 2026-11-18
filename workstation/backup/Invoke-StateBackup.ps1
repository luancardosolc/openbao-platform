#requires -Version 5.1
<#
.SYNOPSIS
  Backup do ESTADO das aplicacoes do PC com restic em dois repos (Hetzner via SFTP/NetBird e OneDrive).
.DESCRIPTION
  Modos:
    Init         cria os dois repos restic (idempotente)
    Backup       manifesto + copias SQLite consistentes + puxa o tar cifrado do servidor + restic backup nos 2 repos + forget 7/4/12
    Check        restic check --read-data-subset nos 2 repos (semanal); no 1o domingo do mes roda tambem RestoreTest
    RestoreTest  restaura uma amostra de cada repo para uma pasta temporaria e confere: integrity_check dos SQLite
                 (Hermes state.db, MeuBot fila), hashes de arquivos que nao mudaram desde o snapshot (projects, .env,
                 codex, manifesto) e o tar do servidor (sha256 + age decrypt). Apaga a pasta no final.
    Freshness    se o ultimo backup bom de algum repo tem mais de 26h, avisa no Telegram pelo alerta.py do MeuBot
  Segredos: senha do restic e identidade age ficam em DPAPI (%LOCALAPPDATA%\StateBackup\*.dpapi, so este usuario);
  a fonte da verdade e o Bitwarden (pasta Hetzner, itens "Backup estado / ..."). Nada e impresso.
#>
[CmdletBinding()]
param(
  [ValidateSet('Init','Backup','Check','RestoreTest','Freshness')][string]$Mode = 'Backup',
  [ValidateSet('All','Sftp','OneDrive')][string]$Repo = 'All',
  [switch]$NoAlert
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$SB = Join-Path $env:LOCALAPPDATA 'StateBackup'
$LogDir = Join-Path $SB 'logs'; New-Item -ItemType Directory -Force $LogDir | Out-Null
$StatusFile = Join-Path $SB 'status.json'
$tz = [TimeZoneInfo]::FindSystemTimeZoneById('E. South America Standard Time')
function NowBrt { [TimeZoneInfo]::ConvertTime([DateTime]::UtcNow, $tz) }
function Log([string]$m) { $line = '{0} [{1}] {2}' -f (NowBrt).ToString('yyyy-MM-dd HH:mm:ss'), $Mode, $m; Add-Content -LiteralPath (Join-Path $LogDir ('statebackup-{0}.log' -f (NowBrt).ToString('yyyy-MM'))) -Value $line -Encoding UTF8; Write-Output $line }
function Expand([string]$s) { $s.Replace('{HOME}', $HOME).Replace('{LOCALAPPDATA}', $env:LOCALAPPDATA).Replace('{APPDATA}', $env:APPDATA) }

$cfgRaw = Import-PowerShellDataFile (Join-Path $here 'statebackup.config.psd1')
$Includes = @($cfgRaw.Includes | ForEach-Object { Expand $_ })
$ExNames = @($cfgRaw.ExcludeNames)
$ExPaths = @($cfgRaw.ExcludePaths | ForEach-Object { Expand $_ })
$Py = Expand $cfgRaw.Python
$SshCfg = Join-Path $SB 'ssh_config'
$Restic = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\restic.restic_Microsoft.Winget.Source_8wekyb3d8bbwe" -Filter 'restic*.exe' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1).FullName
if (-not $Restic) { $c = Get-Command restic -ErrorAction SilentlyContinue; if ($c) { $Restic = $c.Source } }
if (-not $Restic) { throw 'restic nao encontrado (winget install restic.restic)' }
$Repos = [ordered]@{}
if ($Repo -in 'All','Sftp') { $Repos['sftp'] = @{ url = $cfgRaw.RepoSftp; opts = @('-o', ('sftp.command=ssh -F {0} {1} -s sftp' -f ($SshCfg -replace '\\','/'), $cfgRaw.ServerHost)) } }
if ($Repo -in 'All','OneDrive') { $Repos['onedrive'] = @{ url = (Expand $cfgRaw.RepoOneDrive); opts = @() } }

Add-Type -AssemblyName System.Security
function Unprotect([string]$file) { [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($file), $null, 'CurrentUser')) }
$env:RESTIC_PASSWORD = (Unprotect (Join-Path $SB 'restic-pass.dpapi')).Trim()
$env:RESTIC_CACHE_DIR = Join-Path $SB 'restic-cache'
$env:RESTIC_PROGRESS_FPS = '0.016'

function Get-Status { if (Test-Path $StatusFile) { try { return (Get-Content $StatusFile -Raw | ConvertFrom-Json) } catch { } }; return [pscustomobject]@{} }
function Set-StatusField($name, $value) { $s = Get-Status; $h = @{}; $s.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }; $h[$name] = $value; [IO.File]::WriteAllText($StatusFile, ($h | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false))) }
function Alert([string]$text) {
  if ($NoAlert) { Log "ALERTA (suprimido): $text"; return }
  try { & $Py (Expand $cfgRaw.MeubotAlert) ("[backup] " + $text) *> $null; Log "ALERTA enviado: $text" } catch { Log "ALERTA falhou: $($_.Exception.Message)" }
}
function Invoke-Rs([string]$repoKey, [string[]]$args2, [switch]$Json) {
  $r = $Repos[$repoKey]; $a = @('-r', $r.url) + $r.opts + $args2; if ($Json) { $a += '--json' }
  $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $out = & $Restic @a 2>&1; $code = $LASTEXITCODE; $ErrorActionPreference = $eap
  return [pscustomobject]@{ code = $code; out = @($out | ForEach-Object { "$_" }) }
}
$mutex = New-Object Threading.Mutex($false, 'Global\StateBackupLuan')
if (-not $mutex.WaitOne(0)) { Log 'outra execucao em andamento; saindo'; exit 0 }
$ErrorActionPreference = 'Continue'
try {
switch ($Mode) {
'Init' {
  foreach ($k in $Repos.Keys) {
    $c = Invoke-Rs $k @('cat', 'config')
    if ($c.code -eq 0) { Log "repo $k ja existe" } else { $i = Invoke-Rs $k @('init'); Log ("init {0}: code={1} {2}" -f $k, $i.code, (($i.out | Where-Object { $_ -match 'created restic repository' }) -join ' ')) ; if ($i.code -ne 0) { throw "init $k falhou" } }
  }
}
'Backup' {
  $t0 = Get-Date
  $stage = Join-Path $SB 'staging'
  if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
  New-Item -ItemType Directory -Force "$stage\manifest", "$stage\sqlite", "$stage\server-state" | Out-Null
  # 1) manifesto de reinstalacao
  $m = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Split-Path $here) 'manifest\Export-ReinstallManifest.ps1') -OutDir "$stage\manifest" 2>&1 | Select-Object -Last 1
  Log "manifesto: $m"
  # 2) copias SQLite consistentes
  $rc = Join-Path $SB 'statebackup.resolved.json'
  [IO.File]::WriteAllText($rc, ([pscustomobject]@{ includes = @($Includes | Where-Object { $_ -notlike "$SB*" }); exclude_names = $ExNames; exclude_paths = $ExPaths } | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
  $sq = & $Py (Join-Path $here 'sqlite_snapshot.py') --config $rc --out "$stage\sqlite" 2>&1 | Select-Object -Last 1
  Log "sqlite: $sq"
  # 3) tar cifrado do servidor (SFTP restrito)
  $srvOk = $false; $ErrorActionPreference = 'Continue'
  try {
    $lj = Join-Path "$stage\server-state" 'latest.json'
    $bf = Join-Path "$stage\server-state" 'sftp-batch.txt'  # arquivo sem BOM: pipe do PS 5.1 injeta BOM e o sftp rejeita
    [IO.File]::WriteAllText($bf, "get /server-state/latest.json `"$($lj -replace '\\','/')`"`n", (New-Object Text.UTF8Encoding($false)))
    & sftp.exe -F $SshCfg -b $bf $cfgRaw.ServerHost *> $null
    if (-not (Test-Path -LiteralPath $lj)) { throw "latest.json nao baixou (sftp rc=$LASTEXITCODE)" }
    $latest = Get-Content $lj -Raw | ConvertFrom-Json
    $dst = Join-Path "$stage\server-state" $latest.file
    [IO.File]::WriteAllText($bf, "get /server-state/$($latest.file) `"$($dst -replace '\\','/')`"`n", (New-Object Text.UTF8Encoding($false)))
    & sftp.exe -F $SshCfg -b $bf $cfgRaw.ServerHost *> $null
    Remove-Item -LiteralPath $bf -Force
    if (-not (Test-Path -LiteralPath $dst)) { throw "tar do servidor nao baixou (sftp rc=$LASTEXITCODE)" }
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $dst).Hash.ToLowerInvariant()
    if ($h -ne $latest.sha256) { throw 'sha256 do tar do servidor nao confere' }
    $age = ([DateTime]::UtcNow - [DateTime]::ParseExact($latest.ts, "yyyyMMdd'T'HHmmss'Z'", $null)).TotalHours
    $srvOk = $true; Log ("servidor: {0} {1:N1} MB sha256 ok, idade {2:N1}h" -f $latest.file, ($latest.bytes / 1MB), $age)
    if ($age -gt 26) { Alert ("tar do servidor esta com {0:N0}h (timer server-state-backup parado?)" -f $age) }
  } catch { Log "servidor: FALHA $($_.Exception.Message)"; Alert "nao consegui puxar o tar do servidor: $($_.Exception.Message)" }
  # 4) restic backup nos 2 repos
  $exFile = Join-Path $SB 'excludes.txt'
  [IO.File]::WriteAllLines($exFile, [string[]](@($ExNames) + @($ExPaths) + @("$SB\restic-cache", "$SB\*.dpapi", "$SB\logs")), (New-Object Text.UTF8Encoding($false)))
  $existing = @($Includes | Where-Object { Test-Path -LiteralPath $_ })
  $res = @{}
  foreach ($k in $Repos.Keys) {
    $tb = Get-Date
    $b = Invoke-Rs $k (@('backup') + $existing + @('--iexclude-file', $exFile, '--tag', 'state', '--host', 'luan-nitro5', '--exclude-caches', '--read-concurrency', '4')) -Json
    $sum = $b.out | Where-Object { $_ -match '"message_type":"summary"' } | Select-Object -Last 1 | ConvertFrom-Json
    $errs = @($b.out | Where-Object { $_ -match '"message_type":"error"' })
    $secs = [int]((Get-Date) - $tb).TotalSeconds
    if ($sum -and $b.code -in 0, 3) {
      $res[$k] = [pscustomobject]@{ ok = $true; snapshot = $sum.snapshot_id; files = $sum.total_files_processed; bytes = $sum.total_bytes_processed; added = $sum.data_added; added_packed = $sum.data_added_packed; seconds = $secs; read_errors = $errs.Count; code = $b.code; at_utc = [DateTime]::UtcNow.ToString('o') }
      Log ("restic {0}: snapshot {1} files={2} processed={3:N2}GB added={4:N2}GB stored={5:N2}GB {6}s read_errors={7} code={8}" -f $k, $sum.snapshot_id.Substring(0, 8), $sum.total_files_processed, ($sum.total_bytes_processed / 1GB), ($sum.data_added / 1GB), ($sum.data_added_packed / 1GB), $secs, $errs.Count, $b.code)
      if ($errs.Count) { $errs | Select-Object -First 20 | ForEach-Object { try { $e = $_ | ConvertFrom-Json; Log ("  nao lido: {0}" -f $e.item) } catch { } } }
      Set-StatusField "last_ok_$k" $res[$k]
    } else {
      $res[$k] = [pscustomobject]@{ ok = $false; code = $b.code; seconds = $secs }
      Log ("restic {0}: FALHA code={1} {2}" -f $k, $b.code, (($b.out | Where-Object { $_ -notmatch '^\{' } | Select-Object -Last 3) -join ' | '))
      Alert "backup restic $k falhou (code $($b.code))"
    }
  }
  # 5) retencao 7/4/12 (prune aos domingos)
  $prune = ((NowBrt).DayOfWeek -eq 'Sunday')
  foreach ($k in $Repos.Keys) {
    if (-not $res[$k].ok) { continue }
    $fa = @('forget', '--host', 'luan-nitro5', '--tag', 'state', '--keep-daily', $cfgRaw.Keep.Daily, '--keep-weekly', $cfgRaw.Keep.Weekly, '--keep-monthly', $cfgRaw.Keep.Monthly); if ($prune) { $fa += '--prune' }
    $f = Invoke-Rs $k $fa; Log ("forget {0}: code={1} prune={2}" -f $k, $f.code, $prune)
  }
  Set-StatusField 'last_run' ([pscustomobject]@{ at_utc = [DateTime]::UtcNow.ToString('o'); seconds = [int]((Get-Date) - $t0).TotalSeconds; server_ok = $srvOk; results = $res })
  if (@($res.Values | Where-Object { -not $_.ok }).Count) { exit 1 }
}
'Check' {
  foreach ($k in $Repos.Keys) { $c = Invoke-Rs $k @('check', '--read-data-subset=5%'); Log ("check {0}: code={1} {2}" -f $k, $c.code, (($c.out | Select-Object -Last 1) -join '')); Set-StatusField "last_check_$k" ([pscustomobject]@{ at_utc = [DateTime]::UtcNow.ToString('o'); code = $c.code }); if ($c.code -ne 0) { Alert "restic check $k falhou (code $($c.code))" } }
  if ((NowBrt).Day -le 7) { & powershell -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path -Mode RestoreTest | ForEach-Object { Write-Output $_ } }
}
'RestoreTest' {
  $allOk = $true
  $samples = @(
    "$env:LOCALAPPDATA\hermes\config.yaml", "$env:LOCALAPPDATA\hermes\SOUL.md", "$env:LOCALAPPDATA\hermes\.env",
    "$HOME\projects\personal\meubot\.env", "$HOME\projects\personal\compras\.env", "$HOME\projects\personal\meubot\bot.py",
    "$HOME\.codex\config.toml", "$HOME\.claude\settings.json", "$HOME\.ssh\config", "$HOME\agent-tools\bw-auto-unlock\Get-BwSession.ps1"
  )
  # amostra aleatoria de arquivos versionados em alguns repos
  foreach ($rp in 'personal\meubot', 'personal\compras', 'projects-knowledge-base', 'personal\openbao-platform', 'conectores\whatsapp-pessoal-mcp') {
    $full = Join-Path "$HOME\projects" $rp
    if (Test-Path $full) { $samples += @(& git -C $full ls-files 2>$null | Get-Random -Count 4 | ForEach-Object { Join-Path $full ($_ -replace '/', '\') }) }
  }
  $samples = @($samples | Where-Object { Test-Path -LiteralPath $_ })
  foreach ($k in $Repos.Keys) {
    $tmp = Join-Path $env:TEMP ('statebackup-rt-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
      $snap = (Invoke-Rs $k @('snapshots', '--host', 'luan-nitro5', '--tag', 'state', '--latest', '1') -Json).out | Where-Object { $_ -match '^\[' } | ConvertFrom-Json | Select-Object -Last 1
      if (-not $snap) { throw 'sem snapshot' }
      $snapTime = [DateTime]::Parse($snap.time).ToUniversalTime()
      $chk = @("$env:LOCALAPPDATA\hermes\state.db", "$env:LOCALAPPDATA\hermes\kanban.db", "$HOME\projects\personal\meubot\agente_estado\fila_duravel.sqlite3", "$HOME\.codex\state_5.sqlite", "$HOME\projects\personal\compras\data\compras.sqlite3")
      $inc = @($samples) + @($chk | ForEach-Object { Join-Path "$SB\staging\sqlite" ($_.Substring(0, 1) + $_.Substring(2)) }) + @("$SB\staging\manifest", "$SB\staging\server-state")
      $incArgs = @(); # restaura so a subarvore do HOME (snap:/C/Users/luanc): restaurar C\ e C\Users aplicaria as ACLs originais deles na pasta temporaria e travaria o restore
      foreach ($p in $inc) { $incArgs += @('--include', ('/' + ($p.Substring($HOME.Length + 1) -replace '\\', '/'))) }
      $tr = Get-Date
      $r = Invoke-Rs $k (@('restore', ($snap.id + ':/' + ($HOME.Substring(0, 1) + $HOME.Substring(2)) -replace '\\', '/'), '--target', $tmp) + $incArgs)
      if ($r.code -ne 0) { throw "restore code=$($r.code)" }
      $rsecs = [int]((Get-Date) - $tr).TotalSeconds
      function RPath([string]$p) { Join-Path $tmp $p.Substring($HOME.Length + 1) }
      # hashes (arquivos que nao mudaram desde o snapshot)
      $same = 0; $diff = 0; $changed = 0; $missing = 0
      foreach ($p in $samples) {
        $rp2 = RPath $p
        if (-not (Test-Path -LiteralPath $rp2)) { $missing++; Log "  RT $k faltando: $p"; continue }
        if ((Get-Item -LiteralPath $p).LastWriteTimeUtc -gt $snapTime) { $changed++; continue }
        $h1 = (Get-FileHash -LiteralPath $p).Hash; $h2 = (Get-FileHash -LiteralPath $rp2).Hash
        if ($h1 -eq $h2) { $same++; Log ("  RT {0} hash ok {1} {2}" -f $k, $h2.Substring(0, 12).ToLowerInvariant(), $p.Substring($HOME.Length + 1)) } else { $diff++; Log "  RT $k HASH DIFERENTE: $p" }
      }
      Log ("RT {0}: snapshot {1} restore {2}s; hashes iguais={3} diferentes={4} mudaram-depois={5} faltando={6}" -f $k, $snap.short_id, $rsecs, $same, $diff, $changed, $missing)
      if ($diff -or $missing) { $allOk = $false }
      # SQLite consistentes
      foreach ($db in $chk) {
        $sp = Join-Path (RPath "$SB\staging\sqlite") ($db.Substring(0, 1) + $db.Substring(2))
        if (-not (Test-Path -LiteralPath $sp)) { Log "  RT $k sqlite faltando: $db"; $allOk = $false; continue }
        $ic = & $Py (Join-Path $here 'sqlite_check.py') $sp 2>&1
        Log ("  RT {0} sqlite {1}: integrity={2}" -f $k, (Split-Path $db -Leaf), $ic)
        if ("$ic" -notmatch '^ok ') { $allOk = $false }
      }
      # tar do servidor: sha256 e decifra com a identidade age (DPAPI)
      $lj = RPath "$SB\staging\server-state\latest.json"
      if (Test-Path $lj) {
        $l = Get-Content $lj -Raw | ConvertFrom-Json; $art = RPath "$SB\staging\server-state\$($l.file)"
        $okSha = ((Get-FileHash -Algorithm SHA256 -LiteralPath $art).Hash.ToLowerInvariant() -eq $l.sha256)
        $idf = Join-Path $tmp 'id.txt'; [IO.File]::WriteAllText($idf, (Unprotect (Join-Path $SB 'age-identity.dpapi')), (New-Object Text.UTF8Encoding($false)))
        $ageExe = (Get-Command age -ErrorAction SilentlyContinue).Source; if (-not $ageExe) { $ageExe = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter age.exe | Select-Object -First 1).FullName }
        & $ageExe -d -i $idf -o (Join-Path $tmp 's.tar.zst') $art 2>$null; $dec = ($LASTEXITCODE -eq 0)
        Remove-Item -LiteralPath $idf -Force
        $magic = if ($dec) { ([IO.File]::ReadAllBytes((Join-Path $tmp 's.tar.zst')) | Select-Object -First 4 | ForEach-Object { $_.ToString('x2') }) -join '' } else { '' }
        Log ("  RT {0} servidor {1}: sha256={2} age_decrypt={3} zstd_magic={4}" -f $k, $l.file, $okSha, $dec, ($magic -eq '28b52ffd'))
        if (-not ($okSha -and $dec -and $magic -eq '28b52ffd')) { $allOk = $false }
      } else { Log "  RT $k sem tar do servidor no snapshot"; $allOk = $false }
      if (-not (Test-Path (RPath "$SB\staging\manifest\winget.json"))) { Log "  RT $k manifesto faltando"; $allOk = $false } else { Log "  RT $k manifesto ok" }
    } catch { Log "RT ${k}: FALHA $($_.Exception.Message)"; $allOk = $false }
    finally { if (Test-Path $tmp) { & icacls $tmp /reset /T /C /Q *> $null; & cmd /d /c "rd /s /q `"\\?\$tmp`"" *> $null }; Log "  RT $k pasta temporaria apagada: $(-not (Test-Path $tmp))" }
  }
  Set-StatusField 'last_restore_test' ([pscustomobject]@{ at_utc = [DateTime]::UtcNow.ToString('o'); ok = $allOk })
  if (-not $allOk) { Alert 'teste de restore do backup falhou (ver log StateBackup)'; exit 1 }
  Log 'RT_OK'
}
'Freshness' {
  $s = Get-Status; $now = [DateTime]::UtcNow; $stale = @()
  foreach ($k in $Repos.Keys) {
    $f = $s."last_ok_$k"
    if (-not $f) { $stale += "$k (nunca)"; continue }
    $h = ($now - [DateTime]::Parse($f.at_utc).ToUniversalTime()).TotalHours
    if ($h -gt $cfgRaw.FreshnessHours) { $stale += ("{0} ({1:N0}h)" -f $k, $h) }
  }
  if ($stale.Count) {
    $lastAlert = $s.'last_freshness_alert_utc'
    if (-not $lastAlert -or ($now - [DateTime]::Parse($lastAlert).ToUniversalTime()).TotalHours -ge 12) { Alert ("backup atrasado: " + ($stale -join ', ')); Set-StatusField 'last_freshness_alert_utc' $now.ToString('o') }
    Log ("atrasado: " + ($stale -join ', '))
  } else { Log 'fresco' }
}
}
} finally { $env:RESTIC_PASSWORD = $null; Remove-Item Env:RESTIC_PASSWORD -ErrorAction SilentlyContinue; $mutex.ReleaseMutex() }