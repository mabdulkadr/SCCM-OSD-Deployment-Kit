<#!
.SYNOPSIS
    Post-OSD maintenance tasks for SCCM Task Sequence (silent, SYSTEM-safe).

.DESCRIPTION
    Designed to run at the end of an SCCM OSD Task Sequence under the SYSTEM
    account.  Performs silently with file-based logging.  No user interaction.

    ─── Execution Order (by dependency) ───────────────────────────────
    1. Time Service     ← Kerberos & certificate auth depend on accurate time
    2. IPv6             ← Independent, fast, triggers reboot flag
    3. SCCM Actions     ← Fire-and-forget policy triggers (retry via post-logon task)
    4. Entra ID Join    ← Prerequisite for Intune MDM enrollment
    5. Intune MDM       ← Requires Entra ID join + CloudDomainJoin tenant info
    6. Co-Management    ← Final check; depends on SCCM policy + MDM enrollment

    ─── Scheduling (handled by Schedule-PostOSD-Enrollment.ps1) ─────
    - This script creates NO scheduled tasks.
    - Run Schedule-PostOSD-Enrollment.ps1 as the LAST step of the task
      sequence. It registers a post-logon task that re-runs THIS script
      every 5 minutes for 30 minutes, then self-deletes the task, itself,
      and the script copies.

.PARAMETER LogPath
    Directory for log output.
    Default: C:\IntuneLogs

.PARAMETER TimeZone
    Target time zone ID (use tzutil /l to list available IDs).
    Default: 'Arab Standard Time'

.EXIT CODES
    0    : All steps completed; no reboot needed
    3010 : Reboot required (IPv6 was changed; the post-logon scheduled
           task triggers a one-time reboot)

.REQUIREMENTS
    - Windows 10/11 (PowerShell 5.1)
    - SYSTEM account (SCCM TS context)
    - SCCM client installed (for sections 3, 6)
    - Active Directory domain membership (for sections 4, 5)
    - Network connectivity to Domain Controllers

.LIMITATIONS
    - WMI accelerator [wmiclass] not available in PowerShell 7+
    - IPv6 disable may break DirectAccess & Always On VPN
    - Co-management requires server-side SCCM console configuration
    - dsregcmd /join success depends on AAD Connect sync cycle

.OUTPUT LOGS
    - %LogPath%\PostOSDEnrollmentAccelerator.log   : Tab-separated action log
    - %LogPath%\PostOSDScheduler.log               : Scheduler registration log (from Schedule-PostOSD-Enrollment.ps1)

.RUN CONTEXT
    SCCM Task Sequence (runs as LOCAL SYSTEM, no elevation needed).

.EXAMPLE
    # Default (Arab Standard Time, C:\IntuneLogs)
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Post-OSD-Enrollment-Accelerator.ps1

.EXAMPLE
    # Custom time zone and log path
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File Post-OSD-Enrollment-Accelerator.ps1 -LogPath D:\Logs -TimeZone 'Pacific Standard Time'

.NOTES
    Author       : Mohammad Abdelkader
    Website      : momar.tech
    Version      : 1.0
    Last Updated : 2026-07-31
    Changes v2.0 :
      - Removed ALL in-script scheduled task creation (SCCMActionsRetry,
        AzureADJoinRetry, TriggerEnrollment).
      - Retries now delegated to Schedule-PostOSD-Enrollment.ps1, which
        registers a post-logon task (every 5 min for 30 min, self-cleaning).
      - Removed the 120-second in-script Entra join polling loop.
      - IPv6 reboot flag is now set only when the registry value actually
        changes (prevents repeated 3010 exits).
    Changes v1.5 :
      - Added SCCMActionsRetry delayed scheduled task (SCCM client warm-up)
      - IPv6: added adapter-level disable via Disable-NetAdapterBinding
      - Time: added PCs-only safety check, time-source verification
      - Co-mgmt: added 3-tier WMI/Registry/MDM detection
      - All scheduled tasks now use RepetitionDuration limit
      - Replaced deprecated wuauclt.exe with usoclient.exe
      - Improved inter-section dependency ordering
#>

param(
    [string]$LogPath   = 'C:\IntuneLogs',
    [string]$TimeZone  = 'Arab Standard Time'
)

