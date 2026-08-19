# 🖥 Deployment Wizard

The interactive WPF wizard that runs in WinPE during the SCCM OSD Task Sequence. Collects all the information the task sequence needs (computer name, OU, credentials, software, language) and writes it to Task Sequence variables.

> **Note:** This is the wizard application itself. The TS entry point that launches it is [`Start-DeploymentWizard.ps1`](Start-DeploymentWizard.md). Both files must be in the same `DeploymentWizard/` folder in your SCCM package.

---

## What It Does

When the technician boots a device and reaches this step in the task sequence:

1. **Wizard opens** and attempts an anonymous LDAP bind to load the OU list
2. **Technician signs in** with domain credentials (validated against Active Directory)
3. **Technician fills in**:
   - Computer name (max 15 characters, no special characters)
   - Target OU (live-search DataGrid, browse your AD structure)
   - Software to install (dynamic checkboxes)
   - OS language (English or Arabic)
4. **Technician clicks Deploy** → wizard writes all values to TSEnvironment → closes

The downstream task sequence steps then use these values automatically (domain join uses the OU and credentials, application install steps read the `App_*` variables, etc.).

---

## Configuration

Configure the wizard via the TS step parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-CompanyName` | `Momar Tech` | Organization name shown in UI |
| `-CompanyShort` | `MT` | 2-3 char logo badge text |
| `-Department` | `IT Operations` | Header subtitle |
| `-DomainName` | `momar.local` | AD domain FQDN |
| `-SearchBase` | `OU=Domain Computers,DC=Momar,DC=local` | LDAP search base DN |
| `-DomainController` | `dc01.momar.local` | DC for connectivity tests |
| `-SccmServer` | `sccm.momar.local` | SCCM Management Point FQDN |
| `-OrgName` | `Momar Tech` | Written to `OSDRegisteredOrgName` |
| `-DefaultLanguage` | `en-US` | Default OS language (`en-US` or `ar-SA`) |
| `-Software` | Cisco AnyConnect example | `DisplayName\|TSVariableName\|DefaultChecked` |

### Software Parameter Format

The `-Software` parameter accepts an array of strings in this format:

```
DisplayName|TSVariableName|DefaultChecked
```

**Example:**

```powershell
-Software @(
    "Google Chrome|App_Chrome|true",
    "Mozilla Firefox|App_Firefox|false",
    "Microsoft Office|App_Office|true"
)
```

Each checked box becomes `TRUE` in the corresponding `App_*` Task Sequence variable. Reference these in your application install steps using SCCM's `%VariableName%` syntax.

---

## Task Sequence Variables Written

| Variable | Source | Auto-Consumed by SCCM? |
|----------|--------|------------------------|
| `OSDComputerName` | Wizard input | ✅ Yes (Apply Windows Settings) |
| `OSDDomainName` | `-DomainName` parameter | ✅ Yes (Apply Network Settings) |
| `OSDDomainOUName` | Selected OU DN | ✅ Yes (Apply Network Settings) |
| `OSDJoinAccount` | Credentials | ✅ Yes (Apply Network Settings) |
| `OSDJoinPassword` | Credentials (hidden) | ✅ Yes (Apply Network Settings) |
| `OSDRegisteredOrgName` | `-OrgName` parameter | ✅ Yes (Apply Windows Settings) |
| `OSDLanguage` | Language picker | � Custom — use in conditions |
| `App_*` | Checked checkboxes | ❌ Custom — use `%App_Chrome%` in conditions |

---

## Key Features

### 🔐 AD Authentication

- Validates credentials via `PrincipalContext.ValidateCredentials`
- 5 failed attempts → Sign In button permanently disabled (must restart wizard)
- Password stored in memory only — never written to disk or logs
- Credentials reused for authenticated LDAP bind

### 🗂 LDAP OU Browser

- Pure .NET `LdapConnection` — no ADSI COM dependency
- Works in WinPE (where traditional `DirectorySearcher` fails)
- Live search DataGrid with horizontal scroll
- Breadcrumb path display: `DN` → `Top / Parent / Child` friendly format
- Selected OU indicator turns green when picked

### 📝 Software Selection

- Dynamic checkboxes generated from `-Software` parameter
- Hover tooltip shows the TS variable name
- Checked items → `TRUE` value in `App_*` TS variables

### 🌐 Language Selection

- Radio buttons for English (`en-US`) and Arabic (`ar-SA`)
- Writes `OSDLanguage` variable — your TS uses it to choose which OS image to apply
- One Task Sequence supports both languages — no separate TS needed

### 🛡 WinPE Safety

- MessageBox fallback when XAML rendering fails
- try/catch on every dialog
- Topmost window stays above other deployment windows

---

## Requirements

| Requirement | Minimum |
|-------------|---------|
| PowerShell | 5.1+ |
| .NET Framework | 4.6.2+ |
| WinPE | 10.0.17763+ (with WinPE-PowerShell + WinPE-NetFX) |
| AD Domain | Connectivity to a DC |
| SCCM/MECM | CB 1902+ (for `TSEnvironment` COM) |

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|--------------|-----|
| Wizard doesn't launch | Scripts in different folders | Both `.ps1` files must be in same `DeploymentWizard/` folder |
| Wizard blank in WinPE | Missing WinPE-NetFX | Add WinPE-NetFX component to boot image |
| OU list empty in WinPE | Anonymous LDAP fails | Sign in — credentials are reused for LDAP bind |
| "Cannot reach domain" | DC unreachable | `Test-NetConnection dc01.your-domain.local -Port 389` |
| Sign-in disabled | 5 failed attempts | Restart wizard (intentional security behavior) |
| "Not inside Task Sequence" warning | Running outside SCCM | Expected when testing — TS variables won't persist |

---

## Related Documentation

- [Start-DeploymentWizard.md](Start-DeploymentWizard.md) — The TS wrapper that launches this wizard
- [Technical Architecture](../technical-architecture.md) — Deep dive into wizard internals
