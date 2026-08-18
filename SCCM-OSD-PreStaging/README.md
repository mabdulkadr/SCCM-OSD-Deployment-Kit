# 🚀 SCCM OSD Pre-Staging Tool — Quick Reference

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)
![GUI](https://img.shields.io/badge/GUI-WPF-purple.svg)
![SCCM](https://img.shields.io/badge/SCCM-AdminService%20REST-9C27B0.svg)
![Version](https://img.shields.io/badge/version-1.0-green.svg)

---

## 📖 Overview

A **WPF GUI tool** for pre-staging bare-metal devices in **SCCM/MECM** before PXE boot. Uses the **SCCM AdminService REST API** over HTTPS — **no local SCCM console required**.

> **Companion Tool:** [`DeploymentWizard.ps1`](../DeploymentWizard/DeploymentWizard.md) — for on-site Task Sequence deployment. This tool is for **remote/off-site pre-staging**.

> 📖 **Full documentation:** [`SCCM-OSD-PreStaging.md`](SCCM-OSD-PreStaging.md) — architecture, SSL bypass, API flow, troubleshooting, UI layout.

---

## 🚀 Quick Start

### Default (Momar Tech)
```powershell
.\SCCM-OSD-PreStaging.ps1
```

### Custom Organization
```powershell
.\SCCM-OSD-PreStaging.ps1 -CompanyName "Contoso Ltd" -CompanyShort "CT" `
    -Department "Infrastructure" -DomainName "contoso.com" `
    -SearchBase "OU=Workstations,DC=contoso,DC=com" `
    -DomainController "dc01.contoso.com" `
    -SccmSiteCode "CT1" -SccmServer "sccm.contoso.com" `
    -DefaultLanguage "ar-SA"
```

### Build to EXE (PSWrap)
```
Platform Target: x64 | Apartment State: STA | Output Type: GUI
```

---

## ⚙️ Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-CompanyName` | `Momar Tech` | Organization name in window title |
| `-CompanyShort` | `MT` | Logo badge text (2-3 chars) |
| `-Department` | `IT Operations` | Header/footer subtitle |
| `-DomainName` | `momar.local` | AD domain for auth and join |
| `-SearchBase` | `OU=Domain Computers,DC=Momar,DC=local` | Root OU DN for LDAP |
| `-DomainController` | `dc01.momar.local` | DC hostname for LDAP |
| `-SccmSiteCode` | `MT1` | SCCM site code |
| `-SccmServer` | `SCCM.Momar.local` | SMS Provider FQDN |
| `-OrgName` | `Momar Tech` | Written to `OSDRegisteredOrgName` |
| `-DefaultLanguage` | `en-US` | OS language (`en-US` / `ar-SA`) |
| `-Software` | `"Cisco AnyConnect VPN\|App_CiscoAnyConnect\|true"` | Format: `DisplayName\|TSVar\|Default` |

---

## 🔐 SCCM RBAC Security Role

The `Helpdesk OSD Pre-Staging Operator.xml` file is a pre-built SCCM Security Role that grants **exactly the permissions needed** for device pre-staging — no more, no less.

| ObjectType | Permission | What It Allows |
|------------|------------|----------------|
| **SMS_R_System** | Create + Read Resource + Set Security Scope | Import new computers and verify the import |
| **SMS_MachineSettings** | Create + Set OSD Variables | Inject all OSD variables (name, OU, domain, software, language, credentials) |

### Setup Steps

1. In SCCM Admin Console: **Administration → Security → Security Roles → Import Security Role**
2. Select `Helpdesk OSD Pre-Staging Operator.xml` from this folder
3. Navigate to **Administrative Users → Add User or Group**
4. Select the AD user/group for the helpdesk team
5. Assign the `Helpdesk OSD Pre-Staging Operator` role
6. Scope to the appropriate collections (e.g., "All Workstations")

> **Full documentation:** [`SCCM-OSD-PreStaging.md`](SCCM-OSD-PreStaging.md) — includes detailed permission breakdown, what the role does NOT grant, and why each permission is needed.

---

## ⚙️ Requirements

| Requirement | Minimum |
|-------------|---------|
| PowerShell | 5.1+ (or compiled EXE) |
| .NET Framework | 4.6.2+ |
| SCCM | AdminService REST API on SMS Provider (HTTPS) |
| Network | HTTPS to SCCM, LDAP to DC |
| Permissions | SCCM RBAC + Domain credentials |

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
