<#
.SYNOPSIS
    Get-OSDDeploymentReport.ps1 — OSD deployment status report with HTML email output.

.CONFIGURATION
    Before using this script, replace the following placeholders with your actual values:

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ PLACEHOLDER              │ LOCATION        │ DESCRIPTION                    │
    ├──────────────────────────┼─────────────────┼────────────────────────────────┤
    │ <YOUR_SERVICE_EMAIL>     │ $UserFrom       │ Sender mailbox (Graph API)     │
    │ <YOUR_EMAIL>             │ $UserTo         │ Report recipient email(s)      │
    │ <YOUR_TENANT_ID>         │ $TenantId       │ Azure AD tenant ID (GUID)      │
    │ <YOUR_CLIENT_ID>         │ $ClientId       │ Azure AD app client ID (GUID)  │
    │ <YOUR_CLIENT_SECRET>     │ $ClientSecretDef│ Azure AD app client secret     │
    │ <ADMIN_EMAIL>            │ .EXAMPLE        │ Example: admin email           │
    │ <HELPDESK_EMAIL>         │ .EXAMPLE        │ Example: helpdesk email        │
    │ SCCM.Momar.local         │ $SccmServer     │ Your SCCM site server FQDN     │
    │ MT1                      │ $SiteCode       │ Your SCCM 3-char site code     │
    └──────────────────────────────────────────────────────────────────────────────┘

.DESCRIPTION
    Queries SCCM for Operating System Deployment (OSD) status from two sources:
    1. SMS_DeploymentSummary — deployment-level compliance statistics (Targeted, Success, Error, Not Met)
    2. SMS_TaskSequenceExecutionStatus — per-step device execution records

    Builds an Outlook-safe HTML executive report with summary cards for both views,
    per-device detail tables, per-task-sequence breakdowns, and deployment compliance metrics.

    Email delivery is handled via Microsoft Graph API using the Exchange-Email-Sender
    Azure AD app registration (OAuth 2.0 client credentials flow), eliminating the need
    for legacy SMTP authentication.

.PARAMETER SccmServer
    SCCM site server hostname. Default: SCCM-PS.Momar.local

.PARAMETER SiteCode
    Three-character SCCM site code. Default: MT1

.PARAMETER SendEmail
    Switch to send the HTML report via email. Default: $true

.PARAMETER Subject
    Email subject line. Default: "SCCM OSD Deployment Status"

.PARAMETER UserFrom
    Sender mailbox address (must be a mailbox the app has Mail.Send permission for).
    Default: <YOUR_SERVICE_EMAIL>

.PARAMETER UserTo
    Recipient email address(es). Default: <YOUR_EMAIL>

.PARAMETER TenantId
    Azure AD tenant ID for the Exchange-Email-Sender app registration.

.PARAMETER ClientId
    Azure AD application (client) ID.

.PARAMETER ClientSecret
    Azure AD client secret as SecureString. Priority: parameter > env var > default.

.PARAMETER ClientSecretDefault
    Fallback client secret value (plaintext) used when no other secret source is provided.

.EXAMPLE
    .\Get-OSDDeploymentReport.ps1

    Runs with all defaults: site MT1, generates HTML and sends via Graph API.

.EXAMPLE
    .\Get-OSDDeploymentReport.ps1 -SendEmail:$false

    Saves HTML to disk but skips email.

.EXAMPLE
    .\Get-OSDDeploymentReport.ps1 -UserTo "<ADMIN_EMAIL>", "<HELPDESK_EMAIL>"

    Sends the report to multiple recipients.

.NOTES
    Requirements:
      - SCCM Admin Console or RSAT installed (WMI provider)
      - Run from a machine with SCCM WMI provider access
      - User must have read access to SMS site WMI namespace
      - Exchange-Email-Sender app must have Mail.Send application permission
      - Admin consent granted in Azure AD for the app to send as the mailbox identity

    Data sources:
      - SMS_TaskSequenceExecutionStatus — per-step execution records (split into runs via fresh-start detection)
      - SMS_R_System — computer name, MAC, OS, last user
      - SMS_TaskSequencePackage — task sequence names
      - SMS_Advertisement — deployment/advertisement details
      - SMS_Collection — collection names
      - SMS_DeploymentSummary (FeatureType=7) — deployment compliance stats

    Secret resolution order:
      1. -ClientSecret parameter (SecureString)
      2. $env:OSD_REPORT_CLIENT_SECRET environment variable
      3. -ClientSecretDefault parameter (built-in fallback)

    Version: 2.0 — Migrated from SMTP to Microsoft Graph API email delivery.
#>

[CmdletBinding()]
param(
    [string]$SccmServer   = 'SCCM.Momar.local',          # SCCM site server FQDN
    [string]$SiteCode     = 'MT1',                         # 3-char SCCM site code
    [switch]$SendEmail    = $true,                         # Send report via email
    [string]$Subject      = 'SCCM OSD Deployment Status',  # Email subject line
    [string]$UserFrom     = '<YOUR_SERVICE_EMAIL>',        # Sender mailbox (Graph API)
    [string[]]$UserTo     = @("<YOUR_EMAIL>"),             # Recipient email(s)
    [string]$TenantId     = '<YOUR_TENANT_ID>',            # Azure AD tenant GUID
    [string]$ClientId     = '<YOUR_CLIENT_ID>',            # Azure AD app client GUID
    [securestring]$ClientSecret,                           # Azure AD secret (SecureString)
    [string]$ClientSecretDefault = '<YOUR_CLIENT_SECRET>'  # Fallback secret (plaintext)
)

#region Auth — Microsoft Graph API Token & Email

# Connect to Azure AD and acquire an OAuth 2.0 access token for Microsoft Graph
# using client credentials flow (app-only authentication).
function Get-GraphAccessToken {
    param([string]$Tenant, [string]$Client, [securestring]$Secret)
    $secPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
    ) -replace '\0', ''
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $Client
        client_secret = $secPlain
        scope         = 'https://graph.microsoft.com/.default'
    }
    try {
        $resp = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        return $resp.access_token
    } catch {
        Write-Error "Failed to acquire Graph access token: $($_.Exception.Message)"
        return $null
    }
}

