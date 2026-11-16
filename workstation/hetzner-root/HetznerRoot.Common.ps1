#requires -Version 5.1
# Shared helpers for Invoke-HetznerRoot.ps1 and the secret Bitwarden scripts.
# Do not run this file directly.

$script:HetznerRootDir = $PSScriptRoot
if (-not $script:HetznerRootDir) {
  $script:HetznerRootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:HelperSource = Join-Path $script:HetznerRootDir 'su-pty-helper.py'
$script:RunCapture = Join-Path $script:HetznerRootDir 'run-capture.py'
$script:GetBwSession = 'C:\Users\luanc\agent-tools\bw-auto-unlock\Get-BwSession.ps1'
$script:RootBwItem = 'luan/hetzner-openbao-root'
$script:IdentityFile = Join-Path $env:USERPROFILE '.ssh\ed25519_hetzner_acer_2026'
$script:PythonExe = $null

function Write-HzErr([string]$Message) {
  [Console]::Error.WriteLine($Message)
}

function Test-HzPython64([string]$Exe) {
  # Real 64-bit python.exe only. A 32-bit python (e.g. pyenv-win 3.13.1-win32) runs under WOW64,
  # where C:\Windows\System32\OpenSSH\ssh.exe is invisible (WinError 2 -> run-capture rc=2).
  # .bat shims (pyenv) are rejected too: cmd.exe would re-parse the arguments.
  if (-not $Exe -or -not (Test-Path -LiteralPath $Exe)) { return $false }
  if ([IO.Path]::GetExtension($Exe) -ne '.exe') { return $false }
  if ($Exe -like '*\Microsoft\WindowsApps\*') { return $false }
  try {
    $bits = & $Exe -c 'import struct;print(struct.calcsize(chr(80))*8)' 2>$null
    return ([string]$bits).Trim() -eq '64'
  } catch { return $false }
}

function Get-HzPython {
  if ($script:PythonExe -and (Test-Path -LiteralPath $script:PythonExe)) { return $script:PythonExe }
  $cands = New-Object System.Collections.Generic.List[string]
  if ($env:HZ_PYTHON) { $cands.Add($env:HZ_PYTHON) }
  $cands.Add((Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'))
  foreach ($d in (Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs\Python') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
    $cands.Add((Join-Path $d.FullName 'python.exe'))
  }
  foreach ($n in @('python.exe', 'python3.exe')) {
    foreach ($c in @(Get-Command $n -All -CommandType Application -ErrorAction SilentlyContinue)) { $cands.Add($c.Source) }
  }
  foreach ($c in $cands) {
    if (Test-HzPython64 $c) { $script:PythonExe = $c; return $c }
  }
  throw 'no 64-bit python.exe found (32-bit python cannot see System32\OpenSSH\ssh.exe)'
}

function Get-HzSshExe {
  $windir = $env:WINDIR
  if (-not $windir) { $windir = 'C:\Windows' }
  foreach ($p in @(
      (Join-Path $windir 'Sysnative\OpenSSH\ssh.exe'),
      (Join-Path $windir 'System32\OpenSSH\ssh.exe')
    )) {
    if (Test-Path -LiteralPath $p) { return $p }
  }
  $cmd = Get-Command ssh.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw 'ssh.exe not found'
}

function New-HzSshConfig {
  if (-not (Test-Path -LiteralPath $script:IdentityFile)) {
    throw 'SSH identity file missing'
  }
  $cfg = Join-Path $env:TEMP ('ssh-hetzner-root-{0}.conf' -f [guid]::NewGuid().ToString('n'))
  $nl = [char]10
  $body = 'Host vps' + $nl + '    HostName 100.102.58.164' + $nl + '    User luan' + $nl + '    IdentityFile ' + $script:IdentityFile + $nl + '    IdentitiesOnly yes' + $nl + '    StrictHostKeyChecking accept-new' + $nl
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText($cfg, $body, $utf8NoBom)
  return $cfg
}

function Invoke-HzProcess {
  param(
    [Parameter(Mandatory = $true)][string]$FileName,
    [string[]]$ArgumentList,
    [byte[]]$StdinBytes,
    [int]$TimeoutSeconds = 60,
    [hashtable]$Environment
  )
  $py = Get-HzPython
  $runner = $script:RunCapture
  if (-not (Test-Path -LiteralPath $runner)) { throw 'run-capture.py not found' }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $py
  $quoted = New-Object System.Collections.Generic.List[string]
  $quoted.Add('"' + $runner + '"')
  $quoted.Add([string]$TimeoutSeconds)
  $quoted.Add('"' + $FileName + '"')
  if ($ArgumentList) {
    foreach ($a in $ArgumentList) {
      if ($null -eq $a) { continue }
      $s = [string]$a
      if ($s -match '[\s"]') {
        $quoted.Add('"' + $s.Replace('"', '\"') + '"')
      } else {
        $quoted.Add($s)
      }
    }
  }
  $psi.Arguments = [string]::Join(' ', $quoted)
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
  if ($Environment) {
    foreach ($k in $Environment.Keys) {
      $psi.EnvironmentVariables[$k] = [string]$Environment[$k]
    }
  }
  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  [void]$proc.Start()
  if ($StdinBytes -and $StdinBytes.Length -gt 0) {
    $proc.StandardInput.BaseStream.Write($StdinBytes, 0, $StdinBytes.Length)
    $proc.StandardInput.BaseStream.Flush()
  }
  $proc.StandardInput.Close()
  $outMs = New-Object System.IO.MemoryStream
  $outTask = $proc.StandardOutput.BaseStream.CopyToAsync($outMs)
  $errTask = $proc.StandardError.ReadToEndAsync()
  $wait = [Math]::Max(5, $TimeoutSeconds + 15)
  if (-not $proc.WaitForExit($wait * 1000)) {
    try { $proc.Kill() } catch { }
    throw ("process timed out after {0} seconds: {1}" -f $TimeoutSeconds, $FileName)
  }
  [void]$outTask.Wait()
  [void]$errTask.Wait()
  # Raw stdout bytes (no UTF-8 round trip), so binary payloads keep their hash.
  $outBytes = $outMs.ToArray()
  $outMs.Dispose()
  return [pscustomobject]@{
    ExitCode = $proc.ExitCode
    Stdout   = [Text.UTF8Encoding]::new($false).GetString($outBytes)
    Stderr   = $errTask.Result
    StdoutBytes = $outBytes
  }
}

function Invoke-HzSshRaw {
  param(
    [Parameter(Mandatory = $true)][string]$SshExe,
    [Parameter(Mandatory = $true)][string]$Config,
    [Parameter(Mandatory = $true)][string]$RemoteCommand,
    [byte[]]$StdinBytes,
    [int]$TimeoutSeconds = 180
  )
  if ($RemoteCommand -match '"') {
    throw 'remote command must not contain double quotes'
  }
  $argList = @(
    '-T', '-F', $Config,
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=20',
    'vps', $RemoteCommand
  )
  return Invoke-HzProcess -FileName $SshExe -ArgumentList $argList -StdinBytes $StdinBytes -TimeoutSeconds $TimeoutSeconds
}

function Protect-HzOutput {
  param(
    [string]$Text,
    [string]$Password
  )
  if ([string]::IsNullOrEmpty($Text)) { return $Text }
  $s = $Text
  if (-not [string]::IsNullOrEmpty($Password)) {
    $s = $s.Replace($Password, '[REDACTED]')
  }
  $s = [regex]::Replace($s, '(?im)^.*\bpassword\s*:\s*.*$', '[password-prompt]')
  $s = [regex]::Replace($s, '(?i)\bhvs\.[A-Za-z0-9\-_]+\b', '[REDACTED]')
  $s = [regex]::Replace($s, '(?i)\bs\.[A-Za-z0-9]{16,}\b', '[REDACTED]')
  $s = [regex]::Replace($s, '(?i)("(?:[^"]*(?:key|token|secret|password|unseal|recovery)[^"]*)"\s*:\s*)\[(?:[^\[\]]|(?<open>\[)|(?<-open>\]))*(?(open)(?!))\]', '${1}[REDACTED]')
  $s = [regex]::Replace($s, '(?i)("(?:[^"]*(?:key|token|secret|password|unseal|recovery)[^"]*)"\s*:\s*)"(?:\\.|[^"\\])*"', '${1}"[REDACTED]"')
  $s = [regex]::Replace($s, '(?s)-----BEGIN [^-]+-----.*?-----END [^-]+-----', '[REDACTED-PEM]')
  $s = [regex]::Replace($s, '(?i)\b[0-9a-f]{32,}\b', '[REDACTED]')
  $s = [regex]::Replace($s, '(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{40,}={0,2}(?![A-Za-z0-9+/])', '[REDACTED]')
  return $s
}

function Test-HzForbiddenSecretRead {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  if ($Text -match '(?i)bootstrap\.json') { return $true }
  if ($Text -match '(?i)(?:^|[\s''\"=])[^\s''\"]+\.(?:key|pem|p12|pfx)\b') { return $true }
  if ($Text -match '(?i)(?:^|[\s''\"=/\\])unseal[^ \r\n]*\.(?:json|txt|key|pem|b64|hex)\b') { return $true }
  if ($Text -match '(?i)(?:/|\\)unseal(?:[-_]keys?)?(?:/|\s|$)') { return $true }
  if ($Text -match '(?i)(?:/|\\)bootstrap(?:/|\\)') { return $true }
  return $false
}

function Get-HzBwSession {
  if (-not (Test-Path -LiteralPath $script:GetBwSession)) {
    throw 'Get-BwSession.ps1 not found'
  }
  $r = Invoke-HzProcess -FileName 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', $script:GetBwSession) -TimeoutSeconds 90
  if ($r.ExitCode -ne 0) {
    throw ("Get-BwSession failed (exit {0})" -f $r.ExitCode)
  }
  $sess = ([string]$r.Stdout).Trim()
  if ([string]::IsNullOrWhiteSpace($sess)) {
    throw 'Get-BwSession returned empty session'
  }
  return $sess
}

function Get-HzNativeExe([string]$Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw ($Name + ' not found')
}

function Get-HzRootPassword([string]$Session) {
  $bw = Get-HzNativeExe 'bw'
  $envMap = @{ BW_SESSION = $Session }
  [void](Invoke-HzProcess -FileName $bw -ArgumentList @('sync') -TimeoutSeconds 90 -Environment $envMap)
  $r = Invoke-HzProcess -FileName $bw -ArgumentList @('get','password', $script:RootBwItem) -TimeoutSeconds 60 -Environment $envMap
  if ($r.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($r.Stdout)) {
    throw 'could not read Bitwarden item'
  }
  return ([string]$r.Stdout).Trim()
}

function Clear-HzLocalFile([string]$Path) {
  if ($Path -and (Test-Path -LiteralPath $Path)) {
    try {
      [IO.File]::WriteAllBytes($Path, (New-Object byte[] 32))
      Remove-Item -LiteralPath $Path -Force
    } catch { }
  }
}

function Get-HzUploadRemoteCommand([string]$RemotePath) {
  return ('umask 077; python3 -c ''import sys;d=sys.stdin.buffer.read();bom=bytes([239,187,191]);d=d[3:] if d.startswith(bom) else d; open(sys.argv[1],chr(119)+chr(98)).write(d)'' {0}' -f $RemotePath)
}

# Runs a command (or local script) as root via su/PTY. Returns stdout/stderr/exit. Does not print payload.
function Invoke-HzRootCommand {
  param(
    [string]$Command,
    [string]$ScriptFile,
    [int]$TimeoutSeconds = 180,
    [switch]$AllowSecretPaths
  )

  if (-not (Test-Path -LiteralPath $script:HelperSource)) {
    throw 'su-pty-helper.py not found'
  }
  if ($ScriptFile) {
    if (-not (Test-Path -LiteralPath $ScriptFile)) { throw 'script file not found' }
    $body = [IO.File]::ReadAllText($ScriptFile).Replace("`r`n", "`n").Replace("`r", "`n")
  } else {
    if ([string]::IsNullOrWhiteSpace($Command)) { throw 'empty command' }
    $body = ("#!/bin/bash{0}set -u{0}{1}{0}" -f "`n", $Command.Replace("`r`n", "`n").Replace("`r", "`n"))
  }
  if (-not $AllowSecretPaths) {
    if (Test-HzForbiddenSecretRead $body) {
      throw 'refusing to read a known secret path; use Invoke-HetznerSecretToBitwarden.ps1'
    }
  }

  $sshExe = Get-HzSshExe
  $sshConfig = New-HzSshConfig
  $session = Get-HzBwSession
  $env:BW_SESSION = $session
  $password = Get-HzRootPassword -Session $session
  $session = $null
  if ($password.Length -lt 8) {
    $password = $null
    throw 'password from Bitwarden looks invalid'
  }

  $rand = [guid]::NewGuid().ToString('n').Substring(0, 12)
  $remoteHelper = "/tmp/hzroot-$rand.py"
  $remoteCmd = "/tmp/hzroot-$rand.sh"
  $localHelper = Join-Path $env:TEMP ("hzroot-{0}.py" -f $rand)
  $localCmd = Join-Path $env:TEMP ("hzroot-{0}.sh" -f $rand)
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  $exitCode = 2
  $stdout = ''
  $stderr = ''

  try {
    if ($body.IndexOf($password) -ge 0) {
      throw 'refusing to send a command/script that contains the root password'
    }
    $helperText = [IO.File]::ReadAllText($script:HelperSource).Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText($localHelper, $helperText, $utf8NoBom)
    [IO.File]::WriteAllText($localCmd, $body, $utf8NoBom)

    $up1 = Invoke-HzSshRaw -SshExe $sshExe -Config $sshConfig -RemoteCommand (Get-HzUploadRemoteCommand $remoteHelper) -StdinBytes ([IO.File]::ReadAllBytes($localHelper)) -TimeoutSeconds 30
    if ($up1.ExitCode -ne 0) { throw ("helper upload rc={0}" -f $up1.ExitCode) }
    $up2 = Invoke-HzSshRaw -SshExe $sshExe -Config $sshConfig -RemoteCommand (Get-HzUploadRemoteCommand $remoteCmd) -StdinBytes ([IO.File]::ReadAllBytes($localCmd)) -TimeoutSeconds 30
    if ($up2.ExitCode -ne 0) { throw ("script upload rc={0}" -f $up2.ExitCode) }
    $prep = Invoke-HzSshRaw -SshExe $sshExe -Config $sshConfig -RemoteCommand ("python3 -m py_compile {0} && chmod 700 {0} {1}" -f $remoteHelper, $remoteCmd) -TimeoutSeconds 20
    if ($prep.ExitCode -ne 0) { throw ("remote prep rc={0}" -f $prep.ExitCode) }

    $payload = [Text.Encoding]::UTF8.GetBytes($password + "`n")
    $runRemote = ("python3 {0} {1} {2}" -f $remoteHelper, $remoteCmd, $TimeoutSeconds)
    $run = Invoke-HzSshRaw -SshExe $sshExe -Config $sshConfig -RemoteCommand $runRemote -StdinBytes $payload -TimeoutSeconds ($TimeoutSeconds + 20)
    $payload = $null
    $stdout = $run.Stdout
    $stderr = $run.Stderr
    $exitCode = $run.ExitCode
  }
  finally {
    $password = $null
    Remove-Item Env:BW_PASSWORD -ErrorAction SilentlyContinue
    if ($sshExe -and $sshConfig -and $remoteHelper) {
      try {
        [void](Invoke-HzSshRaw -SshExe $sshExe -Config $sshConfig -RemoteCommand ("rm -f -- {0} {1}" -f $remoteHelper, $remoteCmd) -TimeoutSeconds 20)
      } catch { }
    }
    Clear-HzLocalFile $localHelper
    Clear-HzLocalFile $localCmd
    if ($sshConfig -and (Test-Path -LiteralPath $sshConfig)) {
      try { Remove-Item -LiteralPath $sshConfig -Force } catch { }
    }
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    Stdout   = $stdout
    Stderr   = $stderr
  }
}



function Get-HzDownloadRemoteCommand([string]$RemotePath) {

  return ('python3 -c ''import sys;sys.stdout.buffer.write(open(sys.argv[1],chr(114)+chr(98)).read())'' {0}' -f $RemotePath)

}



