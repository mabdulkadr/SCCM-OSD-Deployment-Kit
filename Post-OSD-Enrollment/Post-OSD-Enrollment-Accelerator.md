# 🚀 Post-OSD Enrollment Accelerator

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)
![Account](https://img.shields.io/badge/Account-LOCAL%20SYSTEM-9C27B0.svg)
![Version](https://img.shields.io/badge/version-1.0-green.svg)

---

## 📖 Overview

**Post-OSD-Enrollment-Accelerator.ps1** is the **silent post-deployment provisioning engine** that runs at the end of an SCCM OSD Task Sequence, under the **LOCAL SYSTEM** account, with **zero user interaction**.

After the OS is laid down and the machine reboots into Windows, six critical steps must happen before the device is "fully managed." This script executes them in a carefully ordered, dependency-driven pipeline:

```
┌─────────────────────────────────────────────────────────┐
│ 1. TIME SERVICE    → Accurate time for Kerberos + TLS    │
│ 2. IPv6 DISABLE    → Adapter + registry (sets 3010 flag) │
│ 3. SCCM ACTIONS    → Policy, inventory, updates, apps    │
│ 4. ENTRA ID JOIN   → Hybrid Azure AD join prerequisite   │
│ 5. MDM ENROLLMENT  → Intune MDM auto-enrollment          │
│ 6. CO-MANAGEMENT   → Verify SCCM + Intune co-management  │
└─────────────────────────────────────────────────────────┘
```

Each step depends on the previous one. The script never halts the task sequence — failures are logged and execution continues.

> **Retry engine:** This script creates **no** scheduled tasks. The retry mechanism is delegated to [`Schedule-PostOSD-Enrollment.ps1`](Schedule-PostOSD-Enrollment.md), which registers a post-logon task that re-runs this script every 5 minutes for 30 minutes.

---

## 🏗 Architecture

### Execution Model

```
Post-OSD-Enrollment-Accelerator.ps1 (~400 lines)
├── param()                    # LogPath, TimeZone
├── Write-TSLog function       # Tab-separated logger
├── $RebootRequired = $false   # IPv6 change tracker
├── $ErrorActionPreference     # Continue — never halt
│
├── SECTION 1: Time Service    → Start w32time, sync from PDC, set TZ
├── SECTION 2: IPv6            → Disable adapter binding + registry
├── SECTION 3: SCCM Actions    → 8 action GUIDs + usoclient
├── SECTION 4: Entra ID Join   → dsregcmd /status → /join
├── SECTION 5: MDM Enrollment  → Tenant discovery → URLs → deviceenroller
├── SECTION 6: Co-Management   → 3-tier WMI/Registry/MDM detection
│
└── EXIT: 0 (complete) or 3010 (reboot needed for IPv6)
```

### Log Format

All output is written as tab-separated lines to `C:\IntuneLogs\PostOSDEnrollmentAccelerator.log`:

```
2026-08-03 14:30:01	INFO	=== Start (v1.0) | Machine: WS-A100-25 ===
2026-08-03 14:30:01	INFO	Repairing time service...
2026-08-03 14:30:05	INFO	Time service configured.
2026-08-03 14:30:05	INFO	Disabling IPv6...
2026-08-03 14:30:08	INFO	  Disabled IPv6 on adapter: Ethernet0
2026-08-03 14:30:08	INFO	IPv6 disabled on adapters and via registry (requires reboot).
2026-08-03 14:30:08	WARN	Note: Disabling IPv6 may break DirectAccess...
```

The `_SMSTSLogPath` variable (inside a TS) overrides `$LogPath`, routing logs to the SCCM log directory automatically.

---

## ✨ Core Features — Detailed Section Walkthrough

### 🔹 1. Time Service Repair

**Why first:** Kerberos authentication requires that the client clock is synchronized with the domain controller's clock (within a 5-minute skew). TLS certificate validation also depends on accurate time for checking NotBefore/NotAfter. If the BIOS clock is wrong after imaging, domain join and Entra authentication both fail.

**What happens:**

1. **Safety check** — queries `Win32_ComputerSystem.DomainRole`. If the machine is a Domain Controller (`>= 4`) or a server (`2` or `3`), the time section is skipped entirely. This script only touches workstations.

2. **w32time configuration:**
   - Starts the w32time service and sets startup to `Automatic`
   - Configures the NT5DS domain hierarchy (`w32tm /config /syncfromflags:domhier`)
   - Restarts the service and runs a forced resync (`w32tm /resync /force`)
   - Logs the current time source for diagnostics (`w32tm /query /source`)

3. **Auto time-zone detection:**
   - Configures `tzautoupdate` service via registry (`HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate\Start = 3`)
   - Starts the Location Service (`lfsvc`) if present (required for auto time zone on Windows 10/11 clients)

4. **Target time zone:**
   - Attempts `Set-TimeZone -Id $TimeZone` first (PowerShell cmdlet)
   - Falls back to `tzutil.exe /s $TimeZone` if the cmdlet fails (older PowerShell)

### 🔹 2. IPv6 Disable

**Why second:** IPv6 is independent of all other steps and is fast. It's also the primary source of the `3010` reboot flag, which affects how the scheduler handles reboots.

**What happens:**

1. **Adapter-level disable:**
   - Queries `Get-NetAdapter -Physical | Where-Object Status -eq 'Up'`
   - For each active physical adapter, calls `Disable-NetAdapterBinding -ComponentID ms_tcpip6`

2. **Registry-level disable:**
   - Sets `HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\DisabledComponents = 0xFF` (DWORD)
   - `0xFF` disables **all** IPv6 components: tunnel interfaces, transition technologies, loopback, all IPv6 traffic
   - The reboot flag (`$RebootRequired = $true`) is set **only if** the previous value was not already `0xFF`
   - This guard prevents repeated `3010` exits when the registry value is already set

3. **Warning:** A WARN log entry notes that disabling IPv6 may break DirectAccess, Always On VPN, and some modern Windows features.

### 🔹 3. SCCM Client Actions

**Why third:** These are fire-and-forget triggers. The SCCM client may not be fully initialized yet — that's intentional. The post-logon retry task on Schedule-PostOSD-Enrollment handles any actions that need to fire after the client is warm.

**What happens:**

Eight SCCM action cycles are triggered via the `[wmiclass]` accelerator (Windows PowerShell 5.1 only):

| GUID | Action | Purpose |
|------|--------|---------|
| `{00000000-0000-0000-0000-000000000121}` | App Deployment Eval | Check if assigned applications need installation |
| `{00000000-0000-0000-0000-000000000021}` | Machine Policy Eval | Download new policies (co-management, collections) |
| `{00000000-0000-0000-0000-000000000113}` | Software Updates Scan | Scan for missing updates against WSUS/SUP |
| `{00000000-0000-0000-0000-000000000108}` | SU Deployment Eval | Evaluate software update deployments |
| `{00000000-0000-0000-0000-000000000101}` | Hardware Inventory | Collect hardware data (model, serial, disk, memory) |
| `{00000000-0000-0000-0000-000000000102}` | Software Inventory | Collect installed software list |
| `{00000000-0000-0000-0000-000000000131}` | Compliance Eval | Evaluate configuration baselines |
| `{00000000-0000-0000-0000-000000000003}` | Discovery Data | Update the SCCM database with system info |

Each action is wrapped in its own try/catch — failure of one does not affect the others. A skipped action (SCCM client not ready) is logged as WARN.

After the 8 GUIDs:
- Refreshes update compliance via `Microsoft.CCM.UpdatesStore` COM object
- Kicks `usoclient.exe RefreshSettings` + `StartScan` to trigger the built-in Windows Update client

### 🔹 4. Entra ID (Hybrid Azure AD) Join

**Why fourth:** Entra ID join is the **gateway** to Intune MDM enrollment. If the device is not Entra-joined, the MDM section will fail because there's no tenant to enroll to.

**What happens:**

1. **Status check:**
   - Runs `dsregcmd.exe /status` and parses the output
   - Checks for `AzureAdJoined : YES` and `DomainJoined : YES`

2. **Three scenarios:**

   | State | Action |
   |-------|--------|
   | Already Entra-joined (`AzureAdJoined: YES`) | Logs success, skips to section 5 |
   | Domain-joined, not Entra-joined | Runs `dsregcmd /join /debug`, logs result |
   | Not domain-joined (`DomainJoined: NO`) | Logs WARN — hybrid join not applicable |

3. **The AAD Connect sync gap:** `dsregcmd /join` requests the join, but it can only complete after the computer's AD object is synced to Entra ID by **AAD Connect**. AAD Connect syncs every 30 minutes by default. The post-logon retry task (from the scheduler) re-runs this script every 5 minutes for 30 minutes, covering the full sync window.

### 🔹 5. MDM / Intune Enrollment

**Why fifth:** MDM enrollment requires two preconditions: the device must be Entra-joined (section 4) AND the `CloudDomainJoin\TenantInfo` registry key must exist with the tenant ID.

**What happens:**

1. **Tenant discovery:**
   - Reads `HKLM\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\*`
   - Extracts the tenant ID from the subkey name
   - The key path becomes `CloudDomainJoin\TenantInfo\<TenantID>`

2. **MDM URL configuration:**
   - Writes three registry values under the tenant key:
     ```
     MdmEnrollmentUrl  = https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc
     MdmTermsOfUseUrl  = https://portal.manage.microsoft.com/TermsofUse.aspx
     MdmComplianceUrl  = https://portal.manage.microsoft.com/?portalAction=Compliance
     ```

3. **Auto-enrollment policy:**
   - Sets `HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM\AutoEnrollMDM = 1` (DWORD)
   - This policy tells Windows it should automatically enroll in MDM when a tenant is available

4. **Trigger enrollment:**
   - Runs `deviceenroller.exe /c /AutoEnrollMDM`
   - The `/c` flag uses the configured URLs; `/AutoEnrollMDM` triggers auto-enrollment immediately
   - This process may take several minutes — the post-logon retry task covers it

5. **Graceful skip:** If the tenant info registry key doesn't exist (device not Entra-joined yet), the entire section is caught and logged as WARN.

### 🔹 6. Co-Management Verification

**Why last:** Co-management is the capstone. It confirms that both SCCM and Intune are managing the device. If co-management is active, the device is "fully managed."

**What happens — 3-tier detection:**

| Tier | Source | Reliability |
|------|--------|-------------|
| **Tier 1: WMI** | `Get-WmiObject -Namespace root\ccm\CoManagementHandler -Class CoManagement_Configuration` | Most reliable — directly from the SCCM client |
| **Tier 2: Registry** | `HKLM\SOFTWARE\Microsoft\CCM\CoMgmtSettings\ProductionType` | Fallback when WMI class isn't loaded yet |
| **Tier 3: MDM Policy** | `HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM\AutoEnrollMDM` | Indirect indicator — co-management may be pending |

If Tier 1 or Tier 2 confirms co-management → done.

If none of the tiers confirm co-management:
1. Force-triggers machine policy retrieval via `[wmiclass]` (GUID `{00000000-0000-0000-0000-000000000021}`)
2. Waits 30 seconds for policy to apply
3. Re-checks via WMI Tier 1
4. Logs final status (active or still not detected)

**Note:** Co-management requires server-side configuration in the SCCM console — the Cloud Attach wizard with workload sliders. This script only detects, it does not configure.

---

## ⚙️ Requirements

| Requirement | Notes |
|-------------|-------|
| Windows 10 / 11 | PowerShell 5.1 (built-in) |
| LOCAL SYSTEM account | The SCCM TS step runs as SYSTEM automatically |
| SCCM client installed | Required for sections 3 (actions) and 6 (co-mgmt detection). Distributed by the TS bootstrap. |
| AD domain membership | Required for sections 4 (Entra join) and 5 (MDM enrollment). Handled by the domain join TS step. |
| Network to DCs | Needed for Kerberos auth and Entra join (`dsregcmd /join`) |

### Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| `[wmiclass]` requires PowerShell 5.1 | Breaks on PS 7+ | Not an issue — SCCM TS always runs PS 5.1 |
| IPv6 disable breaks DirectAccess / Always On VPN | Machines using these can't reach IPv6 services | Don't disable IPv6 if you use these features |
| Co-management needs server-side config | Script detects but doesn't configure | Set up Cloud Attach in the SCCM console first |
| Hybrid join needs AAD Connect sync | May not complete within the TS runtime | Post-logon scheduler retries handle the sync gap |

---

## 🚀 How to Run

### Option 1 — Task Sequence (Production)

Add as the **final step** of your OSD task sequence, running as SYSTEM:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Post-OSD-Enrollment-Accelerator.ps1"
```

**Placement:**
- Must run AFTER domain join (the machine needs an AD object for Entra join)
- Must run AFTER the SCCM client is installed (for sections 3 + 6)
- Typically the absolute last step in the task sequence
- The scheduler (`Schedule-PostOSD-Enrollment.ps1`) should run **before** this step to register the retry tasks

### Option 2 — Custom Time Zone + Log Path

```powershell
.\Post-OSD-Enrollment-Accelerator.ps1 -LogPath "D:\PostOSDLogs" -TimeZone "Pacific Standard Time"
```

### Option 3 — Manually on a Deployed Machine (Troubleshooting)

```powershell
.\Post-OSD-Enrollment-Accelerator.ps1 -LogPath "C:\Temp" -TimeZone "Arab Standard Time"
```

---

## ⚙️ Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-LogPath` | `C:\IntuneLogs` | Directory for the tab-separated log file. Overridden by `_SMSTSLogPath` inside a Task Sequence. |
| `-TimeZone` | `Arab Standard Time` | Windows time zone ID. Use `tzutil /l` to list all available IDs on your system. |

---

## 🔄 Execution Order (with rationale)

| # | Section | Duration | Rationale |
|---|---------|----------|-----------|
| 1 | Time Service | ~5 sec | Kerberos requires clock sync (within 5 min skew). TLS certs need accurate time. Must be first. |
| 2 | IPv6 Disable | ~3 sec | Independent of all other steps. Fast. Sets the reboot flag early. |
| 3 | SCCM Actions | ~10 sec | Fire-and-forget. Triggers before the client may be fully ready — that's OK; retries happen later. |
| 4 | Entra ID Join | 1-5 min | Blocking dependency for MDM. Can only succeed after the AD computer object is synced to AAD. |
| 5 | MDM Enrollment | 1-5 min | Requires Entra join + CloudDomainJoin tenant info. Triggers auto-enrollment. |
| 6 | Co-Management | ~35 sec | Final verification. Confirms both SCCM and Intune are active. Re-checks after a policy refresh. |

---

## 📊 Operational Safeguards

- ✅ **`$ErrorActionPreference = 'Continue'`** — the script **never halts** the task sequence. All errors are caught and logged at their respective severity level.
- 🔄 **Reboot flag change detection** — `$RebootRequired` is set to `$true` only when the IPv6 registry value `DisabledComponents` changes from something other than `0xFF`. Prevents repeated `3010` exits on subsequent runs.
- 🛟 **Per-action WMI error handling** — each SCCM action GUID is in its own try/catch. A single failed action (e.g., client not ready) doesn't affect the other 7.
- 📝 **Structured tab-separated logging** — `INFO` / `WARN` / `ERROR` levels. Timestamps down to the second. Machine name logged at startup. Easy to parse with Excel or grep.
- 📍 **Graceful tenant discovery failure** — if the `CloudDomainJoin\TenantInfo` key doesn't exist (device not Entra-joined), the MDM section logs a WARN and the script continues to co-management.
- 🖥 **PCs-only time safety** — DCs and servers are detected via `DomainRole` and the time section is skipped (you shouldn't change time settings on a domain controller from a random workstation deployment).

---

## 🚦 Exit Codes

| Code | Meaning | Scheduler Reaction |
|------|---------|--------------------|
| `0` | All sections completed. No reboot needed. | Scheduler considers the run "done." The accelerator exits, the retry task continues its interval, the next run will be a no-op (everything already configured). |
| `3010` | IPv6 registry value changed. Reboot required. | The scheduler's wrapper checks `$LASTEXITCODE -eq 3010` AND the `RebootDone.flag` file. If no flag exists, it writes the flag and triggers `shutdown /r /t 60`. After reboot, subsequent runs will exit `0` (registry value already `0xFF`). |

---

## 📁 Log Output

```
C:\IntuneLogs\
 ├── PostOSDEnrollmentAccelerator.log   ← This script's action log (tab-separated)
 └── PostOSDScheduler.log               ← Scheduler registration log (tab-separated)
```

When running inside a Task Sequence, `_SMSTSLogPath` redirects both logs to the SCCM log directory (e.g., `C:\Windows\CCM\Logs\`).

---

## 🐛 Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| **`[WARN] SMS_Client trigger fails`** | SCCM client service not started yet | Expected — retries happen via the post-logon scheduler. Check after 5-10 minutes. |
| **`Cannot load type [wmiclass]`** | Running in PowerShell 7+ | SCCM TS always runs Windows PowerShell 5.1. Running manually? Use `powershell.exe` (not `pwsh.exe`). |
| **Hybrid join never completes** | AAD Connect hasn't synced the AD computer object | AAD Connect syncs every 30 min. The post-logon retry covers the full window. Manually: `dsregcmd /join` as SYSTEM. |
| **MDM section skipped** | No `CloudDomainJoin\TenantInfo` in registry | Device isn't Entra-joined. This section will work after section 4 succeeds. |
| **Co-management "Not Detected"** | Co-management not configured in SCCM console | Set up Cloud Attach in the SCCM console. Without that, the SCCM client can't receive co-management policies. |
| **Repeated 3010 exits** (reboot loop) | `RebootDone.flag` guard file already present but `DisabledComponents` still changing | Verify `DisableComponents` is set to `0xFF` in `HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters`. Remove the flag file if needed. |
| **Time service repair logs "skipped"** | Machine detected as DC or Server | Expected — the script only configures time on workstations. |

---

## 🛡 Design Principles

- **Silent + SYSTEM-safe** — no user interface, no prompts. Runs entirely in the SYSTEM context.
- **Dependency-driven ordering** — sections are ordered by prerequisites. Time first (everything needs it), co-management last (needs everything else to succeed).
- **Failures are logged, never fatal** — `$ErrorActionPreference = 'Continue'`. Every try/catch is scoped to a single operation.
- **No in-script scheduled tasks** — all retry logic is delegated to `Schedule-PostOSD-Enrollment.ps1`. This keeps the accelerator simple and testable independently.
- **Reboot guard flag** — single-source-of-truth for reboot state. Prevents infinite reboot loops even with multiple 3010 exits.
- **PS 5.1 compatible** — uses `[wmiclass]` accelerator (not available in PS 7+) because SCCM TS always runs PS 5.1. Safe.

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
