# 📐 Technical Architecture

This document covers the internal architecture of the SCCM OSD Deployment Kit. It explains **how** the toolkit works under the hood — for users who want to understand, modify, or troubleshoot the scripts.

> **Most users don't need this.** Start with the [main README](../README.md) and per-module docs. Come back here when you need deeper understanding.

---

## 🏗 High-Level Architecture

```
SCCM OSD Deployment Kit
        │
        ├── Phase 0: Pre-Staging (SCCM-OSD-PreStaging/)
        │       └── Standalone WPF GUI for helpdesk operators
        │
        ├── Phase 1: Deployment Wizard (DeploymentWizard/)
        │       ├── Start-DeploymentWizard.ps1 (TS wrapper)
        │       └── DeploymentWizard.ps1 (WPF application)
        │
        └── Phase 2: Post-OSD Enrollment (Post-OSD-Enrollment/)
                ├── Schedule-PostOSD-Enrollment.ps1 (scheduler)
                └── Post-OSD-Enrollment-Accelerator.ps1 (engine)
```

Each phase is **independent** — they share no code, only data flow through TSEnvironment variables.

---

## 📁 File Organization

```
SCCM-OSD-Deployment-Kit/
├── README.md                              ← Project overview
├── autounattend.xml                       ← Windows OOBE bypass
├── autounattend.md
├── Remove-StaleADComputer.ps1             ← WinPE: cleans stale AD objects
├── technical-architecture.md              ← This file
│
├── DeploymentWizard/
│   ├── Start-DeploymentWizard.ps1         ← TS entry point (wrapper)
│   ├── DeploymentWizard.ps1               ← WPF wizard application
│   ├── DeploymentWizard.md
│   └── Start-DeploymentWizard.md
│
├── Post-OSD-Enrollment/
│   ├── Schedule-PostOSD-Enrollment.ps1    ← Retry + cleanup scheduler
│   ├── Post-OSD-Enrollment-Accelerator.ps1← 6-section provisioning engine
│   ├── Post-OSD-Enrollment-Accelerator.md
│   └── Schedule-PostOSD-Enrollment.md
│
├── SCCM-OSD-PreStaging/
│   ├── SCCM-OSD-PreStaging.ps1            ← WPF GUI
│   ├── SCCM-OSD-PreStaging.md
│   ├── README.md
│   └── Helpdesk OSD Pre-Staging Operator.xml ← RBAC role
│
└── Report/
    ├── Get-OSDDeploymentReport.ps1        ← HTML reports
    ├── Send-QUExchangeMail.psm1           ← Graph API email module
    ├── Get-OSDDeploymentReport.md
    └── Send-QUExchangeMail.md
```

---

## 🔀 Data Flow

### Deployment Wizard

```
User Input (WPF Controls)
    │
    ├─ UsernameBox + PasswordBox ────────────▶ AD Authentication
    ├─ ComputerNameBox ──────────────────────▶ OSDComputerName
    ├─ OUDataGrid (LDAP browse) ─────────────▶ OSDDomainOUName
    ├─ SoftwarePanel (checkboxes) ───────────▶ App_* variables
    └─ Language radio ───────────────────────▶ OSDLanguage
    │
    ▼
Validation (Deploy button)
    │
    ▼
Write-SCCMVariables → COM Microsoft.SMS.TSEnvironment
    │
    ▼
Downstream TS steps consume the variables automatically
```

### Post-OSD Enrollment

```
TS ends → Schedule-PostOSD-Enrollment.ps1 runs
    │
    ├─ Copies accelerator to C:\Windows\Temp\PostOSD\
    ├─ Registers PostOSD-Enrollment task (AtLogOn, every 5 min × 30 min)
    └─ Registers PostOSD-Cleanup task (once at +35 min)
    │
    ▼
TS continues → Post-OSD-Enrollment-Accelerator.ps1 runs once in TS context
    │
    ▼
Machine reboots → AutoLogon → PostOSD-Enrollment fires
    │
    ├─ Accelerator runs (6 sections in dependency order)
    ├─ If exit 3010 + no flag → reboot (single reboot guard)
    └─ Repeats every 5 min until T+30
    │
    ▼
T+35 → PostOSD-Cleanup fires
    │
    └─ Deletes both tasks + copied script + flag
```

