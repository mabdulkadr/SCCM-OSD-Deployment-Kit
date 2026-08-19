# 📡 SCCM OSD Pre-Staging Tool

A WPF GUI tool that lets helpdesk operators register bare-metal devices in SCCM **before the device arrives on-site**. Uses the **SCCM AdminService REST API** over HTTPS — no SCCM console, no module, no admin workstation setup required.

> **Companion tool:** [`DeploymentWizard.ps1`](../DeploymentWizard/DeploymentWizard.md) is used **on-site** during the OSD process. This tool is for **remote/off-site pre-staging** before the device even arrives.

---

## What Problem Does This Solve?

When a remote site receives new hardware, an IT technician typically has to:

1. Travel to the remote site, OR
2. Ask someone at the remote site to walk through complex SCCM console steps

This tool removes that friction. The helpdesk operator runs it from their office workstation, enters the device details, and the device becomes "PXE-ready" in SCCM. When the employee boots the device from network, SCCM already knows everything about it.

---

## How It's Used

**Standalone tool** — run it on any Windows workstation with HTTPS access to the SCCM AdminService:

```powershell
.\SCCM-OSD-PreStaging.ps1
```

Or use a pre-compiled EXE (built with PSWrap) — double-click, no PowerShell console.

---

## Workflow

```
1. Operator signs in with domain credentials
2. Enters device details:
   - MAC address (auto-formatted to XX:XX:XX:XX:XX:XX)
   - Computer name (max 15 chars)
3. Selects language (English / Arabic)
4. Searches and selects target OU via LDAP browse
5. Picks software from checkboxes
6. Reviews confirmation dialog (full detail preview)
7. Clicks Pre-Stage → API calls register the device
8. Fields auto-clear for next device
9. Employee boots device from network → SCCM deploys automatically
```

---

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-CompanyName` | `Momar Tech` | Window title, header, dialogs |
| `-CompanyShort` | `MT` | 2-3 char logo badge text |
| `-Department` | `IT Operations` | Header subtitle |
| `-DomainName` | `momar.local` | AD domain for auth + join |
| `-SearchBase` | `OU=Domain Computers,DC=Momar,DC=local` | LDAP search base |
| `-DomainController` | `dc01.momar.local` | DC for LDAP queries |
| `-SccmSiteCode` | `MT1` | 3-character SCCM site code |
| `-SccmServer` | `SCCM.Momar.local` | AdminService FQDN |
| `-OrgName` | `Momar Tech` | Written to `OSDRegisteredOrgName` |
| `-DefaultLanguage` | `en-US` | OS language |
| `-Software` | Cisco AnyConnect | `Name\|TSVar\|Default` |

---

## API Flow

```
Operator fills form → clicks Pre-Stage
    │
    ├── Step 1: Apply TLS 1.2 + SSL certificate bypass
    ├── Step 2: POST ImportMachineEntry (MAC + Name → ResourceID)
    ├── Step 3: GET SMS_R_System (verify record exists, extract ResourceID)
    └── Step 4: POST SMS_MachineSettings (inject 8+ OSD variables)
    │
    ▼
