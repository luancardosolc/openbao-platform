<#
Test-NoSecrets.ps1 - varredura de segredos (fallback sem gitleaks). Nunca imprime o valor: so arquivo:linha, tipo e 4 chars + ***.
Uso: .\Test-NoSecrets.ps1 -Repo <dir> [-Staged]   (sem -Staged: arquivos rastreados + nao ignorados)
Sai 1 se achar algo.
#>
param([Parameter(Mandatory)][string]$Repo, [switch]$Staged)
$ErrorActionPreference = 'Stop'
Push-Location $Repo
try {
  $files = if ($Staged) { git diff --cached --name-only --diff-filter=ACMR } else { git ls-files -co --exclude-standard }
  $rules = [ordered]@{
    'b64key44'  = '(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{43}=(?![A-Za-z0-9+/=])'
    'hex66'     = '(?<![0-9a-fA-F])[0-9a-fA-F]{66}(?![0-9a-fA-F])'
    'vaulttok'  = '(?<![A-Za-z0-9.])(?:hv[sbr]|s)\.[A-Za-z0-9_-]{20,}'
    'password'  = '(?i)(?<![A-Za-z$])pass(?:word|wd)?\s*[=:]\s*["'']?(?![\$%<{\[(]|[A-Z][a-z]+-[A-Z][A-Za-z]+\b|\*\*\*|REDACTED|example|changeme|xxx)[^\s"'',;]{6,}'
    'pem'       = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'ghtoken'   = '\b(?:ghp|gho|ghs|github_pat)_[A-Za-z0-9_]{20,}'
    'bwsession' = '(?i)BW_SESSION\s*=\s*["'']?[A-Za-z0-9+/=]{40,}'
  }
  $hits = 0
  foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
    $text = if ($Staged) { (git show ":$f") -join "`n" } else { [IO.File]::ReadAllText((Resolve-Path -LiteralPath $f)) }
    if ($text -match "`0") { continue }
    $lines = $text -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
      foreach ($k in $rules.Keys) {
        foreach ($m in [regex]::Matches($lines[$i], $rules[$k])) {
          $hits++; $v = $m.Value
          Write-Output ("HIT {0}:{1} {2} {3}***" -f $f, ($i + 1), $k, $v.Substring(0, [Math]::Min(4, $v.Length)))
        }
      }
    }
  }
  Write-Output "SECRET_SCAN files=$(@($files).Count) hits=$hits"
  if ($hits) { exit 1 }
} finally { Pop-Location }