### Pre-Staging Tool

```
Operator enters device details → clicks Pre-Stage
    │
    ├─ POST ImportMachineEntry (MAC + Name → ResourceID)
    ├─ GET SMS_R_System (verify record exists)
    └─ POST SMS_MachineSettings (inject 8+ OSD variables)
    │
    ▼
Device is PXE-ready in SCCM
```

---

## 🧠 Deployment Wizard State Machine

| State | Trigger | Next State |
|-------|---------|------------|
| **Loaded** | Window opens | Anonymous LDAP attempt → READY |
| **READY** | OU list loaded (or "Sign in to load" if anonymous failed) | User clicks Sign In → AUTH |
| **AUTH** | Credential check | Success → AUTHENTICATED / Fail → READY (or LOCKED after 5 fails) |
| **AUTHENTICATED** | OUs loaded with credentials | User fills form → VALIDATED |
| **VALIDATED** | Deploy clicked | Write TS variables → Result dialog → CLOSED |
| **LOCKED** | 5 failed auth attempts | Must restart wizard |

---

## � Credential Flow

```
PasswordBox.Password
    │
    ├─ [Sign In] → PrincipalContext.ValidateCredentials
    │     │
    │     ├─ Success → $script:JoinPass = password (in-memory only)
    │     │
    │     └─ Update-OUList (LDAP bind with NetworkCredential)
    │
    └─ [Deploy] → Write-SCCMVariables
            │
            └─ TSEnvironment:
                  OSDJoinAccount   = domain\user
                  OSDJoinPassword  = password (hidden)
                  OSDComputerName  = name
                  OSDDomainOUName  = selected OU DN
                  OSDLanguage      = en-US | ar-SA
                  OSDRegisteredOrgName = org name
                  App_*            = TRUE / not set
```

**Security guarantees:**

- Password only stored in `$script:JoinPass` (memory only, never disk)
- `OSDJoinPassword` is a hidden TS variable (masked in `smsts.log`)
- 5-attempt lockout prevents brute force
- Credentials reused for authenticated LDAP bind

---

## 📡 LDAP Browsing in WinPE

Traditional `DirectorySearcher` (ADSI COM) **does not work** in WinPE because the COM object can't be instantiated.

**Solution:** Use `System.DirectoryServices.Protocols.LdapConnection` — pure .NET TCP socket, no COM dependency.

| | DirectorySearcher | LdapConnection |
|---|---|---|
| Works in WinPE? | ❌ No | ✅ Yes |
| Underlying tech | ADSI COM | Pure .NET |
| Bind | Implicit | Explicit (anonymous or credentialed) |

### Bind Strategy

```
Window.Loaded
    │
    ├─ Not logged in → try anonymous bind
    │     ├─ Success → OUs loaded
    │     └─ Fail (typical in WinPE) → "Sign in to load OUs"
    │
    └─ After sign-in → re-bind with NetworkCredential
          └─ Authenticated OU list loaded into DataGrid
```

---

## 🔧 Deployment Wizard Functions

| Function | Purpose |
|----------|---------|
| `New-Brush` | Creates frozen `SolidColorBrush` from hex color |
| `Write-UiLog` | Thread-safe color-coded Message Center entry |
| `Show-AuthBanner` / `Hide-AuthBanner` | Display/clear auth status banner |
| `Show-CustomDialog` | Styled modal dialog with MessageBox fallback |
| `Test-TcpReach` | Async TCP port connectivity test |
| `ConvertTo-FriendlyOUPath` | DN → "Top / Parent / Child" path |
| `Update-OUList` | LDAP bind + DataGrid population |
| `Filter-OUDataGrid` | Client-side live search |
| `Update-Summary` | Refresh summary pills (green/red backgrounds) |
| `Test-ADAuthentication` | `PrincipalContext.ValidateCredentials` wrapper |
| `Write-SCCMVariables` | Writes all 8+ variables to TSEnvironment |

---

## 🎨 Design System

### Color Palette

| Role | Hex | Usage |
|------|-----|-------|
| Navy | `#031926` | Header, Computer/Software/Message Center accents |
| Gold | `#C9A23D` | Logo badge, Auth/OU/Summary accents |
| Green | `#28A745` | Success states, Deploy button |
| Red | `#DC3545` | Error states |
| Orange | `#F59E0B` | Warning states |
| SoftBlue | `#EEF2FF` | Software panel, selected OU |
| PageBg | `#F6F8FB` | Window background |
| Border | `#E4E9F0` | Card borders |