# Send an HTML email via Microsoft Graph API /sendMail endpoint.
# The app must have Mail.Send application permission on the sender mailbox.
function Send-GraphMailMessage {
    param(
        [string]$AccessToken,
        [string]$From,
        [string[]]$To,
        [string]$Subject,
        [string]$HtmlBody
    )
    $toRecipients = @($To | ForEach-Object { @{ emailAddress = @{ address = $_ } } })
    $payload = @{
        message = @{
            subject      = $Subject
            body         = @{ contentType = 'HTML'; content = $HtmlBody }
            toRecipients = $toRecipients
            from         = @{ emailAddress = @{ address = $From } }
        }
        saveToSentItems = $false
    } | ConvertTo-Json -Depth 5 -Compress
    $headers = @{
        Authorization = "Bearer $AccessToken"
        'Content-Type'  = 'application/json'
    }
    Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/v1.0/users/$From/sendMail" -Headers $headers -Body $payload -ErrorAction Stop
}

#endregion Auth

#region Initialization — Parameters, Logging & WMI Connection

$LogPath    = ''
$ReportPath = 'C:\Reports'

# Write timestamped log messages to console (color-coded) and optionally to a log file.
# Levels: HEADER (Cyan), OK (Green), WARN (Yellow), ERROR (Red), INFO (default)
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    $fg = switch ($Level) {
        'OK'     { 'Green' }
        'WARN'   { 'Yellow' }
        'ERROR'  { 'Red' }
        'HEADER' { 'Cyan' }
        default  { $host.UI.RawUI.ForegroundColor }
    }
    Write-Host $line -ForegroundColor $fg
    if ($LogPath) {
        try { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
    }
}

$namespace = "root\sms\site_$SiteCode"
$reportTime = Get-Date

Write-Log "Site=$SiteCode Server=$SccmServer"

# Test SCCM WMI connectivity
try {
    $null = Get-WmiObject -Namespace $namespace -Class SMS_Site -ComputerName $SccmServer -ErrorAction Stop
    Write-Log "Connected to SCCM site $SiteCode on $SccmServer" -Level 'OK'
} catch {
    Write-Error "Cannot connect to SCCM WMI on $SccmServer\$namespace : $($_.Exception.Message)"
    Write-Log "WMI connection FAILED: $($_.Exception.Message)" -Level 'ERROR'
    return
}

#endregion Initialization

#region Collectors — SCCM WMI Data Retrieval

