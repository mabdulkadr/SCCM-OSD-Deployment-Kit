# 🚀 Start-DeploymentWizard.ps1 (Task Sequence Wrapper)

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-WinPE%20%2B%20Full%20OS-lightgrey.svg)
![SCCM](https://img.shields.io/badge/SCCM-Task%20Sequence-orange.svg)
![Version](https://img.shields.io/badge/version-1.0-green.svg)

---

## ⚙️ Configuration Required

> Replace the default parameter values with your organization's data in the SCCM Task Sequence step.

```powershell
.\Start-DeploymentWizard.ps1 `
    -CompanyName      "Your Company" `
    -CompanyShort     "YC" `
    -Department       "IT Operations" `
    -DomainName       "yourdomain.local" `
    -SearchBase       "OU=Domain Computers,DC=yourdomain,DC=local" `
    -DomainController "dc01.yourdomain.local" `
    -SccmServer       "sccm.yourdomain.local" `
    -OrgName          "Your Company" `
    -Software         @("Chrome|App_Chrome|true","Firefox|App_Firefox|true")
```

| Parameter | Default | Description |
|---|---|---|
| `-CompanyName` | `Momar Tech` | Organization name shown in UI |
| `-CompanyShort` | `MT` | 2-3 char logo badge code |
| `-Department` | `IT Operations` | Department name in header |
| `-DomainName` | `momar.local` | AD domain FQDN |
| `-SearchBase` | `OU=Domain Computers,DC=Momar,DC=local` | LDAP root OU |
| `-DomainController` | `dc01.momar.local` | DC for auth/LDAP |
| `-SccmServer` | `sccm.momar.local` | SCCM MP FQDN |
| `-OrgName` | `Momar Tech` | OSDRegisteredOrgName value |
| `-Software` | Cisco AnyConnect | `Name|TSVar|Default` format |

---

## 📖 Overview

**Start-DeploymentWizard.ps1** is the **SCCM Task Sequence entry point** for the deployment wizard. It acts as a bridge between the SCCM task sequence engine and the [`DeploymentWizard.ps1`](DeploymentWizard.md) WPF application.

Its job is simple but critical: **validate, launch, monitor, verify**.

```
[SCCM TS Step] → Start-DeploymentWizard.ps1
                      │
                      ├─ Validate parameters (DomainName, SearchBase required)
                      ├─ Resolve DeploymentWizard.ps1 path (3 fallbacks)
                      ├─ Build argument list (forward all params)
                      │
                      ▼
              powershell.exe -File DeploymentWizard.ps1 (child process)
                      │
                      ├─ WPF Wizard runs (user interaction, blocking)
                      │
                      ▼
              $LASTEXITCODE checked
                      │
                      ├─ Read back TS variables via COM TSEnvironment
                      ├─ Mask password (********)
                      ├─ Log all values to smsts.log
                      │
                      ▼
              Exit 0 (success) or Exit 1 (failure)
```

### Why a Separate Wrapper?

The wrapper solves two architectural problems:

1. **Process isolation** — the WPF wizard runs in a **child `powershell.exe` process**. If the wizard crashes, hangs, or the user cancels, the task sequence step is not affected. The wrapper can gracefully exit `1` and the TS can be configured to continue on error.

2. **Variable verification** — after the wizard closes, the wrapper reads back ALL variables from `TSEnvironment` and logs them. This gives SCCM administrators a single place (`smsts.log`) to see exactly what values were set, without digging through wizard output.

---

## ✨ Core Features

### 🔹 Parameter Validation

The wrapper immediately validates the two parameters that the wizard **cannot** function without:

```powershell
if ([string]::IsNullOrWhiteSpace($DomainName)) {
    Write-Log "DomainName is required" "ERROR"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($SearchBase)) {
    Write-Log "SearchBase is required" "ERROR"
    exit 1
}
```

These are the only two that cause a hard failure. Other parameters have reasonable defaults and won't block deployment. The check uses `IsNullOrWhiteSpace` rather than simple null check — empty strings, spaces, and nulls all cause the exit.

### 🔹 Path Resolution (3 Fallbacks)

Finding `DeploymentWizard.ps1` is harder than it sounds because the script may run in different execution contexts:

```powershell
$scriptRoot = if ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path      # Context 1: standard execution
} elseif ($PSScriptRoot) {
    $PSScriptRoot                                          # Context 2: PowerShell V3+ variable
} else {
    (Get-Location).Path                                    # Context 3: interactive / last resort
}
$wizardPath = Join-Path $scriptRoot "DeploymentWizard.ps1"

if (-not (Test-Path $wizardPath)) {
    Write-Host "[$ts] [ERROR] DeploymentWizard.ps1 not found at: $wizardPath"
    exit 1
}
```

**Context 1** (`$MyInvocation.MyCommand.Path`) — used when the script is launched normally. Most reliable.

**Context 2** (`$PSScriptRoot`) — PowerShell V3+ automatic variable. Works when `$MyInvocation` isn't available (e.g., dot-sourced scripts).

**Context 3** (`Get-Location`) — last resort. Only used if the first two fail (rare). Works interactively but can be wrong if the working directory changed.

### 🔹 Argument Forwarding

Every organization parameter is forwarded to the wizard as a CLI argument:

```powershell
$wizArgs = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wizardPath,
    "-CompanyName", $CompanyName, "-CompanyShort", $CompanyShort,
    "-Department", $Department, "-DomainName", $DomainName,
    "-SearchBase", $SearchBase, "-DomainController", $DomainController,
    "-SccmServer", $SccmServer, "-OrgName", $OrgName, "-DefaultLanguage", $DefaultLanguage
)
```

**The Software array problem:** PowerShell arrays don't serialize cleanly across process boundaries. If you pass `-Software @("a","b","c")`, the child process often receives a single concatenated string. The wrapper solves this by adding each `-Software` entry individually:

```powershell
foreach ($s in $Software) {
    $wizArgs += "-Software"
    $wizArgs += $s
}
# Result: -Software "entry1" -Software "entry2" -Software "entry3"
# This ensures each entry arrives as a separate string in the child process.
```

### 🔹 Exit Code Monitoring

The child process's exit code is checked via `$LASTEXITCODE`:

```powershell
& powershell.exe @wizArgs

