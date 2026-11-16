#requires -Version 5.1
<#
.SYNOPSIS
  Unseal deterministico do OpenBao prod (Hetzner) com as chaves do Bitwarden. Nunca imprime chaves.
.DESCRIPTION
  1. Sessao Bitwarden via Get-BwSession.ps1 (nunca bw lock/logout).
  2. Invoke-HetznerBitwardenToRemoteFile.ps1 grava o item de unseal em arquivo so de root no servidor.
  3. Invoke-HetznerRoot.ps1 -MarkersOnly: espera a API, envia 3 chaves (jq -> curl --data @-, sem argv),
     imprime so linhas UNSEAL_*, e faz shred do arquivo (trap EXIT, sempre).
  Saida esperada: UNSEAL_BEFORE sealed=true ... UNSEAL_DONE sealed=false health=200 ... UNSEAL_SHRED ok
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-OpenBaoUnseal.ps1
#>
[CmdletBinding()]
param(
  [string]$ItemName = 'OpenBao prod / unseal+recovery (rekey 2026-11-15)',
  [string]$ApiAddr = 'https://100.102.58.164:8200',
  [string]$RemoteKeyFile = '/root/hzroot-unseal.json'
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $env:BW_SESSION) { $env:BW_SESSION = & 'C:\Users\luanc\agent-tools\bw-auto-unlock\Get-BwSession.ps1' 2>$null }
if ($ApiAddr -notmatch '^https://[0-9.]+:[0-9]+$') { Write-Output 'FAIL bad ApiAddr'; exit 2 }
if ($RemoteKeyFile -notmatch '^/root/hzroot-[a-z0-9.-]+$') { Write-Output 'FAIL bad RemoteKeyFile'; exit 2 }

$put = & (Join-Path $here 'Invoke-HetznerBitwardenToRemoteFile.ps1') -ItemName $ItemName -RemotePath $RemoteKeyFile *>&1 | ForEach-Object { "$_" }
$put | Where-Object { $_ -match '^(PATH|BYTES|SHA256_PREFIX|OK|FAIL)' } | ForEach-Object { Write-Output "KEYFILE $_" }
$putOk = ($put -contains 'OK') -and -not ($put -match '^FAIL')

$remote = @"
K=$RemoteKeyFile; A=$ApiAddr
trap 'if [ -e "`$K" ]; then shred -u "`$K" && echo "UNSEAL_SHRED ok" || echo "UNSEAL_SHRED FAIL"; else echo "UNSEAL_SHRED ok(absent)"; fi' EXIT
if [ ! -s "`$K" ]; then echo "FAIL keyfile missing"; exit 3; fi
i=0; until c=`$(curl -sk -o /dev/null -w '%{http_code}' "`$A/v1/sys/health"); [ "`$c" = 200 ] || [ "`$c" = 503 ] || [ "`$c" = 429 ]; do i=`$((i+1)); [ `$i -ge 60 ] && { echo "FAIL api not reachable code=`$c"; exit 4; }; sleep 2; done
S=`$(curl -sk "`$A/v1/sys/seal-status" | jq -r .sealed)
echo "UNSEAL_BEFORE sealed=`$S health=`$c"
if [ "`$S" = true ]; then
  T=`$(jq -r .threshold "`$K")
  n=0; while [ `$n -lt "`$T" ]; do
    jq -c "{key: .keys_base64[`$n]}" "`$K" | curl -sk -X PUT --data @- "`$A/v1/sys/unseal" | jq -r '"UNSEAL_STEP sealed=\(.sealed) progress=\(.progress)/\(.t)"'
    n=`$((n+1))
  done
fi
S=`$(curl -sk "`$A/v1/sys/seal-status" | jq -r .sealed); c=`$(curl -sk -o /dev/null -w '%{http_code}' "`$A/v1/sys/health")
echo "UNSEAL_DONE sealed=`$S health=`$c"
[ "`$S" = false ] && [ "`$c" = 200 ] || exit 5
"@
# Invoke-HetznerRoot escreve via [Console]::Out: roda em processo filho para capturar o stdout.
$tmp = Join-Path $env:TEMP ("hz-unseal-" + [guid]::NewGuid().ToString('N') + ".sh")
[IO.File]::WriteAllText($tmp, ($remote -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
try {
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Invoke-HetznerRoot.ps1') -MarkersOnly -MarkerPattern '^(UNSEAL_|FAIL)' -ScriptFile $tmp 2>&1 | ForEach-Object { "$_" }
  $rc = $LASTEXITCODE
} finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
$out | ForEach-Object { Write-Output $_ }
if (-not $putOk) { Write-Output 'FAIL keyfile upload'; exit 1 }
if ($rc -ne 0 -or -not ($out -match '^UNSEAL_DONE sealed=false health=200')) { Write-Output "FAIL rc=$rc"; exit 1 }
Write-Output 'OK'