# Query SCCM for ALL OSD task sequence executions and build one row per actual deployment attempt.
#
# SMS_TaskSequenceExecutionStatus has one row per STEP per device per advertisement.
# The same ResourceID+AdvertisementID combination accumulates step records across MULTIPLE
# deployment attempts (retries, re-runs). We must split these into separate "runs" to:
#   1. Show every deployment attempt as its own row
#   2. Avoid old failed runs polluting the state of recent successful ones
#   3. Correctly compute duration per attempt
#
# A new "run" is detected when a step appears chronologically AFTER a step that marks a
# fresh start: a very low step number (1-3) OR an action name indicating restart/PXE/boot.
function Get-OSDDeployments {
    Write-Log "Querying SCCM for ALL OSD deployments..." -Level HEADER

    $query = "SELECT ResourceID, AdvertisementID, PackageID, ExecutionTime, ExitCode, Step, ActionName, GroupName, LastStatusMsgName FROM SMS_TaskSequenceExecutionStatus"
    $allRecords = Get-WmiObject -Namespace $namespace -ComputerName $SccmServer -Query $query -ErrorAction SilentlyContinue

    if (-not $allRecords) {
        Write-Log "No OSD execution records found." -Level WARN
        return ,@()
    }

    Write-Log "  Fetched $($allRecords.Count) total step records" -Level INFO

    # Pre-load lookup maps
    Write-Log "  Loading computer registry..." -Level INFO
    $computerMap = @{}
    try {
        $systems = Get-WmiObject -Namespace $namespace -ComputerName $SccmServer -Query "SELECT ResourceID, Name, MACAddresses, LastLogonUserName, OperatingSystemNameandVersion FROM SMS_R_System" -ErrorAction SilentlyContinue
        foreach ($s in $systems) { $computerMap[$s.ResourceID] = $s }
    } catch {}

    Write-Log "  Loading task sequence catalog..." -Level INFO
    $tsMap = @{}
    try {
        $tsPackages = Get-WmiObject -Namespace $namespace -ComputerName $SccmServer -Query "SELECT PackageID, Name FROM SMS_TaskSequencePackage" -ErrorAction SilentlyContinue
        foreach ($t in $tsPackages) { $tsMap[$t.PackageID] = $t.Name }
    } catch {}

    Write-Log "  Loading advertisement details..." -Level INFO
    $adMap = @{}
    try {
        $ads = Get-WmiObject -Namespace $namespace -ComputerName $SccmServer -Query "SELECT AdvertisementID, AdvertisementName, CollectionID, PackageID, PresentTime FROM SMS_Advertisement" -ErrorAction SilentlyContinue
        foreach ($a in $ads) { $adMap[$a.AdvertisementID] = $a }
    } catch {}

    Write-Log "  Loading collection names..." -Level INFO
    $colMap = @{}
    try {
        $cols = Get-WmiObject -Namespace $namespace -ComputerName $SccmServer -Query "SELECT CollectionID, Name FROM SMS_Collection" -ErrorAction SilentlyContinue
        foreach ($c in $cols) { $colMap[$c.CollectionID] = $c.Name }
    } catch {}

    # Group step records by ResourceID + AdvertisementID. Each group may contain multiple runs.
    $grouped = $allRecords | Group-Object { "$($_.ResourceID)|$($_.AdvertisementID)" }

    Write-Log "  Splitting into per-run deployments (grouped by device+advertisement: $($grouped.Count))..." -Level INFO

    # Helper: detect new run boundaries inside a chronologically sorted group.
    # A new run starts whenever the step number DROPS (e.g. step 28 -> step 0 means
    # the TS restarted). This handles gaps and partial data correctly.
    function Get-RunBoundaries($steps) {
        $boundaries = @(0)
        if (-not $steps -or $steps.Count -le 1) { return $boundaries }
        $prev = -1
        for ($idx = 0; $idx -lt $steps.Count; $idx++) {
            $sn = -1
            try { $sn = [int]$steps[$idx].Step } catch {}
            if ($idx -gt 0 -and $sn -ge 0 -and $sn -lt $prev) {
                $boundaries += $idx
            }
            $prev = [Math]::Max($prev, $sn)
        }
        return $boundaries
    }

    $deployments = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($g in $grouped) {
        $allSteps = @($g.Group | Sort-Object ExecutionTime)
        if ($allSteps.Count -eq 0) { continue }

        $runBoundaries = Get-RunBoundaries $allSteps

        $rid  = $allSteps[0].ResourceID
        $adID = $allSteps[0].AdvertisementID

        for ($r = 0; $r -lt $runBoundaries.Count; $r++) {
            $start = $runBoundaries[$r]
            $end   = if ($r -lt $runBoundaries.Count - 1) { $runBoundaries[$r + 1] - 1 } else { $allSteps.Count - 1 }
            $runSteps = $allSteps[$start..$end]
            if (-not $runSteps -or $runSteps.Count -eq 0) { continue }

            # Only emit a row for the LAST run per device+ad (most recent attempt).
            # All earlier runs are tracked via RetryCount below.
            if ($r -lt $runBoundaries.Count - 1) { continue }

            $stepsBySeq = @($runSteps | Sort-Object { [int]$_.Step })
            $maxStepNum  = [int]$stepsBySeq[-1].Step
            $lastStepNum = [int]$stepsBySeq[-1].Step

            $firstExec = $runSteps[0]
            $lastExec  = $runSteps[-1]

            $sysInfo = $computerMap[$rid]
            $tsName  = if ($tsMap[$firstExec.PackageID]) { $tsMap[$firstExec.PackageID] } else { [string]$firstExec.PackageID }
            $adInfo  = $adMap[$adID]
            $adName  = if ($adInfo -and $adInfo.AdvertisementName) { $adInfo.AdvertisementName } else { $adID }
            $colName = if ($adInfo -and $colMap[$adInfo.CollectionID]) { $colMap[$adInfo.CollectionID] } else { 'N/A' }

            $cname = if ($sysInfo -and $sysInfo.Name) { $sysInfo.Name } else { "Unknown (ID:$rid)" }

            # Determine state from THIS run only
            $state  = 'Success'
            $errors = @()
            foreach ($s in $runSteps) {
                if ($s.ExitCode -and [int]$s.ExitCode -ne 0) {
                    $state = 'Failed'
                    $errors += "$($s.ActionName): exit $($s.ExitCode) — $($s.LastStatusMsgName)"
                }
            }
            if ($errors.Count -eq 0 -and $lastExec.ExitCode -and [int]$lastExec.ExitCode -ne 0) {
                $state = 'Failed'
                $errors += "$($lastExec.ActionName): exit $($lastExec.ExitCode)"
            }

            # "Still running" detection
            $phase = ''
            $isTerminal = $lastExec.LastStatusMsgName -match 'completed|ended|success|failed|error|aborted|finished'
            if ($state -ne 'Failed' -and -not $isTerminal) {
                $stale = $false
                try {
                    $lastTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($lastExec.ExecutionTime)
                    $age = (Get-Date) - $lastTime
                    if ($age.TotalHours -gt 72) { $stale = $true }
                } catch {}

                if ($stale) {
                    $state = 'Unknown'
                    $phase = 'Stale (>72 h)'
                    $errors += "Last action was on $($lastTime.ToString('yyyy-MM-dd HH:mm')) — deployment may be abandoned or status records are stale."
                } else {
                    $state = 'Running'
                }
            }

            # Duration (first -> last step of THIS run)
            $duration = 'N/A'
            try {
                $startDt = [System.Management.ManagementDateTimeConverter]::ToDateTime($firstExec.ExecutionTime)
                $endDt   = [System.Management.ManagementDateTimeConverter]::ToDateTime($lastExec.ExecutionTime)
                $span    = $endDt - $startDt
                if ($span.TotalMinutes -ge 1) {
                    $duration = "{0:D2}:{1:D2}:{2:D2}" -f $span.Hours, $span.Minutes, $span.Seconds
                } else {
                    $duration = "$([int]$span.TotalSeconds)s"
                }
            } catch {}

            # Execution time = when this run started
            $execTime = ''
            try {
                $execTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($firstExec.ExecutionTime).ToString('yyyy-MM-dd HH:mm')
            } catch {}

            # Phase based on the LAST step's action/group/status message
            if ([string]::IsNullOrEmpty($phase) -or $phase -eq 'Unknown') {
                $phaseInfo = $lastExec.ActionName + ' ' + $lastExec.GroupName + ' ' + $lastExec.LastStatusMsgName
                $phase = 'Unknown'
                if ($phaseInfo -match 'PXE|Boot|WinPE|Format|Partition')               { $phase = 'WinPE' }
                elseif ($phaseInfo -match 'Upgrade.*Operating|Apply OS|WIM|Image|Setup') { $phase = 'OS Install' }
                elseif ($phaseInfo -match 'Driver|Network|Domain|Join')                 { $phase = 'Setup' }
                elseif ($phaseInfo -match 'Install|Application|App|Software')           { $phase = 'Applications' }
                elseif ($phaseInfo -match 'Restart|Reboot')                             { $phase = 'Post-Reboot' }
                elseif ($lastStepNum -le 3)                                             { $phase = 'Initialization' }
                elseif ($state -eq 'Success')                                           { $phase = 'Complete' }
                elseif ($state -eq 'Running')                                           { $phase = 'In Progress' }
            }

            $row = [ordered]@{
                ResourceID        = $rid
                ComputerName      = $cname
                MAC               = if ($sysInfo -and $sysInfo.MACAddresses) { if ($sysInfo.MACAddresses -is [array]) { ($sysInfo.MACAddresses -join ', ') } else { [string]$sysInfo.MACAddresses } } else { 'N/A' }
                OS                = if ($sysInfo -and $sysInfo.OperatingSystemNameandVersion) { $sysInfo.OperatingSystemNameandVersion } else { 'In Deployment' }
                LastUser          = if ($sysInfo -and $sysInfo.LastLogonUserName) { $sysInfo.LastLogonUserName } else { 'N/A' }
                TaskSequence      = $tsName
                DeploymentName    = $adName
                Collection        = $colName
                AdvertisementID   = $adID
                State             = $state
                Phase             = $phase
                TotalSteps        = $runSteps.Count
                MaxStep           = $maxStepNum
                ExecutionTime     = $execTime
                Duration          = $duration
                ExitCode          = if ($errors.Count -gt 0) { $errors[0] -replace '.{60}.*', '...' } else { $lastExec.ExitCode }
                LastStatusMessage = if ($lastExec.LastStatusMsgName) { $lastExec.LastStatusMsgName } else { 'N/A' }
                Errors            = ($errors -join "`n")
                ErrorCount        = $errors.Count
                Step              = "$lastStepNum/$maxStepNum"
                Action            = if ($lastExec.ActionName) { $lastExec.ActionName } else { 'N/A' }
            }

            $deployments.Add($row)
        }
    }

    # Retry count = total runs (incl. earlier ones we filtered out) per ResourceID+Ad
    $retryMap = @{}
    foreach ($g in $grouped) {
        $allSteps = @($g.Group | Sort-Object ExecutionTime)
        if ($allSteps.Count -eq 0) { continue }
        $key = "$($allSteps[0].ResourceID)|$($allSteps[0].AdvertisementID)"
        $boundaries = Get-RunBoundaries $allSteps
        $retryMap[$key] = $boundaries.Count
    }
    foreach ($d in $deployments) {
        $key = "$($d['ResourceID'])|$($d['AdvertisementID'])"
        $d['RetryCount'] = if ($retryMap.ContainsKey($key)) { $retryMap[$key] } else { 1 }
    }

    # Duration statistics for Successful deployments
    function ParseDurationToSeconds([string]$dur) {
        if ($dur -match '^(\d+):(\d+):(\d+)$') {
            return [int]$Matches[1]*3600 + [int]$Matches[2]*60 + [int]$Matches[3]
        }
        elseif ($dur -match '^(\d+)s$') {
            return [int]$Matches[1]
        }
        return $null
    }
    $successDurations = @($deployments | Where-Object { [string]$_.State -eq 'Success' } | ForEach-Object {
        ParseDurationToSeconds ([string]$_.Duration)
    } | Where-Object { $null -ne $_ })

    $durationStats = $null
    if ($successDurations.Count -gt 0) {
        $avgSec  = [Math]::Round(($successDurations | Measure-Object -Average).Average)
        $minSec  = ($successDurations | Measure-Object -Minimum).Minimum
        $maxSec  = ($successDurations | Measure-Object -Maximum).Maximum
        $fmt     = { param($s) if ($s -ge 3600) { "{0:D2}:{1:D2}:{2:D2}" -f [int]($s/3600), [int](($s%3600)/60), [int]($s%60) } else { "$($s)s" } }
        $script:DurationStats = [ordered]@{
            Count    = $successDurations.Count
            Average  = &$fmt $avgSec
            Fastest  = &$fmt $minSec
            Slowest  = &$fmt $maxSec
        }
    }

    Write-Log "  Done: $($deployments.Count) deployments processed." -Level OK
    return $deployments
}

