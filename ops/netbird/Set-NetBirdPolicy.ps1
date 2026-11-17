<#
Set-NetBirdPolicy.ps1 - garante (idempotente) a policy NetBird do PC do Luan para o OpenBao em TCP 8200.
  origem  = grupo admin-pc     (deve conter EXATAMENTE o peer luan-nitro5 / 100.102.188.162)
  destino = grupo hetzner-vps  (deve conter EXATAMENTE o peer openbao-platform-prod-openbao / 100.102.58.164)
  regra   = accept, tcp, porta 8200, nao bidirecional
Nao cria nem apaga grupos; nao toca em outras policies. Adota uma policy com nome legado (-LegacyNames) e a renomeia.
O PAT vem do item Bitwarden (notes) so em memoria; nunca vai para tela, argv ou disco.
Saida: so marcadores GROUP_OK, POLICY_CREATED, POLICY_UPDATED, POLICY_OK, FAIL <motivo>.
  $env:BW_SESSION = & 'C:\Users\luanc\agent-tools\bw-auto-unlock\Get-BwSession.ps1'
  powershell -NoProfile -ExecutionPolicy Bypass -File .\ops\netbird\Set-NetBirdPolicy.ps1 [-CheckOnly]
#>
[CmdletBinding()]
param(
  [string]$BitwardenItem = 'NetBird / API token owner (2026-11-17)',
  [string]$BaseUri = 'https://46.224.228.253.sslip.io/api',
  [string]$PolicyName = 'pc-luan -> openbao 8200',
  [string[]]$LegacyNames = @('PC Luan to OpenBao 8200'),
  [string]$SourceGroup = 'admin-pc',
  [string]$SourcePeerName = 'luan-nitro5',
  [string]$SourcePeerIp = '100.102.188.162',
  [string]$DestinationGroup = 'hetzner-vps',
  [string]$DestinationPeerName = 'openbao-platform-prod-openbao',
  [string]$DestinationPeerIp = '100.102.58.164',
  [string]$Port = '8200',
  [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:Pat = $null

function Invoke-NbApi([string]$Method, [string]$Path, $Body = $null) {
  $params = @{ Method = $Method; Uri = "$BaseUri$Path"; TimeoutSec = 30; ErrorAction = 'Stop'
    Headers = @{ Authorization = "Token $script:Pat"; Accept = 'application/json' } }
  if ($null -ne $Body) { $params.ContentType = 'application/json'; $params.Body = ConvertTo-Json -InputObject $Body -Depth 16 -Compress }
  return Invoke-RestMethod @params
}
# PS 5.1: Invoke-RestMethod devolve um array JSON como UM objeto; desembrulha sempre.
function Get-NbList([string]$Path) { $r = Invoke-NbApi 'Get' $Path; return ,@($r | ForEach-Object { $_ }) }
function Get-Ids($xs) { return ,@(@($xs) | ForEach-Object { if ($_ -is [string]) { $_ } else { [string]$_.id } } | Where-Object { $_ } | Sort-Object -Unique) }

function Get-CheckedGroup($groups, [string]$name, $peer) {
  $g = @($groups | Where-Object { $_.name -eq $name })
  if ($g.Count -ne 1) { throw "group $name count=$($g.Count)" }
  $members = Get-Ids $g[0].peers
  if ($members.Count -ne 1 -or $members[0] -ne [string]$peer.id) { throw "group $name members=$($members.Count) not exactly $($peer.name)" }
  return $g[0]
}

try {
  if (-not $env:BW_SESSION) { throw 'BW_SESSION missing' }
  $items = @((& bw list items --search $BitwardenItem 2>$null) | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.name -eq $BitwardenItem })
  if ($items.Count -ne 1) { throw "bw item count=$($items.Count)" }
  $script:Pat = ([string]$items[0].notes).Trim(); $items = $null
  if ($script:Pat.Length -lt 20) { throw 'empty token' }

  $peers = Get-NbList '/peers'
  $pc = @($peers | Where-Object { $_.name -eq $SourcePeerName -and $_.ip -eq $SourcePeerIp })
  $srv = @($peers | Where-Object { $_.name -eq $DestinationPeerName -and $_.ip -eq $DestinationPeerIp })
  if ($pc.Count -ne 1 -or $srv.Count -ne 1) { throw "peers pc=$($pc.Count) server=$($srv.Count)" }

  $groups = Get-NbList '/groups'
  $src = Get-CheckedGroup $groups $SourceGroup $pc[0]
  $dst = Get-CheckedGroup $groups $DestinationGroup $srv[0]
  Write-Output "GROUP_OK src=$SourceGroup dst=$DestinationGroup"

  $expected = @{
    name = $PolicyName; description = 'PC do Luan (luan-nitro5) -> OpenBao (hetzner) TCP 8200, so ida.'; enabled = $true
    rules = @(@{ name = 'openbao-tcp-8200'; description = 'TCP 8200 one-way'; enabled = $true; action = 'accept'
      bidirectional = $false; protocol = 'tcp'; ports = @($Port); sources = @([string]$src.id); destinations = @([string]$dst.id) })
  }
  $policies = Get-NbList '/policies'
  $named = @($policies | Where-Object { $_.name -eq $PolicyName })
  if ($named.Count -eq 0) { $named = @($policies | Where-Object { $LegacyNames -contains $_.name }) }
  if ($named.Count -gt 1) { throw "duplicate policies=$($named.Count)" }
  if ($named.Count -eq 0) {
    if ($CheckOnly) { Write-Output 'FAIL policy missing'; exit 1 }
    $c = Invoke-NbApi 'Post' '/policies' $expected
    Write-Output "POLICY_CREATED id=$($c.id)"; exit 0
  }
  $cur = $named[0]; $rules = @($cur.rules | ForEach-Object { $_ })
  $equal = $cur.name -eq $PolicyName -and $cur.enabled -eq $true -and $rules.Count -eq 1 -and
    $rules[0].enabled -eq $true -and $rules[0].action -eq 'accept' -and $rules[0].bidirectional -eq $false -and
    $rules[0].protocol -eq 'tcp' -and ((Get-Ids $rules[0].ports) -join ',') -eq $Port -and
    @($rules[0].port_ranges | Where-Object { $_ }).Count -eq 0 -and
    ((Get-Ids $rules[0].sources) -join ',') -eq [string]$src.id -and ((Get-Ids $rules[0].destinations) -join ',') -eq [string]$dst.id
  if ($equal) { Write-Output "POLICY_OK id=$($cur.id)"; exit 0 }
  if ($CheckOnly) { Write-Output "FAIL policy drift id=$($cur.id)"; exit 1 }
  $expected.rules[0].id = [string]$rules[0].id
  [void](Invoke-NbApi 'Put' "/policies/$($cur.id)" $expected)
  Write-Output "POLICY_UPDATED id=$($cur.id)"; exit 0
} catch {
  $m = [string]$_.Exception.Message
  if ($script:Pat) { $m = $m.Replace($script:Pat, '[REDACTED]') }
  Write-Output ('FAIL ' + ($m -replace '\s+', ' ').Substring(0, [Math]::Min(160, $m.Length)))
  exit 1
} finally { $script:Pat = $null }