# 🚀 SCCM OSD Deployment Kit v1.0

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)
![GUI](https://img.shields.io/badge/GUI-WPF-purple.svg)
![SCCM](https://img.shields.io/badge/SCCM-MECM%20CB%201902%2B-orange.svg)
![Version](https://img.shields.io/badge/version-1.0-green.svg)

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-☕-FFDD00?style=for-the-badge)](https://www.buymeacoffee.com/mabdulkadrx)

---

## 📖 Overview

**SCCM OSD Deployment Kit** transforms SCCM's traditional **zero-touch** OSD into a **user-driven** deployment experience. Built for IT support teams to simplify and accelerate Windows 11 installation across the organization — with interactive wizards that collect device details before deployment, eliminating manual post-install configuration.

The toolkit covers **three deployment scenarios** that address every support situation:

| Scenario | Situation | How It Works |
|----------|-----------|-------------|
| **On-Site Installation** | Empty device (no OS), technician physically present | Technician boots from media → interactive wizard appears → enters computer name, selects OU, picks software → system completes installation, drivers, and domain join automatically |
| **Remote Deployment** | Technician at desk, employee at a remote location | Technician runs pre-staging tool from office → registers MAC + OU + software in SCCM via AdminService REST API → instructs employee to boot from network → full deployment happens remotely |
| **In-Place Upgrade** | Existing OS needs upgrade to 25H2, preserving files and apps | System auto-detects current UI language (Arabic/English) → pulls and runs the matching upgrade files silently — zero manual intervention |

### The Problem This Solves

Traditional SCCM zero-touch deployments are rigid — the same image goes to every device with no room for technician input. This toolkit adds **interactive WPF wizards** at critical points in the task sequence, letting support staff personalize each deployment: computer name, organizational unit, domain join credentials, and application selection — all before a single file is copied.

### Architecture

Each module is self-contained: its script, documentation, and supporting files live together in a single folder. No cross-folder dependencies, no scattered files.

```
                   SCCM OSD Deployment Kit
                          │
     ┌────────────────────┼────────────────────┐
     │                    │                    │
     ▼                    ▼                    ▼
┌─────────┐     ┌──────────────┐      ┌──────────────┐
│  PHASE 0│     │   PHASE 1    │      │   PHASE 2    │
│Pre-Stage│───▶│  Deployment  │─────▶│ Post-Deploy  │
│ (remote)│     │ (on-site OSD)│      │ (provision)  │
└─────────┘     └──────────────┘      └──────────────┘
     │                    │                    │
SCCM-OSD-           DeploymentWizard/   Post-OSD-
PreStaging/         ├── .ps1 + .ps1     Enrollment/
                    └── .md  + .md      ├── .ps1 + .ps1
                                        └── .md  + .md
```

---

## ⚙️ Configuration Required

> **Before using any script**, replace the placeholders below with your organization's actual values.

| Placeholder | Where | What to put |
|---|---|---|
| `<YOUR_TENANT_ID>` | Report scripts | Azure AD tenant GUID |
| `<YOUR_CLIENT_ID>` | Report scripts | Azure AD app client GUID |
| `<YOUR_CLIENT_SECRET>` | Report scripts | Azure AD app secret |
| `<YOUR_SERVICE_EMAIL>` | Report scripts | Sender mailbox (Graph API) |
| `<YOUR_EMAIL>` | Report scripts | Primary recipient email |
| `<ADMIN_EMAIL>` | Report examples | Admin mailbox |
| `<HELPDESK_EMAIL>` | Report examples | Helpdesk mailbox |
| `-DefaultLanguage` | All scripts | OS language (`en-US` / `ar-SA`) |
| `<YOUR_DOMAIN>` | Docs / email | Your domain (e.g. `contoso.com`) |
| `<YOUR_TENANT>` | Docs | Your Microsoft 365 tenant name |
| `Momar Tech` | All scripts | Your organization name |
| `MT` | All scripts | Your 2-3 char org code |
| `momar.local` | All scripts | Your AD domain FQDN |
| `DC=Momar,DC=local` | All scripts | Your LDAP search base DN |
| `dc01.momar.local` | All scripts | Your domain controller FQDN |
| `sccm.momar.local` | DeploymentWizard | Your SCCM MP FQDN |
| `SCCM.Momar.local` | PreStaging | Your SCCM AdminService FQDN |
| `MT1` | All scripts | Your SCCM site code |
| `10.0.0.11` - `14` | Remove-StaleADComputer | Your DC IP addresses |

---

## 🗂 Folder Structure

```
SCCM-OSD-Deployment-Kit/
│
├── README.md                               # 📖 This file
├── autounattend.xml                        # 📄 Win11 OOBE bypass answer file
├── autounattend.md                         # 📖 Unattend documentation
├── technical-architecture.md               # 📐 Full architecture reference
│
├── DeploymentWizard/                       # 🖥 Phase 1 — Interactive OSD Wizard
│   ├── Start-DeploymentWizard.ps1          # 🚀 SCCM TS wrapper (validates, launches, verifies)
│   ├── Start-DeploymentWizard.md           # 📖 Wrapper architecture doc
│   ├── DeploymentWizard.ps1                # 🖥 WPF wizard (~1550 lines, 12 functions)
│   └── DeploymentWizard.md                 # 📖 Wizard architecture + deep dive
│
├── Post-OSD-Enrollment/                    # 🔁 Phase 2 — Silent Post-Deployment
│   ├── Schedule-PostOSD-Enrollment.ps1     # ⏰ Self-cleaning retry scheduler
│   ├── Schedule-PostOSD-Enrollment.md      # 📖 Scheduler lifecycle + timeline doc
│   ├── Post-OSD-Enrollment-Accelerator.ps1 # 🔁 6-section provisioning engine
│   └── Post-OSD-Enrollment-Accelerator.md  # 📖 Accelerator 6-section deep dive
│
├── SCCM-OSD-PreStaging/                    # ⚙️ Phase 0 — Off-Site Pre-Staging
│   ├── SCCM-OSD-PreStaging.ps1             # 🖥 WPF GUI (AdminService REST API)
│   ├── SCCM-OSD-PreStaging.exe             # 📦 Compiled EXE (PSWrap, self-signed)
│   ├── SCCM-OSD-PreStaging.md              # 📖 REST API + SSL architecture doc
│   ├── README.md                           # 📖 Quick-reference README
│   └── Helpdesk OSD Pre-Staging Operator.xml # 🔐 SCCM RBAC role (Create + OSD Variables)
│
├── Report/                                 # 📊 Deployment reporting & email
│   ├── Get-OSDDeploymentReport.ps1         # 🚀 OSD deployment status report
│   ├── Send-QUExchangeMail.psm1            # 📧 Graph API email module
│   └── Send-QUExchangeMail.md              # 📖 Email module documentation
│
└── Remove-StaleADComputer.ps1             # 🧹 WinPE script — delete stale AD computer objects
```

---

## ✨ Core Features

### 🔹 Phase 1 — Deployment Wizard (`DeploymentWizard/`)

The interactive **WPF wizard** appears during the OSD task sequence to collect deployment parameters. Each `.ps1` file has a matching `.md` documentation file in the same folder.

**`Start-DeploymentWizard.ps1` — TS Wrapper:**
- Validates required parameters (`-DomainName`, `-SearchBase`) — fail-fast exit on empty
- Resolves `DeploymentWizard.ps1` path with 3 fallbacks for different execution contexts
- Launches the wizard in a child `powershell.exe` process — UI crash can't kill the TS
- Forwards each `-Software` entry individually (arrays don't serialize well across process boundaries)
- Reads back all TS variables, masks `OSDJoinPassword`, logs everything to `smsts.log`

**`DeploymentWizard.ps1` — WPF Application:**
- AD authentication via `PrincipalContext.ValidateCredentials` with 5-attempt lockout
- LDAP OU browser via pure .NET `LdapConnection` — no ADSI COM, works in WinPE
- Live search DataGrid, breadcrumb paths, selected-OU indicator with green/red backgrounds
- Dynamic software checkboxes from `-Software` parameter → `App_*` TS variables
- Writes 8+ variables via COM `Microsoft.SMS.TSEnvironment`
- WinPE-safe: MessageBox fallback when XAML rendering fails
- 12 functions, 6 event handlers, single-file XAML+code embedded architecture

> 📖 Docs: [`DeploymentWizard/DeploymentWizard.md`](DeploymentWizard/DeploymentWizard.md) · [`DeploymentWizard/Start-DeploymentWizard.md`](DeploymentWizard/Start-DeploymentWizard.md)

### 🔹 Phase 2 — Post-OSD Enrollment (`Post-OSD-Enrollment/`)

Silent, SYSTEM-context provisioning at task sequence completion — zero user interaction.

**`Schedule-PostOSD-Enrollment.ps1` — Retry + Cleanup Scheduler:**
- Copies the accelerator to `C:\Windows\Temp\PostOSD\` (outside ephemeral SCCM package cache)
- Registers `PostOSD-Enrollment` task: AtLogOn trigger, repeats every 5 min × 30 min
- One-time reboot guard: `RebootDone.flag` ensures exactly 1 reboot on exit `3010`
- Registers `PostOSD-Cleanup` task: fires at +35 min, deletes both tasks + script copies + markers
- Idempotent — skips if already registered; always exits `0` (never blocks TS)

**`Post-OSD-Enrollment-Accelerator.ps1` — 6-Section Provisioning Engine:**
1. **Time Service** — w32time sync from PDC, set time zone (PCs-only safety skip)
2. **IPv6 Disable** — adapter binding + registry `0xFF`, reboot flag only on actual change
3. **SCCM Actions** — 8 standard action GUIDs + `usoclient.exe` refresh
4. **Entra ID Join** — `dsregcmd /status` → `/join`, covers AAD Connect sync gap
5. **MDM Enrollment** — tenant discovery, URL config, `AutoEnrollMDM`, `deviceenroller.exe`
6. **Co-Management** — 3-tier detection (WMI → Registry → MDM policy) + 30s re-check

> 📖 Docs: [`Post-OSD-Enrollment/Post-OSD-Enrollment-Accelerator.md`](Post-OSD-Enrollment/Post-OSD-Enrollment-Accelerator.md) · [`Post-OSD-Enrollment/Schedule-PostOSD-Enrollment.md`](Post-OSD-Enrollment/Schedule-PostOSD-Enrollment.md)

### 🔹 Phase 0 — Pre-Staging Tool (`SCCM-OSD-PreStaging/`)

Remote helpdesk operators register bare-metal devices **before they arrive** — no SCCM console required.

- WPF GUI connecting to **SCCM AdminService REST API** over HTTPS
- 3-step API flow: `ImportMachineEntry` → verify `SMS_R_System` → inject `SMS_MachineSettings`
- **C# compiled SSL bypass** — works in compiled EXEs where PowerShell script-block callbacks fail
- TLS 1.2 applied at startup + before every API call (double-hardened)
- AD authentication, LDAP OU browser, dynamic software checkboxes with TS variable tooltips
- MAC auto-formatting + regex validation, 15-char name limit
- Full-detail WPF confirmation dialog before sending to SCCM
- Auto-clear fields after success, retry prompt on failure (2 attempts)
- **Compiled EXE** available — double-click, no PowerShell console needed
- **RBAC Role** (`Helpdesk OSD Pre-Staging Operator.xml`) — import into SCCM to grant operators Create + Read + Set OSD Variables permissions (least-privilege, no admin rights needed)

> 📖 Docs: [`SCCM-OSD-PreStaging/SCCM-OSD-PreStaging.md`](SCCM-OSD-PreStaging/SCCM-OSD-PreStaging.md) · [`SCCM-OSD-PreStaging/README.md`](SCCM-OSD-PreStaging/README.md)

### 🔹 Windows Unattend (`autounattend.xml`)

Minimal answer file for zero-touch Windows 11 Setup:
- **specialize pass** — `BypassNRO = 1`, removes network requirement
- **oobeSystem pass** — hides EULA, OEM registration, Microsoft account, wireless setup
- Auto-discovered by Windows Setup at the media root — no command-line parameter needed

> 📖 Docs: [`autounattend.md`](autounattend.md)

### 🔹 Technical Architecture (`technical-architecture.md`)

Full internal reference: data-flow diagrams, state machine, 12-function index, LDAP architecture, color palette, WinPE requirements, error handling matrix, performance benchmarks.

> 📖 Docs: [`technical-architecture.md`](technical-architecture.md)

---

## ⚙️ Requirements

| Requirement | Minimum | Notes |
|-------------|---------|-------|
| PowerShell | 5.1+ | Built into Windows 10/11. SCCM TS always runs PS 5.1. |
| .NET Framework | 4.6.2+ | WPF, AD auth, LDAP |
| SCCM/MECM | CB 1902+ | `Microsoft.SMS.TSEnvironment` COM interface |
| WinPE | 10.0.17763+ | WinPE-PowerShell (~45 MB) + WinPE-NetFX (~195 MB) |
| AD Domain | Line-of-sight to DC | Auth, LDAP, domain join. Ports 389, 88, 445. |
| SCCM AdminService | HTTPS on SMS Provider | **Only for Pre-Staging Tool** |

---

## 🚀 How to Run

### Scenario 1 — On-Site Installation (New Device)

The technician boots the empty device from installation media. The interactive wizard appears in WinPE to collect deployment details.

| Step | Script | Folder | Account | Purpose |
|------|--------|--------|---------|---------|
| 1 | `Start-DeploymentWizard.ps1` | `DeploymentWizard/` | SYSTEM | Launch WPF wizard (30 min timeout) |
| 2 | Domain join + App installs | — | — | Consumes OSD variables |
| 3 | `Schedule-PostOSD-Enrollment.ps1` | `Post-OSD-Enrollment/` | SYSTEM | Install retry + cleanup tasks |
| 4 | `Post-OSD-Enrollment-Accelerator.ps1` | `Post-OSD-Enrollment/` | SYSTEM | Time → IPv6 → SCCM → Entra → MDM → Co-mgmt |

### Scenario 2 — Remote Deployment (Pre-Staging)

The technician registers the device from their office. The employee boots from network at the remote location.

```powershell
# Technician runs from office:
.\SCCM-OSD-PreStaging\SCCM-OSD-PreStaging.ps1
# Or double-click:
.\SCCM-OSD-PreStaging\SCCM-OSD-PreStaging.exe
```

### Scenario 3 — In-Place Upgrade

The task sequence auto-detects the current system language and pulls the matching upgrade files. No user interaction needed.

### Test Run (Interactive)

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\DeploymentWizard\Start-DeploymentWizard.ps1
```

---

## 📦 SCCM Package Setup

Before using the Task Sequence, you must create and distribute the SCCM package:

| Property | Value |
|----------|-------|
| **Package Name** | `SCCM-OSD-Deployment-Kit` |
| **Package ID** | `QU100100` |
| **Version** | `1.0` |
| **Location** | Software Library → Application Management → Packages |

### Package Contents

The package contains all files used during OSD:

| File | Purpose |
|------|---------|
| `Start-DeploymentWizard.ps1` | Launch WPF wizard (TS entry point) |
| `DeploymentWizard.ps1` | WPF wizard application |
| `Remove-StaleADComputer.ps1` | Delete stale AD computer objects |
| `Schedule-PostOSD-Enrollment.ps1` | Register retry + cleanup tasks |
| `Post-OSD-Enrollment-Accelerator.ps1` | 6-section provisioning engine |
| `autounattend.xml` | Windows Setup answer file |

### Distribution

After creating the package:

1. **Distribute Content** to all Distribution Points
2. Verify **Content Status** shows **Success** before using the Task Sequence

---

## 🔄 Complete Task Sequence

### Phase 1 — Pre-Deployment

| Step | Script/Action | Purpose |
|------|---------------|---------|
| 1 | `Start-DeploymentWizard.ps1` | Launch WPF wizard — collect computer name, OU, software, language, domain credentials |
| 2 | `Remove-StaleADComputer.ps1` | Delete stale AD computer object with the same name |

**Task Sequence Variables Generated:**

| Variable | Source | Used In |
|----------|--------|---------|
| `OSDComputerName` | Wizard input | Windows Settings, Domain Join |
| `OSDDomainName` | `-DomainName` param | Domain Join |
| `OSDDomainOUName` | Selected OU DN | Domain Join |
| `OSDJoinAccount` | Credentials | Domain Join |
| `OSDJoinPassword` | Credentials (hidden) | Domain Join |
| `OSDRegisteredOrgName` | `-OrgName` param | Windows Settings |
| `OSDLanguage` | Language picker | OS Image Selection |
| `App_*` | Checked checkboxes | Application Installation |

### Phase 2 — Install Operating System

| Step | Action | Condition |
|------|--------|-----------|
| 1 | **Restart in Windows PE** | Always |
| 2 | **Partition Disk 0 - BIOS** | Legacy BIOS |
| 3 | **Partition Disk 0 - UEFI** | UEFI (creates EFI, MSR, Windows, Recovery) |
| 4 | **Apply OS English** | `OSDLanguage equals "en-US"` |
| 5 | **Apply OS Arabic** | `OSDLanguage equals "ar-SA"` |
| 6 | **Apply autounattend.xml** | From SCCM package (linked in "Apply OS Image" step) |
| 7 | **Apply Windows Settings** | `OSDComputerName`, `OSDRegisteredOrgName` |
| 8 | **Apply Network Settings** | `OSDDomainName`, `OSDDomainOUName`, `OSDJoinAccount`, `OSDJoinPassword` |
| 9 | **Apply Device Drivers** | Chipset, Network, Audio, Storage, Video |

### Phase 3 — Setup Operating System

| Step | Action | Purpose |
|------|--------|---------|
| 1 | **Setup Windows and Configuration Manager** | Install SCCM Client |
| 2 | **Restart Computer** | Apply SCCM Client installation |

### Phase 4 — Install Applications

| Step | Action | Purpose |
|------|--------|---------|
| 1 | **Install Cisco Secure Client** | VPN + network services |
| 2 | **Schedule Post OSD Enrollment** | Register retry + cleanup tasks |
| 3 | **Final Restart** | Apply all policies + drivers + apps |

---

## 🌐 Language Selection Mechanism

The Task Sequence supports **two OS images** (English and Arabic) with automatic selection based on user input:

```
Start-DeploymentWizard.ps1
          ↓
User Selects Language (English / Arabic)
          ↓
OSDLanguage Variable Created
          ↓
 ┌─────────────────────┬─────────────────────┐
 │                     │
 │ OSDLanguage=en-US   │ OSDLanguage=ar-SA
 │                     │
 ▼                     ▼
Apply OS English   Apply OS Arabic
 │                     │
 └──────────┬──────────┘
            ↓
 Apply Windows Settings
            ↓
 Apply Network Settings
            ↓
 Apply Device Drivers
            ↓
 Setup Windows & ConfigMgr
```

### Why This Design?

- **Single Task Sequence** — no need to create separate TS for each language
- **User-driven** — technician selects language during wizard
- **Automatic** — correct image applied based on `OSDLanguage` value
- **Consistent** — same installation steps regardless of language

---

## 🔄 Full Deployment Lifecycle

```
SCENARIO 1 — ON-SITE INSTALLATION (empty device, technician present)
  └─ Device boots from installation media → WinPE loads → Wizard appears
  └─ Tech authenticates → enters name → selects OU → picks software → selects language
  └─ Wizard writes OSDComputerName, OSDDomainOUName, OSDLanguage, App_* to TSEnvironment
  └─ Remove-StaleADComputer cleans up any existing AD object
  └─ WinPE restart → Partition disk → Apply OS image (English/Arabic based on OSDLanguage)
  └─ Apply autounattend.xml → Windows Settings → Network Settings → Drivers
  └─ Setup Windows + SCCM Client → Restart → Install apps → Post-OSD enrollment
  └─ Ready: Domain-joined, Entra-joined, Intune-enrolled, Co-managed

SCENARIO 2 — REMOTE DEPLOYMENT (technician off-site)
  └─ Tech runs Pre-Staging Tool from office → registers MAC + Name + OU + Software + Language
  └─ AdminService REST API → device in SCCM DB with all OSD variables
  └─ Employee boots device from network → SCCM recognizes MAC → deploys automatically
  └─ All OSD variables applied from pre-staged record

SCENARIO 3 — IN-PLACE UPGRADE (existing OS → Windows 11 25H2)
  └─ Task sequence detects current UI language (Arabic / English)
  └─ Pulls and runs matching upgrade files automatically
  └─ Files, apps, and settings preserved — zero manual intervention

POST-DEPLOYMENT (all scenarios, silent SYSTEM context)
  └─ Scheduler registers retry + cleanup tasks
  └─ Accelerator runs: Time sync → IPv6 → SCCM → Entra join → MDM → Co-mgmt
  └─ Machine reboots into Windows → AutoLogon → retries every 5 min × 30 min
  └─ At +35 min: cleanup task deletes everything

✅ READY — Domain-joined, Entra-joined, Intune-enrolled, Co-managed
```

---

## 🎨 Customization

Every visible string is a **parameter**. Pass your org values at runtime — no file editing needed:

```powershell
.\DeploymentWizard\Start-DeploymentWizard.ps1 `
    -CompanyName "Contoso Ltd" -CompanyShort "CT" -Department "Infrastructure" `
    -DomainName "contoso.com" -SearchBase "OU=Workstations,DC=contoso,DC=com" `
    -DomainController "dc01.contoso.com" -SccmServer "sccm.contoso.com" `
    -OrgName "Contoso Ltd" -DefaultLanguage "en-US" `
    -Software @("Chrome|App_Chrome|true","Firefox|App_Firefox|true","Office365|App_Office|true")
```

---

## 📊 Operational Safeguards

| Category | Safeguard | Component |
|----------|-----------|-----------|
| Input Validation | Required params checked → exit 1 | Wrapper |
| Auth Security | 5-attempt lockout, password in-memory only, hidden TS variable | Wizard + PreStaging |
| WinPE Resilience | MessageBox fallback on XAML failure, try/catch on dialogs | Wizard |
| Process Isolation | Wizard in child `powershell.exe` — crash can't kill TS | Wrapper |
| Retry Engine | Post-logon task retries every 5 min × 30 min | Scheduler |
| Reboot Safety | `RebootDone.flag` — exactly 1 reboot, no loops | Scheduler |
| Self-Cleanup | Tasks, copies, flags deleted at +35 min | Scheduler |
| API Resilience | Retry 2× on failure, TLS 1.2 applied twice | PreStaging |
| Structured Logging | Tab-separated, timestamped, password masked | All scripts |

---

## 🐛 Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Wizard doesn't launch | Scripts not co-located in `DeploymentWizard/` | Both `.ps1` files must be in same folder |
| Wizard blank in WinPE | WinPE-NetFX missing | Add via Boot Image → Optional Components |
| OU grid empty in WinPE | Anonymous LDAP fails | Sign in — credentials reused for bind |
| "Cannot reach domain" | DC offline | `Test-NetConnection $DC -Port 389` |
| Sign-in disabled | 5 failed attempts | Restart wizard |
| Enrollment never completes | AAD Connect sync gap | Retries cover the 30-min window |
| Repeated reboots | Flag guard missing | Check `C:\Windows\Temp\PostOSD\RebootDone.flag` |
| Co-management "Not Detected" | Cloud Attach not configured | Set up in SCCM console |
| Pre-Staging: 403 | Missing RBAC | Import `Helpdesk OSD Pre-Staging Operator.xml` |

---

## 🛡 Design Principles

| Principle | Implementation |
|-----------|---------------|
| PowerShell 5.1 only | Tested on Windows PS 5.1. Uses `[wmiclass]` (SCCM TS always PS 5.1). |
| Zero hardcoded branding | Every org name, domain, OU, software is a CLI parameter. |
| WinPE-safe | `LdapConnection` (no ADSI COM). MessageBox fallback. Try/catch guard. |
| Process isolation | Wrapper → child `powershell.exe`. Crash → exit 1, TS can continue. |
| Dependency-driven ordering | Post-OSD: time → IPv6 → SCCM → Entra → MDM → co-mgmt. |
| Self-cleaning | Cleanup task deletes both tasks + copies + markers automatically. |
| No console required | PreStaging: REST API. Wizard: WPF GUI. |
| PSWrap EXE compatible | C# SSL bypass works without runspace. x64 + STA + GUI. |
| Single-reboot enforcement | Flag file ensures exactly 1 reboot for IPv6 change. |

---

## 📜 License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).

---

## 👤 Author

**Mohammad Abdulkader Omar**
Website: https://momar.tech
LinkedIn: https://www.linkedin.com/in/mabdulkadr/

---
## ☕ Support

If this project helps you, consider supporting it:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-☕-FFDD00?style=for-the-badge)](https://www.buymeacoffee.com/mabdulkadrx)

---

## 📊 Version History

| Version | Date | Changes |
|---------|------|---------|
| v1.0 | 2026-08-03 | Initial release: WPF deployment wizard + TS wrapper + Post-OSD enrollment accelerator + self-cleaning scheduler + SCCM-OSD-PreStaging tool (AdminService REST API, C# SSL bypass, EXE support) + autounattend.xml + deployment reporting + full documentation |

---

## ⚠ Disclaimer

These scripts are provided as-is. Test them in a staging environment before applying them to production. The author is not responsible for any unintended outcomes resulting from their use.
