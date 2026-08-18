# 🚀 SCCM OSD Pre-Staging Tool

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)
![GUI](https://img.shields.io/badge/GUI-WPF-purple.svg)
![SCCM](https://img.shields.io/badge/SCCM-AdminService%20REST-9C27B0.svg)
![EXE](https://img.shields.io/badge/EXE-PSWrap%20Ready-green.svg)
![Version](https://img.shields.io/badge/version-1.0-green.svg)

---

## ⚙️ Configuration Required

> Replace the default parameter values with your organization's data before deployment.

```powershell
.\SCCM-OSD-PreStaging.ps1 `
    -CompanyName      "Your Company" `
    -CompanyShort     "YC" `
    -Department       "IT Operations" `
    -DomainName       "yourdomain.local" `
    -SearchBase       "OU=Domain Computers,DC=yourdomain,DC=local" `
    -DomainController "dc01.yourdomain.local" `
    -SccmSiteCode     "YC1" `
    -SccmServer       "SCCM.yourdomain.local" `
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
| `-DomainController` | `dc01.momar.local` | DC for LDAP queries |
| `-SccmSiteCode` | `MT1` | SCCM site code |
| `-SccmServer` | `SCCM.Momar.local` | AdminService FQDN |
| `-OrgName` | `Momar Tech` | OSDRegisteredOrgName value |
| `-Software` | Cisco AnyConnect | `Name|TSVar|Default` format |

---

## 📖 Overview

**SCCM-OSD-PreStaging.ps1** is a professional **WPF GUI tool** for **off-site / zero-touch pre-staging** of bare-metal devices in SCCM/MECM **before PXE boot**.

It solves a common logistics problem: IT technicians at remote sites need to register new machines in SCCM, but they don't have the SCCM console installed. This tool connects to the **SCCM AdminService REST API** over HTTPS from **any Windows workstation** — no console, no module, no admin workstation setup:

- 🚀 **Who uses it:** Helpdesk operators at remote campuses/sites who receive new hardware
- 🎯 **When:** Before the device ever PXE boots — the device isn't even on the network yet
- 📡 **How:** HTTPS calls to the SCCM SMS Provider's AdminService endpoint
- 📊 **What it does:** Registers the MAC address + computer name, injects all OSD variables (OU, domain, software, language), makes the device "PXE-ready"

> **Companion Tool:** [`DeploymentWizard.ps1`](../DeploymentWizard/DeploymentWizard.md) — used **on-site during OSD** (the machine is at the deployment bench). This tool is for **remote/off-site pre-staging** before the device arrives.

---

## 🏗 Architecture

### AdminService REST API Flow

```
User fills form → clicks Pre-Stage
         │
         ▼
  ┌─────────────────────────────────────────┐
  │ STEP 1: Set-AdminServiceTls             │
  │   • Force TLS 1.2                       │
  │   • Bypass proxy                        │
  │   • Set connection limit to 100         │
  │   • Attach C# SSL bypass delegate       │
  └────────────────┬────────────────────────┘
                   ▼
  ┌──────────────────────────────────────────────┐
  │ STEP 2: POST ImportMachineEntry              │
  │   • Body: { MAC, NetbiosName }               │
  │   • OverwriteExistingRecord = true (always)  │
  │   • Returns: { ResourceID, MachineExists }   │
  └────────────────┬─────────────────────────────┘
                   ▼
  ┌──────────────────────────────────────────────┐
  │ STEP 3: Extract ResourceID                   │
  │   ├─ Direct from response (fast path)        │
  │   └─ Poll SMS_R_System (6 attempts × 2s)     │
  │       Covers SCCM DB write latency           │
  └────────────────┬─────────────────────────────┘
                   ▼
  ┌─────────────────────────────────────────┐
  │ STEP 4: POST SMS_MachineSettings        │
  │   • Body: { ResourceID, OSDVariables[] }│
  │   • Injects all 8+ OSD variables        │
  │   • Variables available at PXE boot     │
  └────────────────┬────────────────────────┘
                   ▼
  ┌─────────────────────────────────────────┐
  │ STEP 5: Success                         │
  │   • Log: "Device variables injected"    │
  │   • Auto-clear fields for next device   │
  └─────────────────────────────────────────┘
```

**API endpoints used (SCCM AdminService):**

| Endpoint | Method | Request Body | Response |
|----------|--------|-------------|----------|
| `.../SMS_Site.ImportMachineEntry` | POST | `{ MACAddress, NetbiosName, OverwriteExistingRecord }` | `{ ResourceID, MachineExists, ReturnValue }` |
| `.../SMS_R_System` (polling fallback) | GET (ODATA) | `?$filter=NetbiosName eq '...'` | `{ value: [{ ResourceID }] }` |
| `.../SMS_MachineSettings` | POST | `{ ResourceID, SourceSite, MachineVariables[] }` | Success/error |

### ResourceID Retrieval — Polling Strategy

The `ImportMachineEntry` response typically returns the `ResourceID` directly. When available, the script uses it immediately (fast path). If the response doesn't contain the ID, the script enters a **polling loop** because SCCM writes the new machine record asynchronously to its database:

| Attempt | Wait (cumulative) | Action |
|---------|-------------------|--------|
| 1 | 0s | Query `SMS_R_System?$filter=NetbiosName eq '...'` |
| 2 | 2s | Retry query |
| ... | ... | ... |
| 6 | 12s | Last attempt — throw detailed error if still not found |

This replaces the original single `Start-Sleep 2` + one query approach, which failed on busy SCCM servers where the database write could take 4-10 seconds. The `ResourceID` from the `ImportMachineEntry` response eliminates the need for polling in most cases.

### SSL / TLS Architecture — The C# Bypass Problem

SCCM AdminService often runs with a **self-signed certificate** on the SMS Provider. PowerShell's `Invoke-RestMethod` fails self-signed cert validation unless you bypass it. The standard bypass is:

```powershell
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
```

**This fails in compiled EXEs.** When PSWrap compiles the script to an EXE, `ServicePointManager` fires the certificate callback on a .NET thread-pool thread that has **no PowerShell runspace**. The script block `{ $true }` crashes with:

```
There is no Runspace available to run scripts in this thread.
```

**The solution — compiled C# delegate:**

```csharp
// Compiled at runtime via Add-Type
using System;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class SslBypass
{
    public static bool ValidateCertificate(
        object sender, X509Certificate certificate, 
        X509Chain chain, SslPolicyErrors sslPolicyErrors)
    {
        return true;  // Accept all certificates
    }
}
```

This C# method is a **true .NET delegate** — no PowerShell runspace needed. It's wired into the callback as:

```powershell
$cbMethod = [SslBypass].GetMethod('ValidateCertificate')
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = 
    [System.Net.Security.RemoteCertificateValidationCallback]::CreateDelegate(
        [System.Net.Security.RemoteCertificateValidationCallback], $cbMethod)
```

The script-block approach is kept as a **fallback** for interactive PowerShell use (where a runspace exists).

### TLS 1.2 Hardening — Why It's Applied Twice

```powershell
function Set-AdminServiceTls {
    # Force TLS 1.2 (with fallback for PS5.1 compatibility)
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = $p -bor 192 -bor 768 -bor 3072
    } catch {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    }
    
    # Wire SSL bypass delegate (C# or script-block)
    # ... (delegate code) ...

    # Kill proxy + boost connections
    [System.Net.WebRequest]::DefaultWebProxy = $null
    [System.Net.ServicePointManager]::DefaultConnectionLimit = 100
}

# Called at startup AND before every API call
Set-AdminServiceTls
```

TLS settings are applied:
1. **At script startup** — before any network operation
2. **Inside `Invoke-DevicePreStage`** — immediately before every API call

The double application ensures that even if some .NET runtime component resets the setting, the next API call re-applies it.

---

## ✨ Core Features

### 🔹 AdminService REST API Integration
- Full 3-step device import pipeline: **ImportMachineEntry → Verify via SMS_R_System → Inject SMS_MachineSettings**
- `Invoke-RestMethod` with site-code-based URL construction
- PS7 compatibility: `-SkipCertificateCheck` added automatically via parameter splatting
- 8 OSD variables injected in a single POST body

### 🔹 C# SSL Bypass (EXE-Safe)
- Runtime-compiled `.NET` static class via `Add-Type -TypeDefinition`
- Works in compiled EXEs (PSWrap), interactive PowerShell, and PS7
- Script-block fallback for environments where `Add-Type` fails
- Solves the classic "runspace" error in compiled PowerShell EXEs

### 🔹 AD Authentication with Lockout
- `PrincipalContext.ValidateCredentials` against the domain in `-DomainName`
- 5 failed attempts → Sign In button permanently disabled
- Auth panel transforms after login: collapses to "Signed in as DOMAIN\User" badge + Sign Out button
- Credentials reused for authenticated LDAP OU browsing

### 🔹 OU Browser
- Live-search DataGrid with 3 columns: Name, Distinguished Name, Friendly Path
- Horizontal scrollbar for long DNs (e.g., `OU=Sub3,OU=Sub2,OU=Top,DC=domain,DC=local`)
- Breadcrumb path display: DN → "Top / Sub2 / Sub3"
- Selected OU indicator with green background

### 🔹 Software Selection with Tooltips
- Dynamic CheckBoxes generated from the `-Software` parameter
- Each checkbox displays the application name
- **Hover to see the TS variable name** — helps technicians understand what the checkbox controls
- Checked items → `App_*` SCCM variables

### 🔹 Input Validation
- **MAC Address:** Real-time regex validation. Red banner for invalid input, green for valid. Auto-formats input to `XX:XX:XX:XX:XX:XX` (all uppercase, colons).
- **Computer Name:** 15-character limit. No special characters `[\/:*?"<>|]`. Max 15 chars (NetBIOS limit).
- **All fields:** Green/red visual feedback before the Pre-Stage button is enabled.

### 🔹 Confirmation Dialog
- Full-detail custom WPF dialog showing every piece of information before sending to SCCM:
  - Computer Name, MAC Address, Target OU (DN + friendly path)
  - Domain, Language, Organization
  - Signed-in Account, Selected Software (list of checked apps)
- **Yes/Cancel** — nothing is sent until explicitly confirmed.

### 🔹 Message Center
- Color-coded `RichTextBox` log with real-time feedback
- Levels: `[INFO]` (blue), `[SUCCESS]` (green), `[WARN]` (orange), `[ERROR]` (red)
- Two buttons: **Clear** (wipes the log) and **Copy to Clipboard** (copies all log text)
- Auto-retry prompt on API failure: "API call failed. Retry? [Yes] [No]" (2 attempts max)

### 🔹 Auto-Clear After Success
- After a successful pre-stage: MAC, Computer Name, and OU selection are **automatically cleared**
- The technician can immediately start entering the next device
- Eliminates a common source of human error (duplicate registrations with the same MAC)

---

## ⚙️ Requirements

| Requirement | Minimum | Note |
|-------------|---------|------|
| PowerShell | 5.1+ | For `.ps1` execution (or use the compiled EXE — no PowerShell needed) |
| .NET Framework | 4.6.2+ | WPF, AD auth, LDAP, TLS |
| SCCM | AdminService REST API enabled on the SMS Provider over HTTPS | Required for the tool to function |
| Network | HTTPS (typically port 443) to the SMS Provider; LDAP (port 389) to a domain controller | The workstation running the tool needs both |
| Permissions | SCCM RBAC role for the signed-in user | Import `Helpdesk OSD Pre-Staging Operator.xml` for Helpdesk operators |
| Domain credentials | Any AD account with the RBAC role assigned | The tool validates credentials and uses them for SCCM API calls |

---

## 🚀 How to Run

### Option 1 — PowerShell Script (Default)
```powershell
.\SCCM-OSD-PreStaging.ps1
```
Uses Momar Tech defaults. The technician signs in, enters MAC + name, picks OU + software, clicks Pre-Stage.

### Option 2 — Compiled EXE (PSWrap)
```
SCCM-OSD-PreStaging.exe
```
Double-click. No PowerShell console visible. Compiled with PSWrap with these settings:
- Platform Target: `x64`
- Apartment State: `STA`
- Output Type: `GUI`
- Self-signed with PSWrap's built-in signing

### Option 3 — Custom Organization
```powershell
.\SCCM-OSD-PreStaging.ps1 -CompanyName "Contoso Ltd" -CompanyShort "CT" `
    -Department "Infrastructure" -DomainName "contoso.com" `
    -SearchBase "OU=Workstations,DC=contoso,DC=com" `
    -DomainController "dc01.contoso.com" `
    -SccmSiteCode "CT1" -SccmServer "sccm.contoso.com" `
    -OrgName "Contoso Ltd" -DefaultLanguage "en-US" `
    -Software "Chrome|App_Chrome|true","Firefox|App_Firefox|true","7-Zip|App_7Zip|false"
```

---

## ⚙️ Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-CompanyName` | `Momar Tech` | Window title, header text, dialog headers |
| `-CompanyShort` | `MT` | 2-3 char abbreviation in the gold logo badge |
| `-Department` | `IT Operations` | Header subtitle, footer text |
| `-DomainName` | `momar.local` | AD domain for sign-in auth + domain join variable |
| `-SearchBase` | `OU=Domain Computers,DC=Momar,DC=local` | DN of the root OU for LDAP browsing |
| `-DomainController` | `dc01.momar.local` | DC hostname/FQDN for LDAP queries |
| `-SccmSiteCode` | `MT1` | 3-character SCCM site code (used in API URL construction) |
| `-SccmServer` | `SCCM.Momar.local` | SMS Provider FQDN (AdminService host) |
| `-OrgName` | `Momar Tech` | Written to `OSDRegisteredOrgName` TS variable |
| `-DefaultLanguage` | `en-US` | OS language after deployment (`en-US` / `ar-SA`) |
| `-Software` | `"Cisco AnyConnect VPN\|App_CiscoAnyConnect\|true"` | `DisplayName\|TSVariableName\|DefaultChecked` |

---

## 🔄 Typical Workflow (Step by Step)

1. **🔑 Sign In** — helpdesk technician enters domain credentials. `PrincipalContext.ValidateCredentials` checks against AD. Green banner on success. Auth panel collapses to "Signed in as DOMAIN\User" badge.

2. **📝 Enter Device Details** — technician types the MAC address (formats automatically to `XX:XX:XX:XX:XX:XX` with uppercase hex). Types the desired computer name (max 15 chars).

3. **🌐 Select Language** — clicks `English` or `Arabic`. Sets the `OSDLanguage` variable.

4. **📂 Choose Target OU** — searches for the destination OU in the live DataGrid. Types in the search box to filter (e.g., "Engineering" → only Engineering-related OUs shown). Clicks a row to select. Breadcrumb shows friendly path. Selected OU indicator turns green.

5. **☑️ Pick Software** — checks the applications to install. Hover over each checkbox to see the TS variable name. Unchecked apps are simply not installed.

6. **✅ Confirmation Dialog** — clicks Pre-Stage. A full-detail WPF dialog appears listing EVERY piece of data: name, MAC, OU (DN + friendly), domain, language, org, account, software list. **Must click Yes** to send to SCCM. Cancel goes back to the form.

7. **🚀 API Calls Execute** — `Set-AdminServiceTls` applies TLS + cert bypass → `POST ImportMachineEntry` registers the device → `GET SMS_R_System` verifies it exists → `POST SMS_MachineSettings` injects OSD variables. Each step logged in the message center.

8. **🎉 Success** — green success message. MAC, Computer Name, and OU fields are cleared automatically. The message center shows "Device pre-staged." Ready for the next device.

9. **🖥 The Device Ships** — on the other end, the device arrives. Staff unbox it, connect Ethernet, PXE boot. SCCM recognizes the MAC from the pre-staged record and applies all the injected OSD variables automatically.

---

## 🔌 AdminService REST API — Full Detail

### Step 1: Register the Machine (always overwrite)

```powershell
$importBody = @{
    MACAddress              = $mac
    NetbiosName             = $computerName
    OverwriteExistingRecord = $true      # Always overwrite existing records
} | ConvertTo-Json

$importResult = Invoke-RestMethod -Uri "$baseUrl/AdminService/wmi/SMS_Site.ImportMachineEntry" `
    -Method Post -Body $importBody -ContentType "application/json" `
    @restCommon
```

The response includes the `ResourceID` directly in most SCCM versions (fast path). If the `ResourceID` is not present, the script polls `SMS_R_System` with the new computer name (6 attempts, 2s interval, ~12s total) to handle SCCM database write latency.

### Step 2: Extract ResourceID (response-first, poll-fallback)

```powershell
# Fast path — most AdminService versions return ResourceID directly
if ($importResult.ResourceID) {
    $resourceId = $importResult.ResourceID
}
else {
    # Polling fallback with exponential backoff
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $resp = Invoke-RestMethod -Uri `
            "$baseUrl/AdminService/wmi/SMS_R_System?`$filter=NetbiosName eq '$computerName'" `
            -Method Get @restCommon
        if ($resp.value -and $resp.value.Count -gt 0) {
            $resourceId = $resp.value[0].ResourceID
            break
        }
        Start-Sleep -Seconds 2
    }
}
```

### Step 3: Inject OSD Variables

```powershell
$variables = @(
    @{ Name = "OSDComputerName";     Value = $computerName;   IsMasked = $false },
    @{ Name = "OSDDomainOUName";     Value = $selectedOU.DN;  IsMasked = $false },
    @{ Name = "OSDLanguage";         Value = $language;       IsMasked = $false },
    @{ Name = "OSDRegisteredOrgName"; Value = $orgName;       IsMasked = $false },
    @{ Name = "OSDDomainName";       Value = $domainName;     IsMasked = $false },
    @{ Name = "OSDJoinAccount";      Value = $username;       IsMasked = $false },
    @{ Name = "OSDJoinPassword";     Value = $password;       IsMasked = $true  }
)
# App_* variables for checked software
foreach ($cb in $checkedSoftware) {
    $variables += @{ Name = $cb.TSVar; Value = "TRUE"; IsMasked = $false }
}

$settingsBody = @{
    ResourceID       = $resourceId
    SourceSite       = $siteCode
    LocaleID         = 1033
    MachineVariables = $variables
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "$baseUrl/AdminService/wmi/SMS_MachineSettings" `
    -Method Post -Body $settingsBody -ContentType "application/json" @restCommon
```

### Variables Injected

| Variable | Source | Effect |
|----------|--------|--------|
| `OSDComputerName` | Computer Name text box | The machine will receive this NetBIOS name during OSD |
| `OSDDomainOUName` | Selected OU DN | Domain join places the computer directly in this OU |
| `OSDDomainName` | `-DomainName` parameter | Tells the domain join step which domain to join |
| `OSDLanguage` | Language radio buttons | System language after deployment |
| `OSDRegisteredOrgName` | `-OrgName` parameter | Sets the "Registered Owner" in System Properties |
| `OSDJoinAccount` | Signed-in username | Credentials for domain join (with join permissions) |
| `OSDJoinPassword` | Password (masked, hidden) | Credentials for domain join (hidden variable) |
| `App_*` (e.g. `App_Chrome`) | Checked checkboxes | Controls which applications install in the TS |

---

## 📊 Operational Safeguards

- ✅ **5-attempt auth lockout** — prevents brute force on the sign-in form
- 🔒 **Password handling** — stored in memory only. SCCM variable `OSDJoinPassword` is hidden. Never logged or persisted.
- 🛡 **TLS 1.2 + proxy bypass + cert bypass** — applied at startup and before every API call (double-hardened)
- 🔄 **ResourceID polling** — 6 attempts × 2s after `ImportMachineEntry` to handle SCCM database write latency
- 🔄 **API retry prompt (2 attempts)** on failure — shows a retry dialog before giving up
- 🧹 **Auto-clear fields** — MAC, name, and OU cleared after success. Prevents duplicate registrations.
- 📝 **Color-coded message center** — full audit trail of every API call with timestamps
- ✅ **MAC regex validation** — bad formats rejected before any API call is attempted

---

## 🐛 Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| **`403 Forbidden` from AdminService** | The signed-in user lacks SCCM RBAC permissions | Import `Helpdesk OSD Pre-Staging Operator.xml` in the SCCM console. Assign the user to the role. |
| **SSL/TLS certificate error** | Self-signed SCCM cert + C# bypass failed to compile | The script-block fallback handles this in interactive PowerShell. For EXE, ensure `Add-Type` succeeded (check the startup log). |
| **"No runspace available" in compiled EXE** | PSWrap EXE is trying to use the PowerShell script-block cert callback | This is exactly the bug the C# `SslBypass` class solves. Ensure `Add-Type` compiled successfully. Recompile the EXE. |
| **OU DataGrid is empty** | DC unreachable or credentials rejected | Verify `-DomainController` is correct and reachable. Sign in with valid domain credentials. Anonymous LDAP may fail if the workstation isn't domain-joined. |
| **MAC address rejected** | Input doesn't match the hex pattern | Let auto-format normalize it. Type all 12 hex characters without separators — the tool adds colons. Use uppercase A-F. |
| **Sign In button disabled permanently** | 5 failed authentication attempts | Restart the tool. There's no unlock — this is intentional security behavior. |
| **"Invalid site code" error** | Wrong `-SccmSiteCode` | Check the site code in the SCCM console. The site code is part of the AdminService URL: `https://SCCMServer/AdminService/wmi/`. Pass the correct 3-character code. |
| **API timeout** | Firewall blocking HTTPS to the SMS Provider | Ensure the workstation can reach `https://SCCMServer` on port 443 (or the configured AdminService port). Test: `Test-NetConnection $SccmServer -Port 443`. |
| **"Failed to retrieve ResourceID"** after successful import | SCCM database write latency — record not yet visible | Fixed in v1.0: the script now polls `SMS_R_System` for up to 12 seconds. `ImportMachineEntry` usually returns the ID directly. |

---

## 🔐 SCCM RBAC Security Role

The `Helpdesk OSD Pre-Staging Operator.xml` file is an SCCM Security Role that grants helpdesk operators **exactly the permissions needed** to pre-stage devices — no more, no less. This follows the principle of least privilege: operators can import computers and inject OSD variables, but cannot modify site settings, delete resources, or perform administrative tasks.

### What the Role Grants

| ObjectType | Permission | GrantedOperations | What It Allows |
|------------|------------|-------------------|----------------|
| **SMS_R_System** (Computer Objects) | Create | `1` | Import new computer records via `ImportMachineEntry` |
| **SMS_R_System** (Computer Objects) | Set Security Scope | `128` | Assign security scopes to imported devices |
| **SMS_R_System** (Computer Objects) | Read Resource | `4096` | Read computer object data (verify import, poll ResourceID) |
| **SMS_MachineSettings** (Machine Variables) | Create | `1` | Create machine settings record for OSD variables |
| **SMS_MachineSettings** (Machine Variables) | Set OSD Variables | `524288` | Inject all OSD variables (computer name, OU, domain, software, language, credentials) |

### Step-by-Step Setup

1. Open the **SCCM Administration Console**
2. Navigate: **Administration** → **Security** → **Security Roles**
3. Right-click **Security Roles** → **Import Security Role**
4. Browse to and select `Helpdesk OSD Pre-Staging Operator.xml` (in the tool's folder)
5. Click **Next** → **Close**
6. Navigate: **Administration** → **Security** → **Administrative Users**
7. Right-click **Administrative Users** → **Add User or Group**
8. Select the AD user/group that will use the Pre-Staging Tool
9. On the **Security Roles** tab, check `Helpdesk OSD Pre-Staging Operator`
10. On the **Security Scopes** tab, select the appropriate scope (e.g., Default)
11. Complete the wizard

### Why These Specific Permissions?

The Pre-Staging Tool uses the **SCCM AdminService REST API** which performs three operations:

1. **`ImportMachineEntry`** — creates the computer record (needs **Create** on SMS_R_System)
2. **`GET SMS_R_System`** — verifies the import succeeded (needs **Read Resource** on SMS_R_System)
3. **`POST SMS_MachineSettings`** — injects all 8+ OSD variables (needs **Create** + **Set OSD Variables** on SMS_MachineSettings)

The role also grants **Set Security Scope** so operators can assign the imported device to the correct collection scope.

### What the Role Does NOT Grant

| Permission | Why Excluded |
|------------|-------------|
| Delete Resource | Operators should not delete computers |
| Modify Resource | Only needed for editing existing records — Pre-Staging always creates new |
| Remote Tools | No remote control capability needed |
| Site Settings | Operators should not modify SCCM site configuration |
| Collection Management | Operators don't create or modify collections |
| Package/Program Management | Operators don't manage software packages

---

## 🖥 UI Layout

| Left Column | Right Column |
|-------------|--------------|
| 🔑 **Authentication Card** (Gold accent) — Username, Password, Sign In button. Collapses to badge after login. | 📊 **Pre-Staging Summary** (Gold accent) — Computer, Domain, Language, Account, Software |
| 💻 **Computer Name Card** (Navy accent) — Name text box, 15-char limit, green/red validation | ☑️ **Software Installation** (Navy accent) — Dynamic checkboxes with TS variable tooltips |
| 🖧 **MAC Address Card** (Navy accent) — MAC text box, auto-formatting, live regex validation | 🌐 **System Language** (Navy accent) — English / Arabic radio buttons |
| 📂 **Target OU Card** (Gold accent) — Search box, DataGrid (3 columns), selected OU breadcrumb, green indicator | 💬 **Message Center** (Navy accent, dark bg) — Color-coded log, Clear + Copy to Clipboard buttons |
| — | 🚀 **Pre-Stage Button** (Gold) — Triggers confirmation dialog → API flow |

---

## 🛡 Design Principles

- **No SCCM console requirement** — pure HTTPS REST API. The workstation needs .NET Framework and network access only.
- **C# delegate cert bypass** — compiled .NET method works in EXE threads without a PowerShell runspace. The script-block fallback exists for interactive use.
- **Pure .NET LDAP** — `LdapConnection` instead of ADSI COM. No `Import-Module ActiveDirectory` needed.
- **Card-based WPF design** — unified typography at 12/13/14/16pt tiers, all interactive controls at 28px height, custom WPF dialogs.
- **Fully parameterized** — zero hardcoded branding. Every visible string is a parameter.
- **PSWrap EXE compatible** — tested with PSWrap GUI: `x64` target, `STA` apartment, `GUI` output. Self-signed.

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
