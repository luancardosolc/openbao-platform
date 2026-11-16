#requires -Version 5.1
<#
.SYNOPSIS
  Le um item Bitwarden em memoria e grava um arquivo so de root no servidor. Nunca imprime o payload.

.DESCRIPTION
  Para unseal/rekey no servidor, sem trazer chaves para a tela.
  Imprime apenas: PATH, BYTES, SHA256_PREFIX (8 chars), OK ou FAIL.

  powershell -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-HetznerBitwardenToRemoteFile.ps1 -ItemName 'OpenBao prod / unseal+recovery (rekey 2026-11-15)' -RemotePath /root/hzroot-keys-from-bw.json
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ItemName,

  [Parameter(Mandatory = $true)]
  [string]$RemotePath,

  [string]$FolderName = 'Hetzner',

  [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'HetznerRoot.Common.ps1')

if ($RemotePath -match '"') { Write-HzErr 'FAIL'; Write-HzErr 'remote path must not contain double quotes'; exit 2 }
if ($RemotePath -notmatch '^/') { Write-HzErr 'FAIL'; Write-HzErr 'remote path must be absolute'; exit 2 }

$exitCode = 2
$payload = $null
$sshConfig = $null
$stage = $null
try {
  $session = Get-HzBwSession
  $env:BW_SESSION = $session
  $py = Get-HzPython
  $getter = Join-Path $here 'bw-get-secret.py'
  if (-not (Test-Path -LiteralPath $getter)) { throw 'bw-get-secret.py not found' }
  $got = Invoke-HzProcess -FileName $py -ArgumentList @($getter, '--name', $ItemName, '--folder', $FolderName) -TimeoutSeconds 180 -Environment @{ BW_SESSION = $session }
  if ($got.ExitCode -ne 0) {
    Write-Output 'FAIL'
    $errRed = Protect-HzOutput -Text $got.Stderr
    if ($errRed) { Write-HzErr $errRed }
    exit 2
  }
  $payload = $got.StdoutBytes
  if (-not $payload -or $payload.Length -lt 1) {
    Write-Output 'FAIL'
    Write-HzErr 'empty payload'
    exit 2
  }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $digest = ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant()
  } finally { $sha.Dispose() }

  # luan cannot write root-only paths: stage in /tmp (umask 077), then root installs it 600 and shreds the stage.
  $stage = '/tmp/hzroot-up-{0}.bin' -f [guid]::NewGuid().ToString('n').Substring(0, 16)
  $upload = Get-HzUploadRemoteCommand $stage
  $sshExe = Get-HzSshExe
  $sshConfig = New-HzSshConfig
  $up = Invoke-HzSshRaw -SshExe $sshExe -Config $sshConfig -RemoteCommand $upload -StdinBytes $payload -TimeoutSeconds 30
  if ($up.ExitCode -ne 0) { throw ('upload failed rc={0}' -f $up.ExitCode) }

  $hashCmd = 'install -o root -g root -m 600 -- {1} {0} && shred -u -- {1}; rm -f -- {1}; chown root:root -- {0} && chmod 600 -- {0} && sha256sum -- {0} && wc -c -- {0}' -f $RemotePath, $stage
  $prep = Invoke-HzRootCommand -Command $hashCmd -TimeoutSeconds $TimeoutSeconds
  if ($prep.ExitCode -ne 0) { throw 'remote chmod/hash failed' }

  $remoteHash = $null
  $remoteLen = $null
  foreach ($line in (($prep.Stdout -replace '\r','') -split "`n")) {
    $t = $line.Trim()
    if ($t -match '^([0-9a-fA-F]{64})\s+') { $remoteHash = $Matches[1].ToLowerInvariant() }
    elseif ($t -match '^(\d+)\s+') { $remoteLen = [int64]$Matches[1] }
    elseif ($t -match '^[0-9a-fA-F]{64}$') { $remoteHash = $t.ToLowerInvariant() }
    elseif ($t -match '^\d+$') { $remoteLen = [int64]$t }
  }
  if ($remoteHash -ne $digest) { throw 'hash mismatch after upload' }
  if ($null -ne $remoteLen -and $remoteLen -ne [int64]$payload.Length) { throw 'length mismatch after upload' }

  Write-Output ('PATH={0}' -f $RemotePath)
  Write-Output ('BYTES={0}' -f $payload.Length)
  Write-Output ('SHA256_PREFIX={0}' -f $digest.Substring(0, 8))
  Write-Output 'OK'
  $exitCode = 0
}
catch {
  Write-Output 'FAIL'
  $msg = Protect-HzOutput -Text ([string]$_.Exception.Message)
  if ($msg) { Write-HzErr $msg }
  $exitCode = 2
}
finally {
  $payload = $null
  if ($stage -and $sshExe -and $sshConfig) {
    try { [void](Invoke-HzSshRaw -SshExe $sshExe -Config $sshConfig -RemoteCommand ('rm -f -- {0}' -f $stage) -TimeoutSeconds 20) } catch { }
  }
  if ($sshConfig -and (Test-Path -LiteralPath $sshConfig)) {
    try { Remove-Item -LiteralPath $sshConfig -Force } catch { }
  }
}

exit $exitCode