Device is PXE-ready in SCCM
```

### Step-by-Step

**Step 1 — TLS Setup:**
- Forces TLS 1.2
- Attaches C#-compiled SSL bypass (handles self-signed certificates)
- Bypasses proxy, increases connection limit

**Step 2 — Register Machine:**
- Endpoint: `POST /AdminService/wmi/SMS_Site.ImportMachineEntry`
- Body: `{ MACAddress, NetbiosName, OverwriteExistingRecord: true }`
- Response: `{ ResourceID, MachineExists, ReturnValue }`

**Step 3 — Verify Resource:**
- If `ResourceID` is in the response → use it directly (fast path)
- Otherwise → poll `GET /AdminService/wmi/SMS_R_System` up to 6 times (2s intervals) to handle SCCM DB write latency

**Step 4 — Inject OSD Variables:**
- Endpoint: `POST /AdminService/wmi/SMS_MachineSettings`
- Body: `{ ResourceID, SourceSite, MachineVariables[] }`
- 8+ variables injected in a single call

---

## OSD Variables Injected

| Variable | Effect |
|----------|--------|
| `OSDComputerName` | NetBIOS name used during OSD |
| `OSDDomainOUName` | Target OU for domain join |
| `OSDDomainName` | Domain to join |
| `OSDLanguage` | System language |
| `OSDRegisteredOrgName` | Registered Owner in System Properties |
| `OSDJoinAccount` | Domain join credentials (username) |
| `OSDJoinPassword` | Domain join credentials (password, hidden) |
| `App_*` | Controls which applications install |

All variables are available to the Task Sequence automatically when the device PXE boots.

---

## Key Features

- **MAC auto-formatting** — Type 12 hex characters, tool adds colons automatically
- **Live OU search** — Client-side filtering, works on any LDAP query size
- **Confirmation dialog** — Full-detail preview before sending to SCCM
- **Auto-clear after success** — MAC, name, OU cleared for next device
- **API retry** — Up to 2 attempts on failure with retry prompt
- **Message Center** — Color-coded log with Copy to Clipboard
- **C# SSL bypass** — Works in compiled EXEs where PowerShell script-block callbacks fail

---

## SSL/TLS Architecture

SCCM AdminService often uses a self-signed certificate. The standard PowerShell workaround for accepting any certificate fails in compiled EXEs (no PowerShell runspace on .NET thread-pool threads).

**The solution:** A C#-compiled static class loaded via `Add-Type`. This is a true .NET delegate — no PowerShell runspace needed. A script-block fallback is kept for interactive PowerShell use.

TLS 1.2 is applied at script startup AND before every API call (double-hardened).

---

## SCCM RBAC Role

The included `Helpdesk OSD Pre-Staging Operator.xml` file grants helpdesk operators **exactly the permissions needed** — no more, no less.

### What It Grants

| Object Type | Permission | What It Allows |
|-------------|------------|----------------|
| `SMS_R_System` | Create | Import new computer records |
| `SMS_R_System` | Read Resource | Verify the import succeeded |
| `SMS_R_System` | Set Security Scope | Assign the device to the correct scope |
| `SMS_MachineSettings` | Create | Create machine settings record |
| `SMS_MachineSettings` | Set OSD Variables | Inject all OSD variables |

### What It Does NOT Grant

- Delete Resource
- Modify Resource
- Remote Tools
- Site Settings
- Collection Management
- Package/Program Management

### Setup Steps

1. **SCCM Console → Administration → Security → Security Roles**
2. Right-click → **Import Security Role**
3. Select `Helpdesk OSD Pre-Staging Operator.xml`
4. **Administration → Administrative Users → Add User or Group**
5. Select the AD user/group for your helpdesk team
6. Assign the `Helpdesk OSD Pre-Staging Operator` role
7. Select the appropriate Security Scope

---

## Requirements

| Requirement | Minimum |
|-------------|---------|
| PowerShell | 5.1+ (or use the compiled EXE) |
| .NET Framework | 4.6.2+ |
| SCCM | AdminService REST API on SMS Provider (HTTPS) |
| Network | HTTPS to SCCM, LDAP to DC |
| Permissions | RBAC role (included) + domain credentials |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `403 Forbidden` | Import `Helpdesk OSD Pre-Staging Operator.xml` RBAC role |
| SSL certificate error | C# bypass handles it — check startup log if using EXE |
| "No runspace available" in EXE | Ensure `Add-Type` compiled successfully; recompile if needed |
| OU DataGrid empty | Verify DC connectivity, sign in with valid credentials |
| MAC address rejected | Type 12 hex characters — tool adds colons automatically |
| Sign-in disabled | 5 failed attempts — restart tool (intentional security) |
| "Invalid site code" | Check `-SccmSiteCode` matches your SCCM console |
| API timeout | Port 443 to SMS Provider must be open from this workstation |
| "Failed to retrieve ResourceID" | Polls up to 12 seconds — should succeed on busy servers |

---

## Quick Reference

For a shorter overview, see the [README.md](README.md) in this folder.
