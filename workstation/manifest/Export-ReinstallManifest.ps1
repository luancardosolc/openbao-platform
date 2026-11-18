#requires -Version 5.1
<#
.SYNOPSIS
  Gera o manifesto de reinstalacao do PC (para uma IA reinstalar tudo num PC novo). Sem segredos.
.DESCRIPTION
  Saidas em -OutDir: winget.json (winget export), scoop.txt, npm-global.json, uv-tools.txt, pyenv.txt, nvm.txt,
  clis.json (nome, versao, caminho), repos.json (todos os repos em projects, com remote/branch/HEAD), scheduled-tasks.json
  (tarefas do usuario que rodam scripts dos projetos) e manifest.json (indice + data BRT).
.EXAMPLE
  powershell -NoProfile -File Export-ReinstallManifest.ps1 -OutDir C:\temp\manifest
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutDir, [string]$ProjectsRoot = "$HOME\projects")
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $OutDir | Out-Null
function Save($name, $obj) { $p = Join-Path $OutDir $name; if ($obj -is [string]) { [IO.File]::WriteAllText($p, $obj, (New-Object Text.UTF8Encoding($false))) } else { [IO.File]::WriteAllText($p, ($obj | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false))) } }
function Run([string]$exe, [string[]]$a, [int]$timeout = 120) {
  $c = Get-Command $exe -ErrorAction SilentlyContinue
  if (-not $c) { $alt = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "$exe*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1; if ($alt) { $c = [pscustomobject]@{ Source = $alt.FullName } } else { return $null } }
  $psi = New-Object Diagnostics.ProcessStartInfo $c.Source; $psi.Arguments = ($a -join ' '); $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  if ($c.Source -match '\.ps1$') { $psi.FileName = 'powershell.exe'; $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $c.Source + '" ' + ($a -join ' ') }
  elseif ($c.Source -match '\.(cmd|bat)$') { $psi.FileName = 'cmd.exe'; $psi.Arguments = '/d /s /c ""' + $c.Source + '" ' + ($a -join ' ') + '"' }
  $p = [Diagnostics.Process]::Start($psi); $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($timeout * 1000)) { try { $p.Kill() } catch {}; return $null }
  return (($o.Result + "`n" + $e.Result).Trim())
}
$now = [TimeZoneInfo]::ConvertTime([DateTime]::UtcNow, [TimeZoneInfo]::FindSystemTimeZoneById('E. South America Standard Time'))
# winget
$wj = Join-Path $OutDir 'winget.json'; & winget export -o $wj --accept-source-agreements --disable-interactivity *> $null
# scoop
Save 'scoop.json' ((Run 'scoop' @('export') 180) + "")
# npm global
$npm = Run 'npm' @('ls', '-g', '--depth=0', '--json'); Save 'npm-global.json' ($npm + "")
# uv tools, pyenv, nvm
Save 'uv-tools.txt' ((Run 'uv' @('tool', 'list')) + "")
Save 'pyenv.txt' ("global: " + (Run 'pyenv' @('global')) + "`nversions:`n" + (Run 'pyenv' @('versions')))
$nvmRoot = "$HOME\scoop\apps\nvm\current\nodejs"; Save 'nvm.txt' (((Get-ChildItem $nvmRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join "`n") + "`ncurrent: " + (Run 'node' @('--version')))
# CLIs
$clis = foreach ($n in 'codex','claude','agy','opencode','gemini','orca','netbird','bw','gh','git','node','npm','uv','pyenv','scoop','restic','age','7z','ffmpeg','rg','openspec','wrangler','hermes','ollama','az','kubectl','helm','gcloud','psql') {
  $c = Get-Command $n -ErrorAction SilentlyContinue
  if (-not $c) { $alt = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "$n*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1; if ($alt) { $c = [pscustomobject]@{ Source = $alt.FullName } } }
  $v = $null
  if ($c) { $arg = if ($n -in 'netbird','restic') { 'version' } elseif ($n -in 'kubectl','helm') { 'version --client' } elseif ($n -eq '7z') { '' } elseif ($n -eq 'pyenv') { '--version' } else { '--version' }; $v = Run $n @($arg) 60; if ($v) { $v = (($v -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 1).Trim() } }
  [pscustomobject]@{ name = $n; installed = [bool]$c; version = $v; path = $(if ($c) { $c.Source } else { $null }) }
}
Save 'clis.json' @($clis)
# Python fixo dos scripts (MeuBot, backup)
Save 'python.txt' ("scripts usam: $HOME\.pyenv\pyenv-win\versions\3.13.1-win32\python.exe`n" + (Run "$HOME\.pyenv\pyenv-win\versions\3.13.1-win32\python.exe" @('-m','pip','freeze') 120))
# repos
$repos = Get-ChildItem $ProjectsRoot -Recurse -Directory -Force -Filter .git -Depth 5 -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\node_modules\\' } | ForEach-Object {
  $r = $_.Parent.FullName
  [pscustomobject]@{ path = $r.Substring($ProjectsRoot.Length).TrimStart('\'); remotes = @(& git -C $r remote -v 2>$null | Where-Object { $_ -match '\(fetch\)' } | ForEach-Object { ($_ -split '\s+')[0..1] -join ' ' }); branch = (& git -C $r rev-parse --abbrev-ref HEAD 2>$null); head = (& git -C $r rev-parse HEAD 2>$null) }
}
Save 'repos.json' @($repos)
# tarefas agendadas do usuario que apontam para scripts locais
$tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -eq '\' } | ForEach-Object { [pscustomobject]@{ name = $_.TaskName; state = "$($_.State)"; actions = @($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }); triggers = @($_.Triggers | ForEach-Object { $_.CimClass.CimClassName -replace 'MSFT_Task','' }) } }
Save 'scheduled-tasks.json' @($tasks)
$files = Get-ChildItem $OutDir -File | Where-Object { $_.Name -ne 'manifest.json' } | ForEach-Object { [pscustomobject]@{ file = $_.Name; bytes = $_.Length } }
Save 'manifest.json' ([pscustomobject]@{ generated_brt = $now.ToString('yyyy-MM-dd HH:mm'); host = $env:COMPUTERNAME; files = @($files); winget_packages = $(try { @((Get-Content $wj -Raw | ConvertFrom-Json).Sources.Packages).Count } catch { 0 }) })
Write-Output ("MANIFEST_OK dir={0} files={1}" -f $OutDir, @($files).Count)