### Component Specs

- Cards: 5px border radius, white background, `#E4E9F0` border
- Buttons: 28px height, SemiBold, 12px font
- DataGrid: 140px height, horizontal scrollbar auto
- Message Center: dark background, Consolas 11px, `[LEVEL]` prefix

---

## 🐛 Error Handling Strategy

| Scenario | Detection | Response |
|----------|-----------|----------|
| Empty credentials | `Test-ADAuthentication` | Red auth banner |
| Wrong credentials | `ValidateCredentials` returns false | Red auth banner |
| DC unreachable | Exception | Red banner: "Cannot reach domain" |
| 5 failed attempts | `AuthAttempts ≥ 5` | Sign In permanently disabled |
| Anonymous LDAP fails (WinPE) | `Update-OUList` exception | Orange: "Sign in to load OUs" |
| XAML rendering fails (WinPE) | try/catch on dialogs | MessageBox fallback |
| TSEnvironment unavailable | COM creation fails | Warning: "Not inside Task Sequence" |
| Wizard file missing | `Test-Path` check | Exit 1 with error log |
| Invalid parameters | `IsNullOrWhiteSpace` check | Exit 1 with error log |

---

## 💻 WinPE Requirements

The Deployment Wizard requires these Boot Image Optional Components:

| Component | Size | Why Needed |
|-----------|------|------------|
| WinPE-NetFx | ~195 MB | WPF, AD auth, LDAP protocols |
| WinPE-PowerShell | ~45 MB | PowerShell script execution |

**Without these components, the wizard cannot render or authenticate in WinPE.**

### How to Add

1. **SCCM Console → Software Library → Boot Images**
2. Right-click boot image → **Properties**
3. **Optional Components** tab → **Add**
4. Select both components → OK
5. **Update Distribution Points**

---

## 🔐 Post-OSD Scheduler Internals

The scheduler registers two Windows Task Scheduler tasks:

### PostOSD-Enrollment (Retry)

| Property | Value |
|----------|-------|
| Principal | SYSTEM, RunLevel Highest |
| Trigger | AtLogOn + Repetition (5 min × 30 min) |
| Action | `powershell.exe` → run accelerator + handle 3010 |
| ExecutionTimeLimit | 20 minutes |
| MultipleInstances | IgnoreNew |

### PostOSD-Cleanup (Self-Destruct)

| Property | Value |
|----------|-------|
| Principal | SYSTEM, RunLevel Highest |
| Trigger | Once, 35 minutes after registration |
| Action | Unregister both tasks + delete copied scripts |

### Reboot Guard

The accelerator can exit `3010` (reboot needed for IPv6). The wrapper checks:

```powershell
if ($LASTEXITCODE -eq 3010 -and -not (Test-Path 'RebootDone.flag')) {
    Set-Content RebootDone.flag -Value (Get-Date)
    shutdown /r /t 60
}
```

This ensures **exactly one reboot** per deployment — no infinite loops.

---

## 🛡 Design Principles

1. **Self-contained** — No external binaries, modules, or XML configs required
2. **PowerShell 5.1 only** — Compatible with SCCM TS environment
3. **WinPE-safe** — Pure .NET, no COM dependencies, MessageBox fallbacks
4. **Process isolation** — Wizard runs in child process; UI crash can't kill TS
5. **Idempotent** — Safe to run multiple times
6. **Self-cleaning** — Post-OSD scheduler removes itself and all artifacts
7. **Parameter-driven** — Every org-specific value is a parameter
8. **Least privilege** — RBAC role grants only the permissions needed
9. **Dependency-ordered** — Post-OSD sections run in strict prerequisite order
10. **Observable** — Tab-separated logs, color-coded UI, full TS variable readback

---

## 📜 License

This project is licensed under the [MIT License](../LICENSE).

---

## � Author

**Mohammad Abdulkader Omar**
Website: [momar.tech](https://momar.tech) · LinkedIn: [linkedin.com/in/mabdulkadr](https://www.linkedin.com/in/mabdulkadr/)