# ─── Version & log path ────────────────────────────────────────────────────
$ScriptVersion = '2.0'
$LogFile       = "$LogPath\PostOSDEnrollmentAccelerator.log"
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

# ─── Global settings ───────────────────────────────────────────────────────
$ErrorActionPreference = 'Continue'    # Log errors but never halt the TS
$RebootRequired        = $false        # Track whether IPv6 changes need a reboot

# ─── Logging function ──────────────────────────────────────────────────────
# Writes a tab-separated timestamped line to %LogPath%\PostOSDEnrollmentAccelerator.log
# Levels: INFO (default), WARN, ERROR
function Write-TSLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t$Level`t$Message"
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

Write-TSLog "=== Start (v$ScriptVersion) | Machine: $env:COMPUTERNAME ==="

# ═══════════════════════════════════════════════════════════════════════════
# 1. TIME SERVICE & TIME ZONE
#    Purpose : Accurate time is required for Kerberos, certificate validation,
#              and Entra ID authentication.  This must run FIRST.
#    Scope   : Workstations only (skips Domain Controllers and servers).
# ═══════════════════════════════════════════════════════════════════════════
Write-TSLog 'Repairing time service...'
try {
    $cs       = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $role     = [int]$cs.DomainRole
    $isDC     = ($role -ge 4)                    # 4=Backup DC, 5=Primary DC
    $isServer = ($role -eq 2 -or $role -eq 3)    # Standalone or Member Server
} catch { $isDC = $false; $isServer = $false }

if ($isDC) {
    Write-TSLog 'Domain Controller detected - skipped time repair.' -Level 'WARN'
} elseif ($isServer) {
    Write-TSLog 'Server detected - skipping time repair (PCs-only mode).' -Level 'WARN'
} else {
    # ── Start and configure w32time service ──────────────────────────────
    Set-Service w32time -StartupType Automatic -ErrorAction SilentlyContinue
    try { Start-Service w32time -ErrorAction SilentlyContinue } catch { }

    # Enforce NT5DS domain hierarchy (sync from PDC)
    $null = & w32tm /config /syncfromflags:domhier /reliable:no /update 2>&1
    Restart-Service w32time -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $null = & w32tm /resync /force 2>&1

    # ── Log current time source for diagnostics ─────────────────────────
    $timeSrc = & w32tm /query /source 2>&1 | Out-String
    Write-TSLog "Current time source: $($timeSrc.Trim())"

    # ── Enable automatic time-zone detection (tzautoupdate) ─────────────
    $tzKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate'
    if (-not (Test-Path $tzKey)) { New-Item -Path $tzKey -Force | Out-Null }
    $curTzAuto = (Get-ItemProperty -Path $tzKey -Name 'Start' -ErrorAction SilentlyContinue).Start
    if ($curTzAuto -ne 3) {
        Set-ItemProperty -Path $tzKey -Name 'Start' -Value 3
        Write-TSLog 'tzautoupdate configured (Start=3).'
    } else { Write-TSLog 'tzautoupdate already configured (Start=3).' }

    # ── Start location service if present (required for auto time zone on client OS) ──
    $locSvc = Get-Service -Name lfsvc -ErrorAction SilentlyContinue
    if ($locSvc) {
        try { Start-Service lfsvc -ErrorAction SilentlyContinue } catch {
            Write-TSLog "Location Service present but could not start: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # ── Set the desired time zone (with tzutil.exe fallback) ────────────
    try {
        if ((Get-TimeZone).Id -ne $TimeZone) { Set-TimeZone -Id $TimeZone }
    } catch {
        Write-TSLog "Get/Set-TimeZone failed, trying tzutil fallback: $($_.Exception.Message)" -Level 'WARN'
        try { & tzutil.exe /s $TimeZone } catch { Write-TSLog "Failed to set timezone: $($_.Exception.Message)" -Level 'ERROR' }
    }
    Write-TSLog 'Time service configured.'
}


# ═══════════════════════════════════════════════════════════════════════════
# 2. DISABLE IPv6
#    Purpose : Disable IPv6 at the adapter level and system-wide via registry.
#              This is the primary source of $RebootRequired = 3010.
# ═══════════════════════════════════════════════════════════════════════════
Write-TSLog 'Disabling IPv6...'

# ── Step A: Disable IPv6 binding on every active physical adapter ──────────
$adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
if ($adapters) {
    foreach ($a in $adapters) {
        try {
            Disable-NetAdapterBinding -Name $a.Name -ComponentID 'ms_tcpip6' -ErrorAction Stop
            Write-TSLog "  Disabled IPv6 on adapter: $($a.Name)"
        } catch { Write-TSLog "  Warning: Failed to disable IPv6 on $($a.Name)" -Level 'WARN' }
    }
} else { Write-TSLog '  No active physical adapters found - skipped adapter binding.' -Level 'WARN' }

# ── Step B: Set DisabledComponents = 0xFF (all IPv6 components off) ────────
$ipv6Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
try {
    $prevIPv6 = (Get-ItemProperty -LiteralPath $ipv6Path -Name 'DisabledComponents' -ErrorAction SilentlyContinue).DisabledComponents
    if (-not (Test-Path -LiteralPath $ipv6Path)) {
        New-Item -Path $ipv6Path -Force | Out-Null
    }
    Set-ItemProperty -Path $ipv6Path -Name 'DisabledComponents' -Value 0xFF -Type DWord -Force
    if ($prevIPv6 -ne 0xFF) { $RebootRequired = $true }
    Write-TSLog 'IPv6 disabled on adapters and via registry (requires reboot).'
    Write-TSLog 'Note: Disabling IPv6 may break DirectAccess, Always On VPN, and some modern Windows features.' -Level 'WARN'
} catch {
    Write-TSLog "Failed to disable IPv6 via registry: $($_.Exception.Message)" -Level 'ERROR'
}


# ═══════════════════════════════════════════════════════════════════════════
# 3. SCCM CLIENT ACTIONS
#    Purpose : Kick off all standard SCCM action cycles so that policy,
#              apps, and updates begin processing without waiting for the
#              default 60-minute policy polling interval.
#    Note    : A scheduled task (SCCMActionsRetry) runs once after 5 minutes
#              because the SCCM client may not be fully initialized yet.
# ═══════════════════════════════════════════════════════════════════════════
Write-TSLog 'Triggering SCCM client actions...'

# ── SCCM action GUIDs (standard, documented by Microsoft) ─────────────────
$SccmActions = @(
    @{ ID = '{00000000-0000-0000-0000-000000000121}'; Name = 'App Deployment Eval' }
    @{ ID = '{00000000-0000-0000-0000-000000000021}'; Name = 'Machine Policy Eval' }
    @{ ID = '{00000000-0000-0000-0000-000000000113}'; Name = 'Software Updates Scan' }
    @{ ID = '{00000000-0000-0000-0000-000000000108}'; Name = 'SU Deployment Eval' }
    @{ ID = '{00000000-0000-0000-0000-000000000101}'; Name = 'Hardware Inventory' }
    @{ ID = '{00000000-0000-0000-0000-000000000102}'; Name = 'Software Inventory' }
    @{ ID = '{00000000-0000-0000-0000-000000000131}'; Name = 'Compliance Eval' }
    @{ ID = '{00000000-0000-0000-0000-000000000003}'; Name = 'Discovery Data' }
)

foreach ($a in $SccmActions) {
    try {
        # Uses [wmiclass] accelerator (Windows PowerShell 5.1 only, not PS 7+)
        [void]([wmiclass]'ROOT\ccm:SMS_Client').TriggerSchedule($a.ID)
        Write-TSLog "  Triggered: $($a.Name)"
    } catch { Write-TSLog "  SKIPPED: $($a.Name) - $($_.Exception.Message.Trim())" -Level 'WARN' }
}

# ── Refresh update compliance + kick off Windows Update scan ──────────────
try { (New-Object -ComObject Microsoft.CCM.UpdatesStore).RefreshServerComplianceState() } catch { }
try { Start-Process usoclient.exe -ArgumentList 'RefreshSettings' -NoNewWindow -Wait } catch { }
try { Start-Process usoclient.exe -ArgumentList 'StartScan' -NoNewWindow } catch { }
Write-TSLog 'SCCM actions complete.'
Write-TSLog 'Note: SCCM action retries are handled by the post-logon scheduled task (Schedule-PostOSD-Enrollment.ps1).'


# ═══════════════════════════════════════════════════════════════════════════
# 4. ENTRA ID (HYBRID AZURE AD) JOIN
#    Purpose : Ensure the device is Entra ID joined BEFORE attempting MDM
#              enrollment.  Hybrid join requires the on-prem AD computer
#              object to be synced to AAD by AAD Connect first.
#    Fallback: A scheduled task retries dsregcmd /join every 10 min for 2
#              hours, covering the AAD Connect sync gap window.
# ═══════════════════════════════════════════════════════════════════════════
Write-TSLog 'Checking Entra ID (Azure AD) join status...'
try {
    $dsregOutput    = & dsregcmd.exe /status 2>&1 | Out-String
    $isAadJoined    = $dsregOutput -match 'AzureAdJoined\s*:\s*YES'
    $isDomainJoined = $dsregOutput -match 'DomainJoined\s*:\s*YES'

    if ($isAadJoined) {
        Write-TSLog 'Device is already Entra ID joined.'
    }
    elseif ($isDomainJoined) {
        Write-TSLog 'Device is domain-joined but NOT Entra joined. Triggering Hybrid Join...'
        $joinResult = & dsregcmd.exe /join /debug 2>&1 | Out-String
        Write-TSLog "Hybrid join triggered: $($joinResult.Trim() -replace '\s+', ' ')"
        Write-TSLog 'Join retries are handled by the post-logon scheduled task (covers the AAD Connect sync gap).'
    }
    else {
        Write-TSLog 'Device is not domain-joined. Hybrid join not applicable here.' -Level 'WARN'
    }
} catch { Write-TSLog "Entra ID join check failed: $($_.Exception.Message)" -Level 'WARN' }


# ═══════════════════════════════════════════════════════════════════════════
# 5. MDM / INTUNE ENROLLMENT
#    Purpose : Configure MDM enrollment URLs, enable auto-enrollment policy,
#              trigger the deviceenroller, and schedule retries.
#    Depends : Entra ID join must be complete (section 4).
#              CloudDomainJoin\TenantInfo must exist in registry.
# ═══════════════════════════════════════════════════════════════════════════
Write-TSLog 'Configuring MDM enrollment...'
try {
    # ── Discover tenant ID from CloudDomainJoin registry ─────────────────
    $key     = 'SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\*'
    $info    = Get-Item "HKLM:\$key" -ErrorAction Stop
    $tid     = $info.Name.Split('\')[-1]
    $mdmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\$tid"

    # ── Set MDM enrollment, ToU, and compliance discovery URLs ───────────
    @(
        @{ N = 'MdmEnrollmentUrl';  V = 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc' }
        @{ N = 'MdmTermsOfUseUrl';  V = 'https://portal.manage.microsoft.com/TermsofUse.aspx' }
        @{ N = 'MdmComplianceUrl';  V = 'https://portal.manage.microsoft.com/?portalAction=Compliance' }
    ) | ForEach-Object {
        New-ItemProperty -LiteralPath $mdmPath -Name $_.N -Value $_.V -PropertyType String -Force -ErrorAction SilentlyContinue
    }
    Write-TSLog 'MDM enrollment URLs set.'

    # ── Enable MDM auto-enrollment via registry policy ───────────────────
    $mdmPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'
    if (-not (Test-Path $mdmPolicyPath)) { New-Item -Path $mdmPolicyPath -Force | Out-Null }
    Set-ItemProperty -Path $mdmPolicyPath -Name 'AutoEnrollMDM' -Value 1 -Type DWord -Force
    Write-TSLog 'MDM auto-enrollment policy enabled.'

    # ── Trigger enrollment immediately ───────────────────────────────────
    Start-Process 'C:\Windows\system32\deviceenroller.exe' -ArgumentList '/c /AutoEnrollMDM' -Wait -NoNewWindow
    Write-TSLog 'Auto-enrollment triggered.'

    # ── Note: retries are handled by the post-logon scheduled task ────────
    Write-TSLog 'Auto-enrollment retries are handled by the post-logon scheduled task.'
} catch { Write-TSLog 'MDM enrollment setup skipped (no tenant info).' -Level 'WARN' }


# ═══════════════════════════════════════════════════════════════════════════
# 6. CO-MANAGEMENT (SCCM + INTUNE)
#    Purpose : Verify whether co-management is active using three detection
#              tiers (WMI → Registry → MDM policy).  If not active, force a
#              machine policy refresh and re-check after 30 seconds.
#    Note    : Co-management requires server-side configuration in the SCCM
#              console (workload slider + tenant association).
# ═══════════════════════════════════════════════════════════════════════════
Write-TSLog 'Checking SCCM / Intune co-management status...'

$coMgmtReady  = $false
$coMgmtStatus = 'Not Detected'

# ── Tier 1: WMI CoManagementHandler (most reliable) ──────────────────────
try {
    $cm = Get-WmiObject -Namespace 'root\ccm\CoManagementHandler' -Class 'CoManagement_Configuration' -ErrorAction Stop
    if ($cm -and $cm.Enable) {
        $coMgmtReady  = $true
        $coMgmtStatus = 'Co-Management Enabled (WMI)'
        Write-TSLog 'Co-management active - confirmed via WMI CoManagementHandler.'
    }
    elseif ($cm) {
        $coMgmtStatus = 'SCCM Present - Co-Management Disabled in WMI'
        Write-TSLog 'SCCM client present but co-management not enabled in WMI.'
    }
} catch { Write-TSLog '  CoManagementHandler WMI class not available (SCCM client may not be ready).' -Level 'WARN' }

# ── Tier 2: Registry CoMgmtSettings (fallback) ───────────────────────────
if (-not $coMgmtReady) {
    $coMgmtKey = 'HKLM:\SOFTWARE\Microsoft\CCM\CoMgmtSettings'
    try {
        if (Test-Path $coMgmtKey) {
            $prodType = (Get-ItemProperty -Path $coMgmtKey -Name 'ProductionType' -ErrorAction SilentlyContinue).ProductionType
            if ($prodType) {
                $coMgmtReady  = $true
                $coMgmtStatus = 'Co-Management Active (Registry)'
                Write-TSLog "Co-management active (Registry, ProductionType: $prodType)."
            }
        }
    } catch { }

    # ── Tier 3: MDM auto-enrollment policy (indirect indicator only) ─────
    if (-not $coMgmtReady) {
        $mdmReg = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM'
        try {
            if (Test-Path $mdmReg) {
                $v = Get-ItemProperty -Path $mdmReg -Name 'AutoEnrollMDM' -ErrorAction SilentlyContinue
                if ($v -and $v.AutoEnrollMDM -eq 1) {
                    $coMgmtStatus = 'MDM AutoEnroll Configured (Co-management may be pending)'
                    Write-TSLog 'MDM auto-enrollment policy detected but co-management not yet confirmed.'
                }
            }
        } catch { }
    }
}

# ── If not ready, trigger machine policy retrieval and re-check ──────────
if (-not $coMgmtReady) {
    Write-TSLog "Co-management status: $coMgmtStatus. Re-triggering machine policy retrieval..."
    try {
        [void]([wmiclass]'ROOT\ccm:SMS_Client').TriggerSchedule('{00000000-0000-0000-0000-000000000021}')
        Write-TSLog '  Machine policy retrieval triggered for co-management.'
    } catch { Write-TSLog '  Could not trigger policy retrieval (SCCM client may not be ready).' -Level 'WARN' }

    Start-Sleep -Seconds 30

    # Re-check via WMI after policy refresh
    try {
        $cm = Get-WmiObject -Namespace 'root\ccm\CoManagementHandler' -Class 'CoManagement_Configuration' -ErrorAction Stop
        if ($cm -and $cm.Enable) {
            Write-TSLog 'Co-management now active after policy refresh.'
        } else {
            Write-TSLog 'Co-management still not active - verify SCCM console co-management configuration.' -Level 'WARN'
        }
    } catch { Write-TSLog '  CoManagementHandler still unavailable after policy refresh.' -Level 'WARN' }
} else {
    Write-TSLog "Co-management status: $coMgmtStatus."
}


# ═══════════════════════════════════════════════════════════════════════════
# CLEANUP & EXIT
# ═══════════════════════════════════════════════════════════════════════════
Write-TSLog '=== Complete ==='

if ($RebootRequired) {
    Write-TSLog 'Reboot required - exiting with code 3010.'
    exit 3010
}
exit 0
