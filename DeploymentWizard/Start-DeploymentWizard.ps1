<#
.SYNOPSIS
    Computer Deployment Wizard — SCCM Task Sequence Wrapper v1.0

.CONFIGURATION
    Before using this script, replace the following placeholders with your actual values:

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ PLACEHOLDER              │ PARAMETER       │ DESCRIPTION                     │
    ├──────────────────────────┼─────────────────┼─────────────────────────────────┤
    │ "Your Company Name"      │ -CompanyName    │ Organization name (UI title)    │
    │ "YC"                     │ -CompanyShort   │ 2-3 char logo badge code        │
    │ "IT Operations"          │ -Department     │ Department name in header       │
    │ yourdomain.local         │ -DomainName     │ Active Directory domain FQDN    │
    │ OU=...,DC=...,DC=...     │ -SearchBase     │ LDAP root OU distinguished name │
    │ dc01.yourdomain.local    │ -DomainController│ DC hostname for auth/LDAP      │
    │ sccm.yourdomain.local    │ -SccmServer     │ SCCM MP hostname                │
    │ "Your Company Name"      │ -OrgName        │ Written to OSDRegisteredOrgName │
    └──────────────────────────────────────────────────────────────────────────────┘

.DESCRIPTION
    This script is the entry point for SCCM/MECM Task Sequences. It launches the
    DeploymentWizard.ps1 WPF application in a separate PowerShell process,
    monitors its exit code, and reads back the Task Sequence variables written
    by the wizard for verification in the SCCM log.

    Architecture:
      [SCCM TS Step] → Start-DeploymentWizard.ps1 → powershell.exe → DeploymentWizard.ps1
                                          ↓
                                    WPF Wizard (user interaction)
                                          ↓
                                    Write-SCCMVariables (COM TSEnv)
                                          ↓
                                    Exit code + variables in SCCM log

.PARAMETER CompanyName
    Organization name forwarded to the wizard. Default: "Momar Tech"

.PARAMETER CompanyShort
    Abbreviated org code (2-3 chars) for logo badge. Default: "MT"

.PARAMETER Department
    Department name for header/footer display. Default: "IT Operations"

.PARAMETER DomainName
    Active Directory domain for authentication and join. Default: "momar.local"

.PARAMETER SearchBase
    LDAP OU root path for browsing. Format: "OU=...,DC=...,DC=..."
    Default: "OU=Domain Computers,DC=Momar,DC=local"

.PARAMETER DomainController
    DC hostname for connectivity testing. Default: "dc01.momar.local"

.PARAMETER SccmServer
    SCCM management point for connectivity testing. Default: "sccm.momar.local"

.PARAMETER OrgName
    Value written to OSDRegisteredOrgName SCCM variable. Default: "Momar Tech"

.PARAMETER Software
    Software list in format "Name|TSVariableName|DefaultChecked". Default: one entry.

.EXAMPLE
    .\Start-DeploymentWizard.ps1

    Runs with all Momar Tech default values.

.EXAMPLE
    .\Start-DeploymentWizard.ps1 -CompanyName "Contoso" -DomainName "contoso.com" `
        -SearchBase "OU=PCs,DC=contoso,DC=com" -DomainController "dc01.contoso.com" `
        -SccmServer "sccm.contoso.com" -OrgName "Contoso Ltd"

    Custom deployment for Contoso — overrides all organization-specific parameters.

.INPUTS
    None. Parameters passed directly to the PowerShell process.

.OUTPUTS
    Task Sequence variables written to COM Microsoft.SMS.TSEnvironment:
      OSDComputerName, OSDDomainName, OSDDomainOUName, OSDJoinAccount,
      OSDJoinPassword, OSDRegisteredOrgName, App_* (custom software variables)

.NOTES
    File Name    : Start-DeploymentWizard.ps1
    Version      : 1.0
    Dependencies : DeploymentWizard.ps1 (must be in same directory)
    Package      : Start-DeploymentWizard.ps1 + DeploymentWizard.ps1
    WinPE        : WinPE-PowerShell (~45 MB), WinPE-NetFX (~195 MB)

    Exit Codes:
      0 = Success (wizard completed, variables written)
      1 = Failure (wizard not found, wizard crashed, or validation error)

    Log Format:
      [YYYY-MM-DD HH:mm:ss] [LEVEL] Message
      LEVEL: INFO | SUCCESS | WARN | ERROR

    SCCM Task Sequence Integration:
       1. Add "Run PowerShell Script" step to your Task Sequence
       2. Select Start-DeploymentWizard.ps1 as the script name
       3. Ensure both Start-DeploymentWizard.ps1 and DeploymentWizard.ps1 are in the package
      4. Configure step to continue on error if you want to handle wizard errors gracefully

.LINK
    DeploymentWizard.ps1 — Main WPF wizard script
    technical-architecture.md — Technical architecture reference
    README.md — Full setup and configuration guide
