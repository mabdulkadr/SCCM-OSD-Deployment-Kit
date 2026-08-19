# 🚀 SCCM OSD Deployment Kit

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)
![GUI](https://img.shields.io/badge/GUI-WPF-purple.svg)
![SCCM](https://img.shields.io/badge/SCCM-MECM%20CB%201902%2B-orange.svg)
![Version](https://img.shields.io/badge/version-1.0-green.svg)

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-☕-FFDD00?style=for-the-badge)](https://www.buymeacoffee.com/mabdulkadrx)

---

## 📖 What Is This?

A self-contained PowerShell toolkit for SCCM/MECM that adds interactive WPF wizards and full lifecycle automation to your Windows 11 deployment process. No external binaries, no XML configuration files — just copy the folder and go.

It replaces the rigid zero-touch deployment model with **user-driven, technician-friendly workflows** that cover every support scenario.

### Why Use This Toolkit?

| Feature | This Toolkit | UI++ | TsGui |
|---------|--------------|------|-------|
| **Setup** | Copy folder | Compiled EXE + XML | Module + XML |
| **Configuration** | CLI parameters | XML-based | XML-based |
| **WinPE Support** | Native .NET LDAP (no ADSI) | Requires components | Requires components |
| **Pre-Staging** | ✅ Built-in (REST API) | � Not included | ❌ Not included |
| **Post-OSD Enrollment** | ✅ Built-in (Entra, MDM, Co-mgmt) | ❌ Not included | ❌ Not included |
| **RBAC Role Included** | ✅ Yes | ❌ Manual | ❌ Manual |

---

## � Deployment Scenarios

The toolkit supports three scenarios covering every support situation:

| Scenario | When to Use | What Happens |
|----------|-------------|--------------|
| 🖥 **On-Site Installation** | Empty device, technician at the machine | Tech boots device → wizard collects info → auto installs |
| 📡 **Remote Deployment** | Tech at office, employee at remote location | Tech pre-stages device → employee boots from network → full auto deploy |
| ⬆️ **In-Place Upgrade** | Existing OS needs upgrade to 25H2 | Auto-detects language → preserves files/apps → silent upgrade |

---

## 📦 What's Inside

The toolkit is organized into self-contained modules — each with its own script and documentation:

```
SCCM-OSD-Deployment-Kit/
├── README.md                              ← You are here
├── autounattend.xml                       ← Windows OOBE bypass
├── autounattend.md                        ← Documentation
├── Remove-StaleADComputer.ps1             ← Cleans stale AD objects in WinPE
│
├── DeploymentWizard/                      ← Phase 1: Interactive OSD wizard
│   ├── Start-DeploymentWizard.ps1         ← TS entry point (wrapper)
│   ├── DeploymentWizard.ps1               ← WPF wizard application
│   └── *.md
│
├── Post-OSD-Enrollment/                   ← Phase 2: Silent post-deployment
│   ├── Schedule-PostOSD-Enrollment.ps1    ← Retry + cleanup scheduler
│   ├── Post-OSD-Enrollment-Accelerator.ps1← 6-section provisioning engine
│   └── *.md
│
├── SCCM-OSD-PreStaging/                   ← Phase 0: Remote device registration
│   ├── SCCM-OSD-PreStaging.ps1            ← WPF GUI for helpdesk
│   ├── Helpdesk OSD Pre-Staging Operator.xml ← RBAC role
│   └── *.md
│
└── Report/                                ← Deployment reporting
    ├── Get-OSDDeploymentReport.ps1        ← HTML status reports
    ├── Send-QUExchangeMail.psm1           ← Graph API email module
    └── *.md
```

---

## ⚡ Quick Start

### 1. Upload to SCCM

Create a package containing the entire `SCCM-OSD-Deployment-Kit` folder, then distribute it to your Distribution Points.

**Package properties** (example):

| Property | Value |
|----------|-------|
| Package Name | `SCCM-OSD-Deployment-Kit` |
| Package ID | `QU100100` |
| Version | `1.0` |

### 2. Configure Boot Image

In **SCCM Console → Software Library → Boot Images → Properties → Optional Components**, add:

| Component | Size | Why Needed |
|-----------|------|------------|
| **WinPE-NetFx** | ~195 MB | WPF UI, AD authentication, LDAP |
| **WinPE-PowerShell** | ~45 MB | Script execution |

Then **Update Distribution Points**.

### 3. Add to Your Task Sequence

Add these steps in order:

| Step | Type | Script |
|------|------|--------|
| 1 | Run PowerShell Script | `Start-DeploymentWizard.ps1` |
| 2 | Run PowerShell Script | `Remove-StaleADComputer.ps1` |
| 3 | Run PowerShell Script | `Schedule-PostOSD-Enrollment.ps1` |
| 4 | Run PowerShell Script | `Post-OSD-Enrollment-Accelerator.ps1` |

Fill in the parameters for each step with your organization values (see [Configuration](#-configuration) below).

### 4. Configure

Replace the default placeholders in every script's parameter block with your own values. The two most important are:

- `-DomainName` — your AD domain (e.g., `contoso.local`)
- `-SearchBase` — your LDAP search base (e.g., `OU=Workstations,DC=contoso,DC=local`)

See each module's documentation for the full list.

---

## 🔄 How It All Works

### Scenario 1: On-Site Installation

```
1. Device boots from PXE/network media
2. WinPE loads → Deployment Wizard appears
3. Technician:
   - Signs in with domain credentials
   - Enters computer name, selects OU, picks software
   - Selects language (English or Arabic)
   - Clicks Deploy
4. From this point → everything is automatic:
   - Partition disk → Apply OS → Install drivers
   - Domain join → SCCM client → Applications
   - Post-OSD: Time sync → IPv6 → Entra ID → Intune → Co-management
5. Device ready for the end user
```

### Scenario 2: Remote Deployment

```
1. Helpdesk tech runs Pre-Staging Tool from office:
   - Enters MAC address, computer name, OU, software, language
   - Clicks Pre-Stage → device registered in SCCM DB
2. Instructs employee to PXE boot the device
3. From the employee's perspective:
   - Selects the deployment option
   - Everything else is automatic (same as Scenario 1)
```

### Scenario 3: In-Place Upgrade

```
1. User opens Software Center on their device
2. Selects "Upgrade to Win11 25H2" → clicks Install
3. The Task Sequence:
   - Auto-detects current UI language
   - Pulls matching upgrade files
   - Runs silent upgrade in background
4. Files, applications, and settings preserved
```

---

## ⚙️ Configuration

### Required Placeholders

Replace these in every script's parameter block:

| Placeholder | What to Put |
|-------------|-------------|
| `<your-domain>.local` | Your AD domain FQDN |
| `OU=YourOU,DC=your-domain,DC=local` | Your LDAP search base DN |
| `dc01.your-domain.local` | Your domain controller FQDN |
| `sccm.your-domain.local` | Your SCCM Management Point FQDN |
| `SCCM.your-domain.local` | Your SCCM AdminService FQDN |
| `ABC` (3 chars) | Your SCCM site code |
| `<YOUR_TENANT_ID>` | Azure AD tenant GUID (for reports) |
| `<YOUR_CLIENT_ID>` | Azure AD app client ID (for reports) |
| `<YOUR_CLIENT_SECRET>` | Azure AD app secret (for reports) |

### Where to Configure

**For TS steps:** Right-click the step in SCCM Console → Properties → fill in the **Parameters** field.

**For the Pre-Staging Tool:** Pass values as script parameters or edit the defaults in the script header.

---

## 📋 Components in Detail

### 🖥 Deployment Wizard

Interactive WPF wizard that runs in WinPE during OSD. Collects all the information the task sequence needs (computer name, OU, credentials, software, language) and writes it as Task Sequence variables.

**TS Step:** `Start-DeploymentWizard.ps1` (the wrapper that validates, launches, monitors, and verifies)

> � [Read full documentation →](DeploymentWizard/DeploymentWizard.md)

### 📡 Pre-Staging Tool

WPF GUI for helpdesk operators to register bare-metal devices in SCCM **before they arrive on-site**. Uses the SCCM AdminService REST API over HTTPS — no SCCM console required on the operator's workstation.

> 📖 [Read full documentation →](SCCM-OSD-PreStaging/SCCM-OSD-PreStaging.md)

### ⚙️ Post-OSD Enrollment

Silent SYSTEM-context provisioning that runs at the end of the task sequence. Six dependency-ordered steps:

1. **Time Service** — sync from PDC, configure time zone
2. **IPv6 Disable** — adapter + registry (single reboot guard)
3. **SCCM Actions** — trigger 8 standard actions + Windows Update refresh
4. **Entra ID Join** — Hybrid Azure AD join
5. **MDM Enrollment** — Intune auto-enrollment
6. **Co-Management** — verify SCCM + Intune co-management

A built-in scheduler retries every 5 min × 30 min, then self-cleans everything.

> 📖 [Read full documentation →](Post-OSD-Enrollment/Post-OSD-Enrollment-Accelerator.md)

### 📄 autounattend.xml

Minimal Windows Setup answer file that hides OOBE screens and bypasses the Windows 11 network requirement. Linked in the **Apply Operating System Image** TS step.

> 📖 [Read full documentation →](autounattend.md)

### 📊 Reporting

- **`Get-OSDDeploymentReport.ps1`** — Generates HTML executive reports from SCCM WMI
- **`Send-QUExchangeMail.psm1`** — Sends email via Microsoft Graph API (OAuth 2.0)

> 📖 [Report documentation →](Report/Get-OSDDeploymentReport.md)

---

## ⚙️ Requirements

| Requirement | Minimum | Notes |
|-------------|---------|-------|
| PowerShell | 5.1+ | Built into Windows 10/11 |
| .NET Framework | 4.6.2+ | WPF, AD auth, LDAP |
| SCCM/MECM | CB 1902+ | `Microsoft.SMS.TSEnvironment` COM interface |
| WinPE | 10.0.17763+ | With WinPE-NetFx + WinPE-PowerShell |
| AD Domain | Connectivity to DC | Ports 389, 88, 445 |
| SCCM AdminService | HTTPS | Required only for Pre-Staging Tool |

---

## 🐛 Troubleshooting

| Problem | Likely Cause | Fix |
|---------|--------------|-----|
| Wizard doesn't appear | Scripts in different folders | Both `.ps1` files must be in same `DeploymentWizard/` folder |
| Wizard blank in WinPE | Missing WinPE-NetFX | Add WinPE-NetFX to boot image, update DPs |
| OU list empty | Anonymous LDAP failed (WinPE) | Sign in — credentials are reused for LDAP bind |
| "Cannot reach domain" | DC unreachable | `Test-NetConnection dc01.your-domain.local -Port 389` |
| Sign-in disabled | 5 failed attempts | Restart wizard (this is intentional security) |
| Pre-Staging: 403 error | Missing RBAC role | Import `Helpdesk OSD Pre-Staging Operator.xml` in SCCM |
| Co-management "Not Detected" | Cloud Attach not configured | Set up Cloud Attach in SCCM console |
| Upgrade is very slow | Antivirus scanning files | Add `_SMSTaskSequence` folder to AV exclusion list |
| Upgrade fails | Leftover files from previous attempt | Delete `C:\$WINDOWS.~BT` before retrying |

---

## 📂 Project Structure

```
SCCM-OSD-Deployment-Kit/
│
├── 📖 README.md                          ← Project overview (this file)
├── 📄 autounattend.xml                   ← Windows OOBE bypass
├── 📖 autounattend.md
├── 🧹 Remove-StaleADComputer.ps1         ← WinPE: delete stale AD computer objects
│
├── 🖥 DeploymentWizard/
│   ├── � Start-DeploymentWizard.ps1     ← TS wrapper (validates + launches + verifies)
│   ├── � DeploymentWizard.ps1           ← WPF wizard application
│   └── 📖 *.md
│
├── ⚙️ Post-OSD-Enrollment/
│   ├── ⏰ Schedule-PostOSD-Enrollment.ps1 ← Retry + cleanup scheduler
│   ├── ⚙️ Post-OSD-Enrollment-Accelerator.ps1 ← 6-section provisioning engine
│   └── 📖 *.md
│
├── 📡 SCCM-OSD-PreStaging/
│   ├── 🖥 SCCM-OSD-PreStaging.ps1        ← WPF GUI (AdminService REST API)
│   ├── 🔐 Helpdesk OSD Pre-Staging Operator.xml ← RBAC role
│   └── � *.md
│
└── 📊 Report/
    ├── 📈 Get-OSDDeploymentReport.ps1    ← HTML status reports
    ├── 📧 Send-QUExchangeMail.psm1       ← Graph API email module
    └── 📖 *.md
```

---

## 📜 License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).

---

## 👤 Author

**Mohammad Abdulkader Omar**
Website: https://momar.tech
LinkedIn: https://www.linkedin.com/in/mabdulkadr/
Version: **1.0**

---

## ☕ Support

If this project helps you, consider supporting it:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-☕-FFDD00?style=for-the-badge)](https://www.buymeacoffee.com/mabdulkadrx)

---

## ⚠ Disclaimer

These scripts are provided as-is. Test them in a staging environment before applying them to production. The author is not responsible for any unintended outcomes resulting from their use.