# Query SMS_DeploymentSummary (FeatureType=7 = OSD) for high-level deployment
# compliance statistics within the date window.
function Get-DeploymentSummaries {
    Write-Log "  Loading OSD deployment summaries (SMS_DeploymentSummary FeatureType=7) ..." -Level INFO
    $all = try {
        @(Get-WmiObject -Namespace $namespace -ComputerName $SccmServer `
            -Query "SELECT * FROM SMS_DeploymentSummary WHERE FeatureType = 7" -ErrorAction SilentlyContinue)
    } catch { @() }
    Write-Log "  Found $($all.Count) OSD deployment summary row(s)" -Level INFO
    $rows = @()
    foreach ($d in $all) {
        $targeted = [int]$d.NumberTargeted
        $succ     = [int]$d.NumberSuccess
        $intent   = [int]$d.DeploymentIntent
        $deployTime = try { [System.Management.ManagementDateTimeConverter]::ToDateTime($d.DeploymentTime).ToString('yyyy-MM-dd HH:mm') } catch { '-' }
        $softName   = if ($d.SoftwareName) { [string]$d.SoftwareName } else { '-' }
        $collName   = if ($d.CollectionName) { [string]$d.CollectionName } else { '-' }
        $item = [ordered]@{
            DeploymentName   = $softName
            Collection       = $collName
            Purpose          = if ($intent -eq 2) { 'Available' } else { 'Required' }
            Compliance       = if ($targeted -gt 0) { [math]::Round((100 * $succ / $targeted), 1) } else { 0 }
            DeploymentTime   = $deployTime
            NumberTargeted   = $targeted
            NumberSuccess    = $succ
            NumberErrors     = [int]$d.NumberErrors
            NumberInProgress = [int]$d.NumberInProgress
            NumberUnknown    = [int]$d.NumberUnknown
            NumberOther      = [int]$d.NumberOther
            AdvertisementID  = [string]$d.DeploymentID
        }
        $rows += $item
    }
    return $rows
}

#endregion Collectors

#region HTML Builder — Outlook-Safe Email Report Generation

Add-Type -AssemblyName System.Web | Out-Null

# HTML-encode a value for safe embedding in email body.
function HtmlEncode {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    [System.Web.HttpUtility]::HtmlEncode([string]$Value)
}

# Outlook-safe color palette: foreground, background, border.
$Palette = @{
    pass = @{ fg = '#16a34a'; bg = '#dcfce7'; bd = '#86efac' }
    warn = @{ fg = '#b45309'; bg = '#fef3c7'; bd = '#fcd34d' }
    fail = @{ fg = '#dc2626'; bg = '#fee2e2'; bd = '#fca5a5' }
    none = @{ fg = '#64748b'; bg = '#f1f5f9'; bd = '#cbd5e1' }
    info = @{ fg = '#0f172a'; bg = '#e0f2fe'; bd = '#7dd3fc' }
}

# Map deployment state to palette key.
function StatusClass([string]$state) {
    switch ($state) {
        'Success' { 'pass' }
        'Failed'  { 'fail' }
        'Running' { 'warn' }
        default   { 'none' }
    }
}

# Render a pill-shaped status badge (Success/Failed/Running/Unknown).
function NewBadge([string]$label, [string]$cls = 'none') {
    $p = $Palette[$cls]
    "<span style=""display:inline-block;padding:2px 10px;border-radius:999px;background-color:$($p.bg);color:$($p.fg);border:1px solid $($p.bd);font-family:Calibri,Arial,sans-serif;font-size:13px;font-weight:700;white-space:nowrap;"">$(HtmlEncode $label)</span>"
}

# Render a summary stat card (e.g. TOTAL, SUCCESS, FAILED, RUNNING).
function Card {
    param(
        [string]$Title,
        [string]$Value,
        [string]$Sub,
        [string]$AccentHex,
        [string]$ValueColor = ''
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { $Value = '0' }
    if (-not $ValueColor) { $ValueColor = '#0f172a' }
    $valueClass = switch ($Title) {
        'SUCCESS' { 'pass' } 'FAILED' { 'fail' } 'RUNNING' { 'warn' } default { 'none' }
    }
    $p = $Palette[$valueClass]
@"
<td valign="top" width="25%" style="padding:8px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
    <tr>
      <td style="background-color:#ffffff;border:1px solid #d8e1ec;border-top:3px solid $AccentHex;border-radius:10px;padding:14px 14px;">
        <div style="font-family:Calibri,Arial,sans-serif;font-size:13px;letter-spacing:.8px;text-transform:uppercase;color:#475569;font-weight:700;">$(HtmlEncode $Title)</div>
        <div style="font-family:Calibri,Arial,sans-serif;font-size:34px;line-height:1.1;color:$ValueColor;font-weight:900;margin-top:4px;">$(HtmlEncode $Value)</div>
        <div style="font-family:Calibri,Arial,sans-serif;font-size:13px;color:#64748b;margin-top:4px;">$(HtmlEncode $Sub)</div>
      </td>
    </tr>
  </table>
</td>
"@
}

# Wrap up to 4 Card cells in a single table row.
function CardsRow4 {
    param([string[]]$CardsHtml)
    if (-not $CardsHtml -or $CardsHtml.Count -eq 0) { return '' }
    $cells = @($CardsHtml)
    while ($cells.Count -lt 4) { $cells += '<td valign="top" width="25%" style="padding:8px;">&nbsp;</td>' }
@"
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
  <tr>$($cells -join "`r`n")</tr>
</table>
"@
}

# Render a section divider with a title and optional note.
function SectionHeader {
    param([string]$Title, [string]$AccentHex, [string]$Note)
@"
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;margin-top:18px;margin-bottom:12px;">
  <tr>
    <td style="padding:0 0 0 12px;border-left:4px solid $AccentHex;">
      <div style="font-family:Calibri,Arial,sans-serif;color:#0f172a;font-size:16px;font-weight:800;line-height:1.2;">$(HtmlEncode $Title)</div>
      <div style="font-family:Calibri,Arial,sans-serif;color:#94a3b8;font-size:12px;margin-top:3px;">$(HtmlEncode $Note)</div>
    </td>
  </tr>
</table>
"@
}

# Render a table header cell with uppercase label.
function Th([string]$text, [string]$align = 'left') {
    "<th style=""padding:8px 10px;background-color:#f8fafc;color:#475569;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:$align;"">$(HtmlEncode $text)</th>"
}

# Build the complete HTML email report with:
# - Summary cards (Total / Success / Failed / Running)
# - Deployment compliance table (SMS_DeploymentSummary)
# - Per-task-sequence breakdown with success rate bars
# - Duration statistics (average, fastest, slowest for successful deploys)
# - Detailed device deployment table sorted by severity
function Build-OSDEmailReport {
    param(
        [Parameter(Mandatory=$false)][System.Collections.IEnumerable]$Items,
        [string]$SiteServer = $SccmServer,
        [string]$Site       = $SiteCode,
        [datetime]$Generated = (Get-Date),
        [string]$Title       = 'SCCM OSD Deployment Status',
        [string]$Description = 'Operating System Deployment execution report — recent deployments, status, and errors.',
        [System.Collections.IEnumerable]$DeploymentSummaries = $null
    )

    $list   = @(if ($Items) { $Items } else { @() })
    $total  = $list.Count
    $states = @{'Success'=0; 'Failed'=0; 'Running'=0; 'Unknown'=0}
    foreach ($i in $list) {
        $s = [string]$i['State']
        if ($states.ContainsKey($s)) { $states[$s]++ } else { $states['Unknown']++ }
        $i['__StateClass'] = StatusClass $s
    }

    $overallScore = if ($total -gt 0) {
        [Math]::Max(0, [Math]::Min(100, [int]([Math]::Round(($states['Success'] / $total) * 100, 0))))
    } else { 0 }

    $sb = New-Object System.Text.StringBuilder
    $generatedText = $Generated.ToString('yyyy-MM-dd HH:mm:ss')

    # ============ Header + Summary ============
    [void]$sb.AppendLine(@"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
</head>
<body style="margin:0;padding:0;background-color:#eef2f6;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;background-color:#eef2f6;">
    <tr>
      <td align="center" style="padding:24px 12px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
          <tr>
            <td style="background-color:#ffffff;border:1px solid #d7deea;border-top:4px solid #1e40af;border-radius:12px;padding:22px 24px 20px 24px;">

              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
                <tr>
                  <td style="padding:0 0 6px 0;font-family:Calibri,Arial,sans-serif;color:#1e40af;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:1px;">SCCM OSD Report</td>
                </tr>
                <tr>
                  <td style="padding:0 0 8px 0;"><div style="font-family:Calibri,Arial,sans-serif;color:#0f172a;font-size:28px;font-weight:800;line-height:1.2;">$(HtmlEncode $Title)</div></td>
                </tr>
                <tr>
                  <td style="padding:0 0 14px 0;font-family:Calibri,Arial,sans-serif;color:#475569;font-size:15px;line-height:1.6;">$(HtmlEncode $Description)</td>
                </tr>
                <tr>
                  <td style="padding:0 0 16px 0;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;background-color:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;">
                      <tr>
                        <td style="padding:8px 12px;font-family:Calibri,Arial,sans-serif;font-size:14px;color:#334155;"><b style="color:#0f172a;">Site:</b> $(HtmlEncode $Site) @ $(HtmlEncode $SiteServer)</td>
                        <td style="padding:8px 12px;font-family:Calibri,Arial,sans-serif;font-size:14px;color:#334155;"><b style="color:#0f172a;">Generated:</b> $(HtmlEncode $generatedText)</td>
                        <td style="padding:8px 12px;font-family:Calibri,Arial,sans-serif;font-size:14px;color:#334155;text-align:right;"><b style="color:#0f172a;">Success Rate:</b> <span style="color:#16a34a;font-weight:800;">$overallScore%</span></td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              $(CardsRow4 -CardsHtml @(
                  (Card -Title "TOTAL"   -Value $total             -Sub "Unique device deployments"         -AccentHex "#1e40af"),
                  (Card -Title "SUCCESS" -Value $states['Success'] -Sub "Completed without errors"         -AccentHex "#22c55e"),
                  (Card -Title "FAILED"  -Value $states['Failed']  -Sub "Needs investigation"              -AccentHex "#ef4444"),
                  (Card -Title "RUNNING" -Value $states['Running'] -Sub "Currently in progress"            -AccentHex "#f59e0b")
              ))
$(if ($depSummaries.Count -gt 0) {
    $aggTargeted = ($depSummaries | Measure-Object -Property NumberTargeted -Sum).Sum
    $aggSuccess  = ($depSummaries | Measure-Object -Property NumberSuccess  -Sum).Sum
    $aggErrors   = ($depSummaries | Measure-Object -Property NumberErrors   -Sum).Sum
    $aggOther    = ($depSummaries | Measure-Object -Property NumberOther    -Sum).Sum
    $aggIP       = ($depSummaries | Measure-Object -Property NumberInProgress -Sum).Sum
    $aggUnk      = ($depSummaries | Measure-Object -Property NumberUnknown  -Sum).Sum
    $aggComp = if ($aggTargeted -gt 0) { [math]::Round((100 * $aggSuccess / $aggTargeted), 1) } else { 0 }
    CardsRow4 -CardsHtml @(
        (Card -Title "TARGETED" -Value $aggTargeted -Sub "Total devices targeted across all deployments" -AccentHex "#6366f1"),
        (Card -Title "SUCCEEDED" -Value $aggSuccess -Sub "$aggComp% overall compliance" -AccentHex "#22c55e"),
        (Card -Title "ERRORS"   -Value $aggErrors  -Sub "Requires investigation" -AccentHex "#ef4444"),
        (Card -Title "NOT MET"  -Value $aggOther   -Sub "Requirements not met / Other" -AccentHex "#a855f7")
    )
})

"@)

    # ============ Deployment Summary (SMS_DeploymentSummary) ============
    $depSummaries = @(if ($DeploymentSummaries) { $DeploymentSummaries } else { @() })
    if ($depSummaries.Count -gt 0) {
        [void]$sb.AppendLine((SectionHeader -Title "Deployment Summary" -AccentHex "#1e40af" -Note "$($depSummaries.Count) OSD deployment(s) — compliance from SMS_DeploymentSummary (FeatureType=7)."))
        $depRows = ''
        foreach ($ds in $depSummaries) {
            $dn = HtmlEncode $ds.DeploymentName
            $dc = HtmlEncode $ds.Collection
            $dp = HtmlEncode $ds.Purpose
            $comp = "$($ds.Compliance)%"
            $dt = HtmlEncode $ds.DeploymentTime
            $targeted = [int]$ds.NumberTargeted
            $nsucc    = [int]$ds.NumberSuccess
            $nerr     = [int]$ds.NumberErrors
            $nip      = [int]$ds.NumberInProgress
            $nunk     = [int]$ds.NumberUnknown
            $nother   = [int]$ds.NumberOther
            $depRows += @"
                <tr>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#0f172a;font-weight:600;">$dn</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#334155;">$dc</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#334155;text-align:center;">$dp</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:13px;font-weight:700;text-align:right;color:#16a34a;">$comp</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#334155;white-space:nowrap;">$dt</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#334155;text-align:center;">$targeted</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#16a34a;font-weight:700;text-align:center;">$nsucc</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#dc2626;font-weight:700;text-align:center;">$nerr</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#b45309;font-weight:700;text-align:center;">$nip</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#64748b;text-align:center;">$nunk</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#a855f7;font-weight:700;text-align:center;">$nother</td>
                </tr>
"@
        }
        [void]$sb.AppendLine(@"
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;background-color:#ffffff;border:1px solid #e2e8f0;border-radius:10px;overflow:hidden;">
                <tr>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#475569;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:left;">Deployment</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#475569;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:left;">Collection</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#475569;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:center;">Purpose</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#16a34a;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:right;">Compliance</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#475569;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:left;">Created</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#475569;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:center;">Targeted</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#16a34a;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:center;">Success</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#dc2626;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:center;">Errors</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#b45309;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:center;">In Prog</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#475569;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:center;">Unknown</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#a855f7;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:center;">Not Met</th>
                </tr>
$depRows
              </table>
"@)
    }

    # ============ Per-TS breakdown ============
    if ($total -gt 0) {
        $byTS = @($list | Group-Object { $_['TaskSequence'] } | Sort-Object Count -Descending)
        [void]$sb.AppendLine((SectionHeader -Title "Deployments by Task Sequence" -AccentHex "#1e40af" -Note "Status counts grouped by task sequence package."))

        $tsRows = ''
        foreach ($tsg in $byTS) {
            $ok   = 0; $bad = 0; $run = 0
            foreach ($d in $tsg.Group) {
                switch ([string]$d['State']) {
                    'Success' { $ok++ }
                    'Failed'  { $bad++ }
                    'Running' { $run++ }
                }
            }
            $cnt    = $tsg.Count
            $rate   = if ($cnt -gt 0) { [int](($ok / $cnt) * 100) } else { 0 }
            $rateCls = if ($bad -gt 0) { 'fail' } elseif ($rate -eq 100) { 'pass' } else { 'warn' }
            $rateP  = $Palette[$rateCls]
            $tsName = HtmlEncode ([string]$tsg.Name)
            $tsRows += @"
                <tr>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:14px;color:#0f172a;font-weight:600;">$tsName</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:14px;color:#334155;text-align:center;">$cnt</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:14px;color:#16a34a;text-align:center;font-weight:700;">$ok</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:14px;color:#dc2626;text-align:center;font-weight:700;">$bad</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:14px;color:#b45309;text-align:center;font-weight:700;">$run</td>
                  <td style="padding:8px 10px;border-bottom:1px solid #f1f5f9;font-family:Calibri,Arial,sans-serif;font-size:14px;font-weight:800;text-align:right;color:$($rateP.fg);">
                    <table role="presentation" cellpadding="0" cellspacing="0" border="0" align="right" width="120" style="border-collapse:collapse;">
                      <tr>
                        <td style="font-size:14px;font-weight:800;color:$($rateP.fg);padding-right:6px;">$rate%</td>
                        <td width="65" style="background-color:#f1f5f9;border-radius:5px;vertical-align:middle;">
                          <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="$rate" style="border-collapse:collapse;">
                            <tr><td style="height:7px;background-color:$($rateP.fg);border-radius:5px;font-size:1px;line-height:1px;">&nbsp;</td></tr>
                          </table>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
"@
        }

        [void]$sb.AppendLine(@"
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;background-color:#ffffff;border:1px solid #e2e8f0;border-radius:10px;overflow:hidden;">
                <tr>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#475569;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:left;">Task Sequence</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#475569;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:center;">Devices</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#16a34a;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:center;">Success</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#dc2626;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:center;">Failed</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#b45309;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:center;">Running</th>
                  <th style="padding:8px 10px;background-color:#f8fafc;color:#475569;font-family:Calibri,Arial,sans-serif;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;border-bottom:2px solid #e2e8f0;text-align:right;">Success Rate</th>
                </tr>
$tsRows
              </table>
"@)
    }

    # ============ Duration statistics (Success only) ============
    if ($script:DurationStats) {
        $ds = $script:DurationStats
        [void]$sb.AppendLine((SectionHeader -Title "Duration Summary" -AccentHex "#16a34a" -Note "$($ds.Count) successful deployment(s) — average, fastest, and slowest times."))
        [void]$sb.AppendLine(@"
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
                <tr>
                  <td valign="top" width="33%" style="padding:6px;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
                      <tr><td style="background-color:#ffffff;border:1px solid #e0e7ff;border-left:3px solid #6366f1;border-radius:8px;padding:14px 16px;">
                        <div style="font-family:Calibri,Arial,sans-serif;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:#6366f1;">Average</div>
                        <div style="font-family:Consolas,monospace;font-size:22px;font-weight:800;color:#0f172a;margin-top:4px;">$($ds.Average)</div>
                      </td></tr>
                    </table>
                  </td>
                  <td valign="top" width="33%" style="padding:6px;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
                      <tr><td style="background-color:#ffffff;border:1px solid #d1fae5;border-left:3px solid #16a34a;border-radius:8px;padding:14px 16px;">
                        <div style="font-family:Calibri,Arial,sans-serif;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:#16a34a;">Fastest</div>
                        <div style="font-family:Consolas,monospace;font-size:22px;font-weight:800;color:#0f172a;margin-top:4px;">$($ds.Fastest)</div>
                      </td></tr>
                    </table>
                  </td>
                  <td valign="top" width="34%" style="padding:6px;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">
                      <tr><td style="background-color:#ffffff;border:1px solid #fee2e2;border-left:3px solid #dc2626;border-radius:8px;padding:14px 16px;">
                        <div style="font-family:Calibri,Arial,sans-serif;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:#dc2626;">Slowest</div>
                        <div style="font-family:Consolas,monospace;font-size:22px;font-weight:800;color:#0f172a;margin-top:4px;">$($ds.Slowest)</div>
                      </td></tr>
                    </table>
                  </td>
                </tr>
              </table>
"@)
    }

    # ============ Device detail table ============
    [void]$sb.AppendLine((SectionHeader -Title "Device Deployment Details" -AccentHex "#1e40af" -Note "$total device deployment(s) found."))

    if ($total -gt 0) {
        $rows = ''
        $i = 0
        foreach ($d in ($list | Sort-Object { @('Failed','Running','Success','Unknown').IndexOf([string]$_['State']) }, { $_['ExecutionTime'] })) {
            $st      = [string]$d['State']
            $cls     = StatusClass $st
            $p       = $Palette[$cls]
            $badge   = NewBadge $st $cls

            $name    = HtmlEncode $d['ComputerName']
            $mac     = HtmlEncode $d['MAC']
            $ts      = HtmlEncode $d['TaskSequence']
            $coll    = HtmlEncode $d['Collection']
            $start   = HtmlEncode $d['ExecutionTime']
            $dur     = HtmlEncode $d['Duration']
            $step    = HtmlEncode $d['Step']
            $phase   = HtmlEncode $d['Phase']
            $msg     = HtmlEncode $d['LastStatusMessage']
            $retry   = [int]$d['RetryCount']

            $errLine = ''
            if ($st -eq 'Failed' -and [int]$d['ErrorCount'] -gt 0) {
                $errLine = HtmlEncode (($d['Errors'] -split "`n")[0])
                $msg = $errLine
            }

            $rowBg = if ($st -eq 'Failed') { 'background-color:#fef2f2;' } elseif ($st -eq 'Running') { 'background-color:#fffbeb;' } elseif ($i % 2 -eq 0) { 'background-color:#ffffff;' } else { 'background-color:#f8fafc;' }
            $i++

            $rows += @"
                <tr style="$rowBg;">
                  <td style="padding:10px 12px;border-bottom:1px solid #eef2f7;border-left:4px solid $($p.fg);font-family:Calibri,Arial,sans-serif;">
                    <div style="font-size:14px;font-weight:700;color:#0f172a;">
                      <span style="display:inline-block;width:8px;height:8px;border-radius:50%;background-color:$($p.fg);margin-right:6px;vertical-align:middle;"></span>$name$(if($retry -gt 1){" <span style=`"font-size:10px;color:#94a3b8;font-weight:500;`">x$retry</span>"})
                    </div>
                    <div style="font-size:11px;color:#94a3b8;margin-top:2px;margin-left:14px;">$mac</div>
                  </td>
                  <td style="padding:9px 10px;border-bottom:1px solid #eef2f7;font-family:Calibri,Arial,sans-serif;">
                    $badge
                    <div style="font-size:12px;color:#64748b;margin-top:3px;">$phase</div>
                  </td>
                  <td style="padding:9px 10px;border-bottom:1px solid #eef2f7;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#334155;">$ts</td>
                  <td style="padding:9px 10px;border-bottom:1px solid #eef2f7;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#334155;">$coll</td>
                  <td style="padding:9px 10px;border-bottom:1px solid #eef2f7;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#334155;text-align:center;">$(HtmlEncode $d['Purpose'])</td>
                  <td style="padding:9px 10px;border-bottom:1px solid #eef2f7;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#334155;">$start</td>
                  <td style="padding:9px 10px;border-bottom:1px solid #eef2f7;font-family:Calibri,Arial,sans-serif;font-size:13px;color:#334155;white-space:nowrap;">
                    $dur
                    <div style="font-size:12px;color:#94a3b8;">Steps: $step</div>
                  </td>
                  <td style="padding:9px 10px;border-bottom:1px solid #eef2f7;font-family:Calibri,Arial,sans-serif;font-size:12px;color:#64748b;">$msg</td>
                </tr>
"@
        }

        [void]$sb.AppendLine(@"
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;background-color:#ffffff;border:1px solid #e2e8f0;border-radius:10px;overflow:hidden;">
                <tr>
                  $(Th "Device")
                  $(Th "Status")
                  $(Th "Task Sequence")
                  $(Th "Collection")
                  $(Th "Purpose" "center")
                  $(Th "Started")
                  $(Th "Duration" "center")
                  $(Th "Last Message")
                </tr>
$rows
              </table>
"@)
    } else {
        [void]$sb.AppendLine(@"
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;background-color:#ffffff;border:1px solid #e2e8f0;border-radius:10px;">
                <tr>
                  <td style="padding:22px;font-family:Calibri,Arial,sans-serif;font-size:15px;color:#94a3b8;text-align:center;">No OSD task sequence executions found.</td>
                </tr>
              </table>
"@)
    }

    # ============ Footer ============
    [void]$sb.AppendLine(@"
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;margin-top:16px;">
                <tr>
                  <td style="padding:10px 0 0 0;border-top:1px solid #e2e8f0;font-family:Calibri,Arial,sans-serif;color:#94a3b8;font-size:13px;line-height:1.6;">
                    Generated for SCCM site <b>$(HtmlEncode $Site)</b> on $(HtmlEncode $generatedText).<br/>
                    Data sources: SMS_DeploymentSummary + SMS_TaskSequenceExecutionStatus (WMI) &nbsp;|&nbsp; Host: $(HtmlEncode $env:COMPUTERNAME)
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"@)

    $sb.ToString()
}

#endregion HTML Builder

#region Main — Orchestration: Collect, Build, Save, Send

# Step 1 — Collect raw deployment data from SCCM WMI
$deployments = Get-OSDDeployments
if (-not $deployments) { $deployments = @() }

# Step 2 — Collect high-level deployment summaries
$deploymentSummaries = Get-DeploymentSummaries

# Step 3 — Merge deployment purpose (Required/Available) from summaries into device rows
if ($deploymentSummaries.Count -gt 0 -and $deployments.Count -gt 0) {
    $adPurposeMap = @{}
    foreach ($ds in $deploymentSummaries) {
        if ($ds.AdvertisementID) { $adPurposeMap[$ds.AdvertisementID] = $ds.Purpose }
    }
    foreach ($d in $deployments) {
        $aid = [string]$d['AdvertisementID']
        $d['Purpose'] = if ($adPurposeMap.ContainsKey($aid)) { $adPurposeMap[$aid] } else { 'Required' }
    }
} else {
    foreach ($d in $deployments) { $d['Purpose'] = 'Required' }
}

# Step 4 — Build the HTML report string
$reportTitle = "OSD Deployment Status – $SiteCode"
$reportDesc  = "Operating System Deployment status report — deployment compliance and task sequence execution details."

$htmlReport = Build-OSDEmailReport -Items $deployments -Site $SiteCode `
    -SiteServer $SccmServer -Generated $reportTime -Title $reportTitle -Description $reportDesc `
    -DeploymentSummaries $deploymentSummaries

# Step 5 — Save HTML report to disk
if (-not (Test-Path $ReportPath)) { New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null }
$reportFile = Join-Path $ReportPath ("OSDDeploymentReport_{0}.html" -f $reportTime.ToString('yyyyMMdd_HHmmss'))
$htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
Write-Log "Report saved to: $reportFile" -Level OK

# Step 6 — Send email via Microsoft Graph API
if ($SendEmail) {
    if (-not $htmlReport) {
        Write-Warning "Report HTML is empty — skipping email."
    }
    else {
        # Resolve client secret: param > env var > default
        $secret = $ClientSecret
        if (-not $secret -and $env:OSD_REPORT_CLIENT_SECRET) {
            $secret = ConvertTo-SecureString $env:OSD_REPORT_CLIENT_SECRET -AsPlainText -Force
        }
        if (-not $secret) {
            $secret = ConvertTo-SecureString $ClientSecretDefault -AsPlainText -Force
        }

        Write-Log "Acquiring Graph access token (app: $ClientId) ..." -Level INFO
        $token = Get-GraphAccessToken -Tenant $TenantId -Client $ClientId -Secret $secret
        if (-not $token) {
            Write-Error "Failed to acquire Graph API access token. Check TenantId, ClientId, and ClientSecret."
        }
        else {
            try {
                Write-Log "Sending email via Microsoft Graph to $($UserTo -join ', ') ..." -Level INFO
                Send-GraphMailMessage -AccessToken $token -From $UserFrom -To $UserTo -Subject $Subject -HtmlBody $htmlReport
                Write-Log "Email sent to $($UserTo -join ', ')" -Level OK
            } catch {
                Write-Error "Failed to send email via Graph API: $($_.Exception.Message)"
            }
        }
    }
}

#endregion Main


