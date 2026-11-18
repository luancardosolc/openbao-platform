#requires -Version 5.1
<#
.SYNOPSIS
  Registra (idempotente) as tarefas agendadas do backup de estado para o usuario atual (logon interativo, sem senha guardada).
  - StateBackup Nightly     todo dia 02:00 BRT (WakeToRun, StartWhenAvailable, ate 6h, 2 novas tentativas a cada 30 min)
  - StateBackup Check       domingo 05:00 (restic check 5%; no 1o domingo do mes tambem o teste de restore)
  - StateBackup Freshness   a cada hora (alerta no Telegram do MeuBot se passar de 26h sem backup bom)
#>
[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'Invoke-StateBackup.ps1'
$ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$user = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
function Reg($name, $mode, $trigger, [TimeSpan]$limit, [switch]$Wake) {
  $act = New-ScheduledTaskAction -Execute $ps -Argument ("-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"{0}`" -Mode {1}" -f $script, $mode)
  $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit $limit -MultipleInstances IgnoreNew -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 30) -WakeToRun:$Wake
  Register-ScheduledTask -TaskName $name -TaskPath '\' -Action $act -Trigger $trigger -Settings $set -Principal $principal -Description "Backup de estado (openbao-platform/workstation/backup) - modo $mode" -Force | Out-Null
  $i = Get-ScheduledTask -TaskName $name | Get-ScheduledTaskInfo
  Write-Output ("TASK_OK {0} next={1}" -f $name, $i.NextRunTime)
}
Reg 'StateBackup Nightly' 'Backup' (New-ScheduledTaskTrigger -Daily -At '02:00') (New-TimeSpan -Hours 6) -Wake
Reg 'StateBackup Check' 'Check' (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '05:00') (New-TimeSpan -Hours 4) -Wake
$fr = New-ScheduledTaskTrigger -Once -At ((Get-Date).Date.AddHours((Get-Date).Hour + 1)) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
Reg 'StateBackup Freshness' 'Freshness' $fr (New-TimeSpan -Minutes 10)