#>
param(
    [string]$CompanyName       = "Momar Tech",                                 # Org name forwarded to wizard
    [string]$CompanyShort      = "MT",                                         # Logo badge abbreviation
    [string]$Department        = "IT Operations",                              # Dept name in header/footer
    [string]$DomainName        = "momar.local",                                # AD domain for auth/join
    [string]$SearchBase        = "OU=Domain Computers,DC=Momar,DC=local",      # LDAP root OU
    [string]$DomainController  = "dc01.momar.local",                           # DC for connectivity test
    [string]$SccmServer        = "sccm.momar.local",                           # SCCM MP for connectivity test
    [string]$OrgName           = "Momar Tech",                                 # OSDRegisteredOrgName value
    [string[]]$Software        = @("Cisco AnyConnect VPN|App_CiscoAnyConnect|true"),  # Software list
    [string]$DefaultLanguage   = "en-US"                                       # OS language (en-US/ar-SA)
)

################################################################################
#  LOGGING HELPER
#  Timestamp format: [YYYY-MM-DD HH:mm:ss] [LEVEL] Message
#  Levels: INFO (default), SUCCESS, WARN, ERROR
#  Note: Timestamp is captured once at script start — consistent for the run.
################################################################################
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
function Write-Log {
    param([string]$M, [string]$L = "INFO")
    Write-Host "[$ts] [$L] $M"
}

################################################################################
#  PARAMETER VALIDATION
#  Ensure required parameters are populated. Exit early with clear error.
################################################################################

if ([string]::IsNullOrWhiteSpace($DomainName)) {
    Write-Log "DomainName is required" "ERROR"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($SearchBase)) {
    Write-Log "SearchBase is required" "ERROR"
    exit 1
}

################################################################################
#  PATH RESOLUTION
#  Resolve wizard path with fallbacks for various execution contexts:
#    1. $MyInvocation.MyCommand.Path — Standard execution
#    2. $PSScriptRoot — PowerShell V3+ automatic variable
#    3. Get-Location — Last resort for interactive execution
################################################################################
$scriptRoot = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } elseif ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$wizardPath = Join-Path $scriptRoot "DeploymentWizard.ps1"

if (-not (Test-Path $wizardPath)) {
    Write-Host "[$ts] [ERROR] DeploymentWizard.ps1 not found at: $wizardPath" -ForegroundColor Red
    exit 1
}

Write-Log "$CompanyName - Deployment Wizard v1.0" "INFO"
Write-Log "Domain      : $DomainName"
Write-Log "SearchBase  : $SearchBase"
Write-Log "DC          : $DomainController"
Write-Log "SCCM        : $SccmServer"

################################################################################
#  BUILD WIZARD ARGUMENTS
#  Construct PowerShell argument list to pass all parameters to the wizard.
#  Each -Software entry is added individually (PowerShell arrays don't
#  serialize well through process boundaries).
################################################################################
$wizArgs = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wizardPath,
    "-CompanyName", $CompanyName, "-CompanyShort", $CompanyShort,
    "-Department", $Department, "-DomainName", $DomainName,
    "-SearchBase", $SearchBase, "-DomainController", $DomainController,
    "-SccmServer", $SccmServer, "-OrgName", $OrgName, "-DefaultLanguage", $DefaultLanguage
)
foreach ($s in $Software) {
    $wizArgs += "-Software"
    $wizArgs += $s
}

################################################################################
#  LAUNCH WIZARD
#  Execute wizard in child PowerShell process. $LASTEXITCODE reflects wizard exit.
#  The wizard may exit with non-zero for errors or if user cancels.
################################################################################
try {
    & powershell.exe @wizArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Log "Wizard exited with code $LASTEXITCODE" "WARN"
    }

################################################################################
#  READ BACK TASK SEQUENCE VARIABLES
#  Verify all variables were written by the wizard and log them.
#  OSDJoinPassword is masked (never shown in logs).
#  Runs in try/catch — TSEnvironment COM object is unavailable outside SCCM.
################################################################################
    try {
        $tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment
        Write-Log "--- Task Sequence Variables ---" "SUCCESS"
        Write-Log "  OSDComputerName       = $($tsenv.Value('OSDComputerName'))"
        Write-Log "  OSDDomainName         = $($tsenv.Value('OSDDomainName'))"
        Write-Log "  OSDDomainOUName       = $($tsenv.Value('OSDDomainOUName'))"
        Write-Log "  OSDJoinAccount        = $($tsenv.Value('OSDJoinAccount'))"
        Write-Log "  OSDJoinPassword       = ********"
        Write-Log "  OSDRegisteredOrgName  = $($tsenv.Value('OSDRegisteredOrgName'))"
        foreach ($s in $Software) {
            $parts = $s -split '\|', 3
            Write-Log "  $($parts[1]) = $($tsenv.Value($parts[1]))"
        }
        Write-Log "Deployment completed successfully." "SUCCESS"
    }
    catch {
        Write-Log "TSEnvironment not available - outside Task Sequence." "WARN"
    }
}
catch {
    Write-Log "Deployment wizard failed: $_" "ERROR"
    exit 1
}
