# 🚀 Deployment Wizard (DeploymentWizard.ps1)

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-WinPE%20%2B%20Full%20OS-lightgrey.svg)
![GUI](https://img.shields.io/badge/GUI-WPF-purple.svg)
![SCCM](https://img.shields.io/badge/SCCM-TSEnv%20COM-orange.svg)
![Version](https://img.shields.io/badge/version-1.0-green.svg)

---

## ⚙️ Configuration Required

> Replace the default parameter values with your organization's data before deployment.

```powershell
.\DeploymentWizard.ps1 `
    -CompanyName    "Your Company" `
    -CompanyShort   "YC" `
    -Department     "IT Operations" `
    -DomainName     "yourdomain.local" `
    -SearchBase     "OU=Domain Computers,DC=yourdomain,DC=local" `
    -DomainController "dc01.yourdomain.local" `
    -SccmServer     "sccm.yourdomain.local" `
    -OrgName        "Your Company" `
    -Software       @("Chrome|App_Chrome|true","Firefox|App_Firefox|true")
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

**DeploymentWizard.ps1** is the **user-facing WPF wizard** for SCCM/MECM Operating System Deployment Task Sequences. It runs during OSD to collect:

- 🔑 **Domain credentials** (validated against Active Directory)
- 💻 **Computer name**
- 📂 **Target Organizational Unit** (via live LDAP browsing)
- ☑️ **Software selection** (dynamic checkboxes)

It then writes everything to the Task Sequence as **COM TSEnvironment variables** that downstream steps consume automatically.

> **Launch:** Normally started by [`Start-DeploymentWizard.ps1`](Start-DeploymentWizard.md), the SCCM TS wrapper.

---

## ✨ Core Features

### 🔹 AD Authentication
- Validates domain credentials via `PrincipalContext.ValidateCredentials`
- Failed attempts tracked — **5 failures → sign-in disabled** (lockout)
- Password masked in all UI and logs; never persisted to disk

### 🔹 LDAP OU Browser (WinPE-Compatible)
- Pure .NET `LdapConnection` — **no ADSI COM**, works in WinPE
- Live search DataGrid with horizontal scroll, breadcrumb paths, selected-OU indicator
- Anonymous bind fallback; authenticated bind after sign-in (reuses credentials)

### 🔹 Device Information
- Computer name, model, serial, memory, disk, domain state via WMI
- Real-time TCP connectivity tests: **DC (port 389)** and **SCCM (port 445)**

### 🔹 Software Selection
- Dynamic checkboxes generated from the `-Software` parameter
- Format: `DisplayName|TSVariableName|DefaultChecked`
- Checked items → `App_*` Task Sequence variables

### 🔹 Language Selection
- Radio buttons for **English** (`en-US`) and **Arabic** (`ar-SA`)
- Writes `OSDLanguage` variable to TSEnvironment
- Task Sequence uses this variable to select the correct OS image:
  - `OSDLanguage = en-US` → Apply OS English
  - `OSDLanguage = ar-SA` → Apply OS Arabic
- Single Task Sequence supports both languages — no separate TS needed

### 🔹 SCCM Output Engine
- Writes variables via COM `Microsoft.SMS.TSEnvironment`
- Masked `OSDJoinPassword` (flagged hidden) — never logged
- `App_*` custom variables for downstream application steps

### 🔹 WinPE Safety
- MessageBox fallback whenever XAML rendering fails
- try/catch on every dialog load — the wizard keeps working in degraded WinPE
- `Topmost=True` window stays above other deployment windows

---

## ⚙️ Requirements

| Requirement | Minimum | Purpose |
|-------------|---------|---------|
| PowerShell | 5.1+ | Script execution |
| .NET Framework | 4.6.2+ | WPF, AD auth, LDAP |
| WinPE | 10.0.17763+ | WinPE-PowerShell + WinPE-NetFX |
| AD Domain | Connectivity | Auth + OU browsing |
| SCCM/MECM | CB 1902+ | TS variable output |

---

## 🚀 How to Run

### Option 1 — Via Task Sequence (Recommended)
Add a **Run PowerShell Script** step to your task sequence using [`Start-DeploymentWizard.ps1`](Start-DeploymentWizard.md).

### Option 2 — Direct (Testing)
```powershell
.\DeploymentWizard.ps1
```

### Option 3 — Fully Customized
```powershell
.\DeploymentWizard.ps1 -CompanyName "Contoso Ltd" -CompanyShort "CT" `
    -Department "Infrastructure" -DomainName "contoso.com" `
    -SearchBase "OU=Workstations,DC=contoso,DC=com" `
    -DomainController "dc01.contoso.com" -SccmServer "sccm.contoso.com" `
    -OrgName "Contoso Ltd" `
    -Software @("Google Chrome|App_Chrome|true","Mozilla Firefox|App_Firefox|true","7-Zip|App_7Zip|false")
```

---

## ⚙️ Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-CompanyName` | `Momar Tech` | Organization name in title/header/dialogs |
| `-CompanyShort` | `MT` | 2-3 char logo badge text |
| `-Department` | `IT Operations` | Header/footer subtitle |
| `-DomainName` | `momar.local` | AD domain for auth + join |
| `-SearchBase` | `OU=Domain Computers,DC=Momar,DC=local` | LDAP OU search root |
| `-DomainController` | `dc01.momar.local` | DC for connectivity test (TCP 389) |
| `-SccmServer` | `sccm.momar.local` | SCCM MP for connectivity test (TCP 445) |
| `-OrgName` | `Momar Tech` | Written to `OSDRegisteredOrgName` |
| `-DefaultLanguage` | `en-US` | System language (`en-US` / `ar-SA`) |
| `-Software` | `"Cisco AnyConnect VPN\|App_CiscoAnyConnect\|true"` | `DisplayName\|TSVar\|DefaultChecked` |

---

## 🔄 Typical Workflow

1. Wizard loads → attempts anonymous LDAP bind to load OUs
2. User signs in with domain credentials (validated against AD)
3. User enters computer name, searches/selects OU, picks software
4. User selects language (English or Arabic)
5. Wizard validates input (name chars, ≤ 15 chars, OU selected, authenticated)
6. User clicks **Deploy** → variables written to TSEnvironment
7. Result dialog confirms; wizard exits

### Task Sequence Flow After Wizard

```
Wizard writes variables → TS continues
    ↓
Remove-StaleADComputer (cleans any existing AD object)
    ↓
Restart to WinPE
    ↓
Partition Disk (BIOS or UEFI)
    ↓
Apply OS Image (English if OSDLanguage=en-US, Arabic if OSDLanguage=ar-SA)
    ↓
Apply autounattend.xml (from SCCM package)
    ↓
Apply Windows Settings (OSDComputerName, OSDRegisteredOrgName)
    ↓
Apply Network Settings (OSDDomainName, OSDDomainOUName, credentials)
    ↓
Install Drivers
    ↓
Setup Windows + SCCM Client
    ↓
Install Applications (App_* variables)
    ↓
Post-OSD Enrollment (Entra ID, MDM, Co-Management)
```

---

## 📝 Task Sequence Variables Written

| Variable | Source | Type |
|----------|--------|------|
| `OSDComputerName` | Wizard input | Built-in |
| `OSDDomainName` | Wizard input | Built-in |
| `OSDDomainOUName` | Selected OU DN | Built-in |
| `OSDJoinAccount` | Credentials | Built-in |
| `OSDJoinPassword` | Credentials (hidden) | Built-in |
| `OSDRegisteredOrgName` | `-OrgName` param | Built-in |
| `OSDLanguage` | Language picker | Custom |
| `App_*` | Checked checkboxes | Custom |

---

## 📊 Operational Safeguards

- ✅ Credential lockout after 5 failed attempts
- 🔒 Password stored in-memory only (`$script:JoinPass`) — never on disk
- 🛟 MessageBox fallback in WinPE when XAML fails
- 🔄 Closing guard flag prevents stale UI dispatches
- 📝 Color-coded Message Center log (`INFO` / `SUCCESS` / `WARN` / `ERROR`)

---

## 🐛 Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| OU list empty | Anonymous LDAP fails (WinPE) | Sign in — credentials reused for bind |
| "Cannot reach domain" | DC offline | Check network + `-DomainController` |
| Sign-in disabled | 5 failed attempts | Restart the wizard |
| Wizard blank in WinPE | Missing WinPE-NetFX | Add component to boot image |
| Not inside Task Sequence warning | Running outside SCCM | Expected — variables can't be written |
| Exit code 1 | Wizard crashed / cancelled | Check `smsts.log` for the wrapper output |

---

## 🛡 Design Principles

- Single-file architecture (XAML + functions + handlers in one script)
- Pure .NET LDAP — no ADSI COM dependency
- Frozen brushes for thread-safe WPF rendering
- Async TCP connectivity tests (never blocks UI)
- Topmost window during deployment
- Zero hardcoded branding — all org values are parameters

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