if ($LASTEXITCODE -ne 0) {
    Write-Log "Wizard exited with code $LASTEXITCODE" "WARN"
}
```

Non-zero means the wizard crashed or the user cancelled. The wrapper logs it as a warning (not error — the TS step should decide if it's fatal).

### 🔹 Variable Verification

After the wizard exits, the wrapper reads back everything from `TSEnvironment` and logs it to `smsts.log`. This is the most valuable part of the wrapper — it provides a **single audit point** for every deployment:

```powershell
$tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment
Write-Log "--- Task Sequence Variables ---" "SUCCESS"
Write-Log "  OSDComputerName       = $($tsenv.Value('OSDComputerName'))"
Write-Log "  OSDDomainName         = $($tsenv.Value('OSDDomainName'))"
Write-Log "  OSDDomainOUName       = $($tsenv.Value('OSDDomainOUName'))"
Write-Log "  OSDJoinAccount        = $($tsenv.Value('OSDJoinAccount'))"
Write-Log "  OSDJoinPassword       = ********"              # Never logged
Write-Log "  OSDRegisteredOrgName  = $($tsenv.Value('OSDRegisteredOrgName'))"
foreach ($s in $Software) {
    $parts = $s -split '\|', 3
    Write-Log "  $($parts[1]) = $($tsenv.Value($parts[1]))"  # App_* variables
}
```

**Security note:** `OSDJoinPassword` is explicitly masked — it writes `********` instead of the actual password. The value is still in TSEnvironment (SCCM needs it), but it never appears in logs.

**TSEnvironment guard:** The entire read-back block is wrapped in try/catch. If the script runs outside SCCM (testing), the COM object won't exist, and the catch logs `"TSEnvironment not available - outside Task Sequence."` as a WARN instead of crashing.

### 🔹 Log Format

All output uses a consistent format prepended with a timestamp captured once at startup:

```
[2026-08-03 14:30:00] [INFO] Momar Tech - Deployment Wizard v1.0
[2026-08-03 14:30:00] [INFO] Domain      : momar.local
[2026-08-03 14:30:00] [INFO] SearchBase  : OU=Domain Computers,DC=Momar,DC=local
[2026-08-03 14:30:00] [SUCCESS] --- Task Sequence Variables ---
[2026-08-03 14:30:00] [SUCCESS]   OSDComputerName = WS-A100-25
[2026-08-03 14:30:00] [SUCCESS]   OSDJoinPassword = ********
[2026-08-03 14:30:00] [SUCCESS]   App_CiscoAnyConnect = TRUE
[2026-08-03 14:30:00] [SUCCESS] Deployment completed successfully.
```

All log entries appear in `smsts.log` on the SCCM site server, searchable by the machine name.

---

## ⚙️ Requirements

| Requirement | Minimum | Purpose |
|-------------|---------|---------|
| PowerShell | 5.1+ | Script execution + `New-ScheduledTask*` cmdlets |
| `DeploymentWizard.ps1` | Same `DeploymentWizard/` folder | Must ship in the same subfolder as the wrapper |
| SCCM/MECM | CB 1902+ | `Microsoft.SMS.TSEnvironment` COM interface |
| WinPE (if in WinPE) | 10.0.17763+ | WinPE-PowerShell (~45 MB), WinPE-NetFX (~195 MB) |

### SCCM Package Structure

The SCCM package must contain **both** scripts in the same `DeploymentWizard/` subfolder. The wrapper uses `$PSScriptRoot` to find the wizard — they must be siblings in the same directory:

```
SCCM Package Source Folder\
└── DeploymentWizard\               <-- Point SCCM to this folder
    ├── Start-DeploymentWizard.ps1  <-- TS step executes this
    └── DeploymentWizard.ps1        <-- Wrapper finds this via Join-Path
