#requires -Version 5.1
<#
.SYNOPSIS
  Roda um comando (ou um script local) como root no Hetzner, via SSH como luan e su com PTY.

.DESCRIPTION
  Le a senha root so em memoria, do Bitwarden item luan/hetzner-openbao-root.
  A senha nunca vai para disco, argv, log ou a tela.
  A saida e redigida por padrao (tokens hvs./s., unseal keys, JSON com key/token/secret/password, PEM, hex/base64 longos).
  Recusa comandos que leem caminhos secretos conhecidos (bootstrap.json, *.key, unseal).
  Para isso use Invoke-HetznerSecretToBitwarden.ps1.

  -MarkersOnly: modo deterministico seguro. Toda a saida (stdout+stderr) fica so em memoria; imprime APENAS
  as linhas que casam com -MarkerPattern (case-sensitive), cada uma cortada em 120 chars e redigida.
  O resto e descartado e so a contagem aparece. Neste modo a recusa de caminhos secretos e liberada,
  porque a saida nao tem como vazar.

  powershell -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-HetznerRoot.ps1 -Command 'id'
  powershell -File C:\Users\luanc\agent-tools\hetzner-root\Invoke-HetznerRoot.ps1 -MarkersOnly -Command 'sh /tmp/x.sh'
#>
[CmdletBinding(DefaultParameterSetName = 'Command')]
param(
  [Parameter(ParameterSetName = 'Command', Mandatory = $true)]
  [string]$Command,

  [Parameter(ParameterSetName = 'ScriptFile', Mandatory = $true)]
  [string]$ScriptFile,

  [int]$TimeoutSeconds = 180,

  [switch]$MarkersOnly,

  [string]$MarkerPattern = '^(STATUS_BEFORE|UNSEAL_OK|REKEY_INIT_OK|NEW_KEYS_FILE_OK|REKEY_COMPLETE|FAIL)\b',

  [ValidateRange(20, 400)]
  [int]$MarkerMaxLength = 120
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'HetznerRoot.Common.ps1')

$exitCode = 2
try {
  if ($MarkersOnly) {
    try { [void][regex]::new($MarkerPattern) } catch { throw 'invalid -MarkerPattern' }
  }
  $common = @{ TimeoutSeconds = $TimeoutSeconds }
  if ($MarkersOnly) { $common['AllowSecretPaths'] = $true }
  if ($PSCmdlet.ParameterSetName -eq 'ScriptFile') {
    $run = Invoke-HzRootCommand -ScriptFile $ScriptFile @common
  } else {
    $run = Invoke-HzRootCommand -Command $Command @common
  }

  if ($MarkersOnly) {
    $script:LastHzRootExit = $run.ExitCode
    $all = ([string]$run.Stdout) + "`n" + ([string]$run.Stderr)
    $run = $null
    $kept = 0
    $dropped = 0
    foreach ($line in ($all -split "\r?\n")) {
      $t = $line.TrimEnd("`r").Trim()
      if ($t.Length -eq 0) { continue }
      if ($t -cmatch $MarkerPattern) {
        if ($t.Length -gt $MarkerMaxLength) { $t = $t.Substring(0, $MarkerMaxLength) + '...' }
        $t = Protect-HzOutput -Text $t
        [Console]::Out.WriteLine($t)
        $kept++
      } else {
        $dropped++
      }
    }
    $all = $null
    [Console]::Out.WriteLine(('[markers-only] markers={0} dropped_lines={1}' -f $kept, $dropped))
    $exitCode = $script:LastHzRootExit
  } else {
    $stdout = Protect-HzOutput -Text $run.Stdout
    $stderr = Protect-HzOutput -Text $run.Stderr
    if ($stderr) { [Console]::Error.Write($stderr) }
    if ($stdout) {
      if (-not $stdout.EndsWith("`n")) { $stdout += "`n" }
      [Console]::Out.Write($stdout)
    }
    $exitCode = $run.ExitCode
  }
}
catch {
  Write-HzErr 'FAIL'
  $msg = Protect-HzOutput -Text ([string]$_.Exception.Message)
  if ($msg) { Write-HzErr $msg }
  $exitCode = 2
}

exit $exitCode