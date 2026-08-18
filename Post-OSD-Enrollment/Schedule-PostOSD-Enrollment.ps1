<#!
.SYNOPSIS
    Registers a self-cleaning post-logon scheduled task that re-runs
    Post-OSD-Enrollment-Accelerator.ps1.

.DESCRIPTION
    Run as the LAST step of the SCCM OSD Task Sequence (as SYSTEM).

    This script:
      1. Copies the enrollment script to a stable location
         (C:\Windows\Temp\PostOSD\) so the task never depends on the
         ephemeral SCCM package cache.
      2. Registers scheduled task 'PostOSD-Enrollment':
           - Trigger   : first interactive logon (AutoLogon after OSD)
           - Repetition: every 5 minutes for 30 minutes
           - Action    : runs the enrollment script; if it exits 3010
                         (IPv6 changed), triggers a one-time reboot
                         after 60 seconds.
      3. Registers scheduled task 'PostOSD-Cleanup':
           - Runs once, 35 minutes after registration (works even if the
             machine never logs in), then deletes BOTH tasks, the copied
             script, and this scheduler file.

    The post-logon task retries every 5 minutes for 30 minutes, which
    covers the AAD Connect sync gap and SCCM client warm-up. Place this
    step LAST in the task sequence.

.PARAMETER MainScriptPath
    Full path to Post-OSD-Enrollment-Accelerator.ps1.
    Default: same folder as this script.

.PARAMETER TaskName
    Scheduled task name for the post-logon enrollment run.
    Default: PostOSD-Enrollment

.PARAMETER CleanupTaskName
    Scheduled task name for the self-cleanup run.
    Default: PostOSD-Cleanup

.PARAMETER WorkDir
    Stable local folder used for the script copy and marker files.
    Default: C:\Windows\Temp\PostOSD

.PARAMETER RepeatIntervalMinutes
    Minutes between repetitions. Default: 5

.PARAMETER RepeatDurationMinutes
    Total repetition window. Default: 30

.PARAMETER CleanupDelayMinutes
    Minutes after registration before the cleanup task runs. Default: 35

.PARAMETER RebootDelaySeconds
    Seconds before shutdown /r after a 3010 exit. Default: 60

.PARAMETER LogPath
    Directory for log output. Default: C:\IntuneLogs
    (overridden by _SMSTSLogPath when running inside a Task Sequence)

.EXIT CODES
    0 : Always. This script never fails the task sequence step.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Schedule-PostOSD-Enrollment.ps1

.OUTPUT LOGS
    - %LogPath%\PostOSDScheduler.log : Tab-separated registration log

.NOTES
    Author       : Mohammad Abdelkader
    Website      : momar.tech
    Version      : 1.0
    Last Updated : 2026-07-31
#>

param(
    [string]$MainScriptPath     = (Join-Path $PSScriptRoot 'Post-OSD-Enrollment-Accelerator.ps1'),
    [string]$TaskName           = 'PostOSD-Enrollment',
    [string]$CleanupTaskName    = 'PostOSD-Cleanup',
    [string]$WorkDir            = 'C:\Windows\Temp\PostOSD',
    [int]$RepeatIntervalMinutes = 5,
    [int]$RepeatDurationMinutes = 30,
    [int]$CleanupDelayMinutes   = 35,
    [int]$RebootDelaySeconds    = 60,
    [string]$LogPath            = 'C:\IntuneLogs'
)

$ErrorActionPreference = 'Continue'
$ExitCode              = 0

# ─── Task Sequence integration (optional, only inside a TS) ────────────────
$tsenv = $null
try { $tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment } catch { }
if ($tsenv) {
    try {
        $tsLog = $tsenv.Value('_SMSTSLogPath')
        if ($tsLog) { $LogPath = $tsLog }
        $tsenv.Value('PostOSDScheduled') = '1'
    } catch { }
}

# ─── Logging setup ─────────────────────────────────────────────────────────
$LogFile = Join-Path $LogPath 'PostOSDScheduler.log'
if (-not (Test-Path -LiteralPath $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }

function Write-TSLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t$Level`t$Message"
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

Write-TSLog "=== Start | Machine: $env:COMPUTERNAME ==="

# ─── Idempotency: skip if already scheduled ────────────────────────────────
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-TSLog "Task '$TaskName' already registered - skipping (idempotent)."
    Write-TSLog '=== Complete ==='
    exit 0
}

if (-not (Test-Path -LiteralPath $MainScriptPath)) {
    Write-TSLog "Main script not found: $MainScriptPath" -Level 'ERROR'
    Write-TSLog '=== Complete ==='
    exit 0
}

try {
    # ─── Stable copy of the enrollment script ─────────────────────────────
    if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
    $StableMain = Join-Path $WorkDir 'Post-OSD-Enrollment-Accelerator.ps1'
    Copy-Item -LiteralPath $MainScriptPath -Destination $StableMain -Force
    Write-TSLog "Enrollment script copied to $StableMain"

    # ─── Principal: SYSTEM, highest privileges ────────────────────────────
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    # ─── Trigger: post-logon + repetition (every 5 min for 30 min) ────────
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $rep     = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $RepeatIntervalMinutes) -RepetitionDuration (New-TimeSpan -Minutes $RepeatDurationMinutes)
    $trigger.Repetition = $rep.Repetition
    if (-not $trigger.Repetition) {
        Write-TSLog 'Could not attach repetition to the AtLogOn trigger.' -Level 'WARN'
    }

    # ─── Action: run the enrollment script, reboot once on 3010 ───────────
    $doneFlag = Join-Path $WorkDir 'RebootDone.flag'
    $wrapper  = "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$StableMain'; if (`$LASTEXITCODE -eq 3010 -and -not (Test-Path '$doneFlag')) { Set-Content -LiteralPath '$doneFlag' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Force; shutdown.exe /r /t $RebootDelaySeconds /c 'PostOSD IPv6 change - rebooting' /d p:0:0 }"
    $action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$wrapper`""

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-TSLog "Task '$TaskName' registered (AtLogOn, repeat every $RepeatIntervalMinutes min for $RepeatDurationMinutes min)."

    # ─── Cleanup task: one-shot after CleanupDelayMinutes ─────────────────
    $cleanupCmd = "Start-Sleep -Seconds 5; Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName '$CleanupTaskName' -Confirm:`$false -ErrorAction SilentlyContinue; Remove-Item -LiteralPath '$StableMain','$PSCommandPath','$doneFlag' -Force -ErrorAction SilentlyContinue"
    $cleanupAction   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$cleanupCmd`""
    $cleanupTrigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($CleanupDelayMinutes)
    $cleanupSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $CleanupTaskName -Action $cleanupAction -Trigger $cleanupTrigger -Principal $principal -Settings $cleanupSettings -Force | Out-Null
    Write-TSLog "Cleanup task '$CleanupTaskName' registered (runs +$CleanupDelayMinutes min)."

    # ─── Verification ─────────────────────────────────────────────────────
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Write-TSLog 'Verification: post-logon task present.'
    } else {
        Write-TSLog 'Verification FAILED: post-logon task not found.' -Level 'ERROR'
    }
} catch {
    Write-TSLog "Scheduling failed: $($_.Exception.Message)" -Level 'ERROR'
}

Write-TSLog '=== Complete ==='
exit $ExitCode
