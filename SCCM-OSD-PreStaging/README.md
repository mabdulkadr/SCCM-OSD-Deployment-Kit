# 📡 SCCM OSD Pre-Staging Tool

Quick reference for the WPF GUI tool that registers devices in SCCM before they arrive on-site.

> **Full documentation:** [`SCCM-OSD-PreStaging.md`](SCCM-OSD-PreStaging.md) — architecture, SSL bypass, RBAC details, troubleshooting.

---

## What Is It?

A standalone WPF GUI tool that uses the **SCCM AdminService REST API** over HTTPS to register bare-metal devices in SCCM. No SCCM console required on the workstation — just .NET Framework and network access.

> **Companion tool:** [`DeploymentWizard.ps1`](../DeploymentWizard/DeploymentWizard.md) is used on-site during OSD. This tool is for remote/off-site pre-staging.

---

## Quick Start

```powershell
.\SCCM-OSD-PreStaging.ps1
```

Or double-click the compiled EXE (PSWrap — no PowerShell console visible).

---

## Workflow

| Step | Action |
|------|--------|
| 1 | Sign in with domain credentials |
| 2 | Enter MAC address (auto-formatted) and computer name |
| 3 | Select language (English / Arabic) |
| 4 | Browse and select target OU via live LDAP search |
| 5 | Pick software from checkboxes |
| 6 | Review full-detail confirmation dialog |
| 7 | Click Pre-Stage → device registered in SCCM |
| 8 | Fields auto-clear for next device |

When the device is powered on and PXE-booted, SCCM already knows everything about it.

---

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-CompanyName` | `Momar Tech` | Window title |
| `-CompanyShort` | `MT` | Logo badge text (2-3 chars) |
| `-Department` | `IT Operations` | Header subtitle |
| `-DomainName` | `momar.local` | AD domain for auth + join |
| `-SearchBase` | `OU=Domain Computers,DC=Momar,DC=local` | LDAP root OU |
| `-DomainController` | `dc01.momar.local` | DC hostname |
| `-SccmSiteCode` | `MT1` | SCCM site code |
| `-SccmServer` | `SCCM.Momar.local` | AdminService FQDN |
| `-OrgName` | `Momar Tech` | Written to `OSDRegisteredOrgName` |
| `-DefaultLanguage` | `en-US` | OS language |
| `-Software` | Cisco AnyConnect | `Name\|TSVar\|Default` |

---

## Requirements

| Requirement | Minimum |
|-------------|---------|
| PowerShell | 5.1+ (or compiled EXE) |
| .NET Framework | 4.6.2+ |
| SCCM | AdminService REST API on SMS Provider (HTTPS) |
| Network | HTTPS to SCCM, LDAP to DC |
| RBAC Role | Import `Helpdesk OSD Pre-Staging Operator.xml` |

---

## RBAC Setup (One-Time)

1. **SCCM Console → Administration → Security → Security Roles**
2. Right-click → **Import Security Role** → select the XML file
3. **Administrative Users → Add User or Group** → pick your helpdesk team
4. Assign the `Helpdesk OSD Pre-Staging Operator` role
5. Select the appropriate Security Scope

For full RBAC details, see the [full documentation](SCCM-OSD-PreStaging.md).

---

## Common Issues

| Problem | Fix |
|---------|-----|
| `403 Forbidden` | RBAC role not imported or assigned to user |
| SSL certificate error | C# bypass handles it — check startup log if using EXE |
| OU DataGrid empty | Check DC connectivity, sign in with valid credentials |
| MAC rejected | Type 12 hex characters — tool adds colons automatically |
| Sign-in disabled | 5 failed attempts — restart tool |
| API timeout | Port 443 to SMS Provider must be open |