```

If the scripts are in different packages or different folders, the wrapper will exit with:
```
[ERROR] DeploymentWizard.ps1 not found at: <wrong-path>
```

---

## 🚀 How to Run

### Option 1 — SCCM Task Sequence Step (Production)

1. In the SCCM console, open your OSD task sequence
2. Add a **Run PowerShell Script** step in the desired position (typically after formatting the disk, before domain join)
3. Configure the step:
   - **Script name:** `Start-DeploymentWizard.ps1`
   - **Execution policy:** `Bypass`
   - **Timeout (minutes):** 30 or more (the wizard waits for user interaction)
4. Ensure the SCCM package referenced by the step contains both `.ps1` files
5. Optionally: check **Continue on error** if you want deployments to proceed even if the wizard fails

### Option 2 — Interactive Test (No TS)

```powershell
.\Start-DeploymentWizard.ps1
```

Runs with all Momar Tech defaults. Variables are written to TSEnvironment (if available) but the child process exits with the wizard's status. Useful for testing before packaging.

### Option 3 — Fully Customized

```powershell
.\Start-DeploymentWizard.ps1 -CompanyName "Contoso" -DomainName "contoso.com" `
    -SearchBase "OU=PCs,DC=contoso,DC=com" -DomainController "dc01.contoso.com" `
    -SccmServer "sccm.contoso.com" -OrgName "Contoso Ltd" -DefaultLanguage "en-US" `
    -Software "Chrome|App_Chrome|true","Firefox|App_Firefox|true","7-Zip|App_7Zip|false"
```

---

## ⚙️ Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-CompanyName` | `Momar Tech` | Forwarded to wizard. Appears in title, header, dialogs. |
| `-CompanyShort` | `MT` | Forwarded to wizard. Logo badge abbreviation (2-3 chars). |
| `-Department` | `IT Operations` | Forwarded to wizard. Header/footer subtitle. |
| `-DomainName` | `momar.local` | Forwarded to wizard. **Required** — exits 1 if empty. |
| `-SearchBase` | `OU=Domain Computers,DC=Momar,DC=local` | Forwarded to wizard. **Required** — exits 1 if empty. |
| `-DomainController` | `dc01.momar.local` | Forwarded to wizard. DC for LDAP + connectivity test. |
| `-SccmServer` | `sccm.momar.local` | Forwarded to wizard. SCCM MP for connectivity test. |
| `-OrgName` | `Momar Tech` | Forwarded to wizard. Written to `OSDRegisteredOrgName`. |
| `-DefaultLanguage` | `en-US` | Forwarded to wizard. Language selection (`en-US` / `ar-SA`). |
| `-Software` | `"Cisco AnyConnect VPN\|App_CiscoAnyConnect\|true"` | Forwarded to wizard. `Name\|TSVar\|DefaultChecked`. |

> **Note:** The wrapper does not use these values itself — it only validates `-DomainName` and `-SearchBase`, then forwards everything to the wizard.

---

## 🔄 Typical Workflow (Step by Step)

