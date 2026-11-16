#requires -Version 5.1
<#
.SYNOPSIS
  Roda um comando como root no Hetzner e grava a saida SO em um item Bitwarden. Nunca imprime o payload.

.DESCRIPTION
  Captura stdout do comando (via su) so em memoria, cria/atualiza um Secure Note na pasta Hetzner
  (notas + anexo), faz bw sync e confere o SHA-256 em processo.
  Imprime apenas: ITEM, BYTES, SHA256_PREFIX (8 chars), OK ou FAIL.

  powershell -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-HetznerSecretToBitwarden.ps1 -Command 'cat /opt/openbao/bootstrap/bootstrap.json' -ItemName 'OpenBao prod / bootstrap antigo (comprometido 2026-11-15)'
#>
[CmdletBinding(DefaultParameterSetName = 'Command')]
param(
  [Parameter(ParameterSetName = 'Command', Mandatory = $true)]
  [string]$Command,

  [Parameter(ParameterSetName = 'ScriptFile', Mandatory = $true)]
  [string]$ScriptFile,

  [Parameter(Mandatory = $true)]
  [string]$ItemName,

  [string]$FolderName = 'Hetzner',

  [string]$AttachmentName = 'payload.bin',

  [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'HetznerRoot.Common.ps1')

function Write-HzMeta([string]$Text) {
  [Console]::Out.WriteLine($Text)
}

function ConvertFrom-HzCaptureMeta {
  param([string]$RawPty)
  if ([string]::IsNullOrEmpty($RawPty)) { return $null }
  $meta = @{ Rc = $null; Bytes = $null; Sha256 = $null; Path = $null; ErrPath = $null }
  foreach ($line in ($RawPty -split "\r?\n")) {
    $t = $line.Trim()
    if ($t -match '^HZROOT_RC=(\-?\d+)$') { $meta.Rc = [int]$Matches[1] }
    elseif ($t -match '^HZROOT_BYTES=(\d+)$') { $meta.Bytes = [int64]$Matches[1] }
    elseif ($t -match '^HZROOT_SHA256=([0-9a-fA-F]{64})$') { $meta.Sha256 = $Matches[1].ToLowerInvariant() }
    elseif ($t -match '^HZROOT_PATH=(/\S+)$') { $meta.Path = $Matches[1] }
    elseif ($t -match '^HZROOT_ERR_PATH=(/\S+)$') { $meta.ErrPath = $Matches[1] }
  }
  if (-not $meta.Path) { return $null }
  return [pscustomobject]$meta
}

$exitCode = 2
$tmpWrap = $null
$remoteOut = $null
$remoteLuan = $null
$remoteErr = $null
try {
  if ([string]::IsNullOrWhiteSpace($ItemName)) { throw 'missing item name' }

  if ($PSCmdlet.ParameterSetName -eq 'ScriptFile') {
    $inner = [IO.File]::ReadAllText($ScriptFile).Replace("`r`n", "`n").Replace("`r", "`n")
  } else {
    $inner = $Command.Replace("`r`n", "`n").Replace("`r", "`n")
  }

  $nl = [char]10
  # Fixed, pre-known capture paths so the finally block always cleans them up,
  # even if the remote metadata never comes back.
  $capRand = [guid]::NewGuid().ToString('n').Substring(0, 16)
  $remoteOut = '/tmp/hzroot-cap-{0}.out' -f $capRand
  $remoteErr = '/tmp/hzroot-cap-{0}.err' -f $capRand
  $remoteLuan = $remoteOut + '.luan'
  $wrapped = @(
    '#!/bin/bash',
    'set +e',
    'umask 077',
    ('OUT={0}' -f $remoteOut),
    ('ERR={0}' -f $remoteErr),
    ': >"$OUT"; : >"$ERR"',
    '{',
    $inner,
    '} >"$OUT" 2>"$ERR"',
    'rc=$?',
    'python3 -c ''',
    'import os, sys, hashlib',
    'out, err, rc = sys.argv[1], sys.argv[2], int(sys.argv[3])',
    'data = open(out, "rb").read() if os.path.exists(out) else b""',
    'sys.stdout.write("HZROOT_RC=%d\n" % rc)',
    'sys.stdout.write("HZROOT_BYTES=%d\n" % len(data))',
    'sys.stdout.write("HZROOT_SHA256=%s\n" % hashlib.sha256(data).hexdigest())',
    'sys.stdout.write("HZROOT_PATH=%s\n" % out)',
    'sys.stdout.write("HZROOT_ERR_PATH=%s\n" % err)',
    ''' "$OUT" "$ERR" "$rc"',
    'exit 0',
    ''
  ) -join $nl

  $tmpWrap = Join-Path $env:TEMP ('hzroot-wrap-{0}.sh' -f [guid]::NewGuid().ToString('n'))
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText($tmpWrap, $wrapped.Replace("`r`n", "`n"), $utf8NoBom)

  $run = Invoke-HzRootCommand -ScriptFile $tmpWrap -TimeoutSeconds $TimeoutSeconds -AllowSecretPaths
  Clear-HzLocalFile $tmpWrap
  $tmpWrap = $null

  $meta = ConvertFrom-HzCaptureMeta -RawPty $run.Stdout
  if (-not $meta) {
    Write-HzMeta 'FAIL'
    Write-HzErr 'capture metadata missing'
    if ($run.ExitCode -ne 0) { Write-HzErr ('helper exit {0}' -f $run.ExitCode) }
    exit 2
  }
  if ($meta.Path -ne $remoteOut) { throw 'unexpected capture path' }
  if ($null -ne $meta.Rc -and $meta.Rc -ne 0) {
    Write-HzMeta 'FAIL'
    Write-HzErr ('remote command exit {0}' -f $meta.Rc)
    exit 2
  }
  if (-not $meta.Bytes -or $meta.Bytes -lt 1) {
    Write-HzMeta 'FAIL'
    Write-HzErr 'empty captured payload'
    exit 2
  }

  $prep = Invoke-HzRootCommand -Command ('cp -- {0} {1} && chown luan:luan -- {1} && chmod 400 -- {1}' -f $remoteOut, $remoteLuan) -TimeoutSeconds 60
  if ($prep.ExitCode -ne 0) { throw 'could not stage capture for download' }

  $sshExe = Get-HzSshExe
  $sshConfig = New-HzSshConfig
  try {
    $dl = Invoke-HzSshRaw -SshExe $sshExe -Config $sshConfig -RemoteCommand (Get-HzDownloadRemoteCommand $remoteLuan) -TimeoutSeconds 60
  }
  finally {
    if ($sshConfig -and (Test-Path -LiteralPath $sshConfig)) {
      try { Remove-Item -LiteralPath $sshConfig -Force } catch { }
    }
  }
  if ($dl.ExitCode -ne 0) { throw 'download of capture failed' }
  $payload = $dl.StdoutBytes
  if (-not $payload -or $payload.Length -lt 1) { throw 'downloaded capture was empty' }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $digest = ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant()
  } finally { $sha.Dispose() }
  if ($meta.Sha256 -and $digest -ne $meta.Sha256) { throw 'hash mismatch between remote capture and download' }
  if ([int64]$payload.Length -ne $meta.Bytes) { throw 'length mismatch between remote capture and download' }

  $session = Get-HzBwSession
  $env:BW_SESSION = $session
  $py = Get-HzPython
  $putter = Join-Path $here 'bw-put-secret.py'
  if (-not (Test-Path -LiteralPath $putter)) { throw 'bw-put-secret.py not found' }
  $put = Invoke-HzProcess -FileName $py -ArgumentList @($putter, '--name', $ItemName, '--folder', $FolderName, '--attachment-name', $AttachmentName) -StdinBytes $payload -TimeoutSeconds 180 -Environment @{ BW_SESSION = $session }
  $session = $null
  $payload = $null
  if ($put.Stdout) { [Console]::Out.Write($put.Stdout) }
  if ($put.Stderr) {
    $errRed = Protect-HzOutput -Text $put.Stderr
    if ($errRed) { Write-HzErr $errRed }
  }
  if ($put.ExitCode -ne 0) { exit 2 }
  $exitCode = 0
}
catch {
  Write-HzMeta 'FAIL'
  $msg = Protect-HzOutput -Text ([string]$_.Exception.Message)
  if ($msg) { Write-HzErr $msg }
  $exitCode = 2
}
finally {
  if ($tmpWrap) { Clear-HzLocalFile $tmpWrap }
  $paths = @($remoteOut, $remoteLuan, $remoteErr) | Where-Object { $_ }
  if ($paths -and $paths.Count -gt 0) {
    try {
      $rm = ($paths | ForEach-Object { $_ }) -join ' '
      [void](Invoke-HzRootCommand -Command ('shred -u -- {0} 2>/dev/null; rm -f -- {0}' -f $rm) -TimeoutSeconds 60)
    } catch { }
  }
}

exit $exitCode
