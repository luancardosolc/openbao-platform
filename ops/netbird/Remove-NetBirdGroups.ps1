<#
Remove-NetBirdGroups.ps1 - apaga, de forma idempotente, uma lista EXPLICITA de grupos NetBird sem uso.
Antes de apagar: confere que nenhum id aparece em policies, routes, DNS (nameservers e settings), setup keys,
users (auto_groups), posture checks, accounts e networks (routers/resources). Se aparecer, ou se algum alvo
for um grupo protegido (All, admin-pc, hetzner-vps), aborta sem apagar nada.
O PAT vem do item Bitwarden (notes) so em memoria. Saida: so marcadores.
  $env:BW_SESSION = & 'C:\Users\luanc\agent-tools\bw-auto-unlock\Get-BwSession.ps1'
  powershell -NoProfile -ExecutionPolicy Bypass -File .\ops\netbird\Remove-NetBirdGroups.ps1 [-CheckOnly]
#>
[CmdletBinding()]
param(
  [string[]]$GroupIds = @('dbu3emitm4ms73cqtg4g', 'dbu3emitm4ms73cqtg5g', 'dbu3foitm4ms73cqtgdg', 'dbu3foitm4ms73cqtgeg'),
  [string[]]$ProtectedNames = @('All', 'admin-pc', 'hetzner-vps'),
  [string]$BitwardenItem = 'NetBird / API token owner (2026-11-17)',
  [string]$BaseUri = 'https://46.224.228.253.sslip.io/api',
  [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:Pat = $null

function Invoke-NbRaw([string]$Method, [string]$Path) {
  $r = Invoke-WebRequest -UseBasicParsing -Method $Method -Uri "$BaseUri$Path" -TimeoutSec 30 -ErrorAction Stop `
    -Headers @{ Authorization = "Token $script:Pat"; Accept = 'application/json' }
  return [string]$r.Content
}
function From-Json([string]$s) { $o = $s | ConvertFrom-Json; return ,@($o | ForEach-Object { $_ }) }

try {
  if (-not $env:BW_SESSION) { throw 'BW_SESSION missing' }
  if ($GroupIds.Count -lt 1) { throw 'no ids' }
  foreach ($id in $GroupIds) { if ($id -notmatch '^[a-z0-9]{20}$') { throw "bad id $id" } }
  $items = @((& bw list items --search $BitwardenItem 2>$null) | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.name -eq $BitwardenItem })
  if ($items.Count -ne 1) { throw "bw item count=$($items.Count)" }
  $script:Pat = ([string]$items[0].notes).Trim(); $items = $null
  if ($script:Pat.Length -lt 20) { throw 'empty token' }

  $groups = From-Json (Invoke-NbRaw 'Get' '/groups')
  $targets = @($groups | Where-Object { $GroupIds -contains [string]$_.id })
  foreach ($t in $targets) { if ($ProtectedNames -contains [string]$t.name) { throw "protected group targeted: $($t.name)" } }
  foreach ($id in $GroupIds) { if (-not (@($targets | Where-Object { [string]$_.id -eq $id }).Count)) { Write-Output "GROUP_ABSENT id=$id" } }
  if ($targets.Count -eq 0) { Write-Output 'DONE deleted=0'; exit 0 }

  $paths = @('/policies', '/routes', '/dns/nameservers', '/dns/settings', '/setup-keys', '/users', '/posture-checks', '/accounts', '/networks')
  $bodies = @{}
  foreach ($p in $paths) { $bodies[$p] = Invoke-NbRaw 'Get' $p }
  foreach ($n in (From-Json $bodies['/networks'])) {
    foreach ($sub in 'routers', 'resources') { $bodies["/networks/$($n.id)/$sub"] = Invoke-NbRaw 'Get' "/networks/$($n.id)/$sub" }
  }
  $refs = 0
  foreach ($t in $targets) {
    foreach ($k in $bodies.Keys) { if ($bodies[$k].Contains([string]$t.id)) { Write-Output "FAIL ref id=$($t.id) in $k"; $refs++ } }
  }
  Write-Output "REFS_CHECKED endpoints=$($bodies.Count) refs=$refs"
  if ($refs -gt 0) { Write-Output 'FAIL aborted: referenced'; exit 1 }

  $deleted = 0
  foreach ($t in $targets) {
    if ($CheckOnly) { Write-Output "WOULD_DELETE id=$($t.id) name=$($t.name)"; continue }
    [void](Invoke-NbRaw 'Delete' "/groups/$($t.id)")
    Write-Output "GROUP_DELETED id=$($t.id) name=$($t.name)"; $deleted++
  }
  if (-not $CheckOnly) {
    $left = @(From-Json (Invoke-NbRaw 'Get' '/groups') | Where-Object { $GroupIds -contains [string]$_.id })
    if ($left.Count) { Write-Output "FAIL still_present=$($left.Count)"; exit 1 }
  }
  Write-Output "DONE deleted=$deleted"; exit 0
} catch {
  $m = [string]$_.Exception.Message
  if ($script:Pat) { $m = $m.Replace($script:Pat, '[REDACTED]') }
  Write-Output ('FAIL ' + ($m -replace '\s+', ' ').Substring(0, [Math]::Min(160, $m.Length)))
  exit 1
} finally { $script:Pat = $null }