1. **Task sequence reaches the step** — SCCM runs `Start-DeploymentWizard.ps1` with the organization parameters (passed via the TS step's parameter field or defaults).

2. **Validation** — wrapper checks `-DomainName` and `-SearchBase` are not empty. If empty → exit `1` with error in `smsts.log`.

3. **Path resolution** — wrapper locates `DeploymentWizard.ps1` using the 3-fallback approach. If not found → exit `1`.

4. **Configuration log** — wrapper logs the organization settings: company name, domain, search base, DC, SCCM server.

5. **Launch** — wrapper constructs the argument array (includes the software array as individual `-Software` entries) and launches the wizard:
   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "DeploymentWizard.ps1" ...
   ```

6. **User interaction** — the WPF wizard appears, the technician fills in fields, clicks Deploy. The wizard writes to TSEnvironment and closes.

7. **Exit code check** — wrapper checks `$LASTEXITCODE`. Non-zero → logged as WARN.

8. **Variable read-back** — wrapper opens COM `TSEnvironment` and logs all values. Password is masked. Each `App_*` variable is logged individually.

9. **Completion** — wrapper exits `0` (success) or `1` (failure). The task sequence moves to the next step.

---

## 🚦 Exit Codes

| Code | Meaning | TS Behavior |
|------|---------|-------------|
| `0` | Wizard completed, all variables written and verified | Proceed to next step |
| `1` | Parameter missing, wizard not found, wizard crashed, or wizard cancelled | TS step fails (unless "Continue on error" is checked) |

---

## 📊 Operational Safeguards

- ✅ **Required-parameter validation** — exits early with a clear error message (no misleading downstream failures about missing values).
- ✅ **Wizard-file existence check** — exits early if `DeploymentWizard.ps1` is not in the same folder.
- 🔒 **Password masking** — `OSDJoinPassword` is replaced with `********` in logs. Never exposed.
- 🛟 **TSEnvironment guard** — the COM read-back is in try/catch. Running outside SCCM (testing) produces a warning, not a crash.
- 📝 **Consistent log format** — timestamp captured once at start, all entries follow `[TIMESTAMP] [LEVEL] Message`.
- 🔄 **Process isolation** — wizard runs in its own `powershell.exe`. A wizard crash cannot kill the task sequence step.

---

## 🐛 Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| **`[ERROR] DeploymentWizard.ps1 not found`** | Scripts are in different SCCM packages or folders | Both `.ps1` files MUST be in the same folder. The wrapper joins `$PSScriptRoot` + `DeploymentWizard.ps1`. |
| **`[ERROR] DomainName is required`** | Empty or missing `-DomainName` parameter | Pass `-DomainName "yourdomain.local"` in the TS step parameters or the command line. |
| **`[WARN] TSEnvironment not available`** | Running outside a Task Sequence | Expected for testing. Variables won't be consumed by SCCM but the wizard itself works. |
| **Step fails but wizard was fine** | TSEnvironment COM read-back failed | Check if the TS is running as SYSTEM (it should). Check `smsts.log` for COM errors. |
| **Wizard never appears** | WinPE missing required components | Add WinPE-PowerShell + WinPE-NetFX to the boot image. Update distribution points. Boot image must be the updated version. |
| **Variable not consumed by next step** | Step references wrong variable name | The wrapper logs exact variable names — check `smsts.log` for the real names. Use `App_*` format matching the software config. |
| **All App_* variables show empty** | Software list not forwarded correctly | The wrapper breaks each `-Software` entry out individually. Check the log for individual entries. |

---

## 🛡 Design Principles

- **Process isolation** — wizard runs as child; UI crash can't kill the task sequence. The wrapper reports the exit code and the TS step decides if it's fatal.
- **Execution policy Bypass** — both the wrapper and the child process use `Bypass`. No policy configuration needed on the deployed machine.
- **Fail-fast validation** — the wrapper checks the two required parameters and the wizard file existence before launching. Actionable error messages tell the admin what to fix.
- **Audit trail** — every variable written by the wizard is read back and logged to `smsts.log`. Single log line per deployment for troubleshooting.
- **Zero hardcoded branding** — the wrapper has no opinion about organization, domain, or software. Everything passes through as parameters.

---

## 📜 License

This project is licensed under the [MIT License](../LICENSE).

---

## 👤 Author

**Mohammad Abdulkader Omar**
Website: https://momar.tech
LinkedIn: https://www.linkedin.com/in/mabdulkadr/

---

## ⚠ Disclaimer

These scripts are provided as-is. Test them in a staging environment before applying them to production. The author is not responsible for any unintended outcomes resulting from their use.
