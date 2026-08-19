# 🚀 Start-DeploymentWizard.ps1

The Task Sequence wrapper for the Deployment Wizard. This is the script you actually run from the SCCM Task Sequence — it validates, launches, monitors, and verifies the wizard.

> The wizard application itself is [`DeploymentWizard.ps1`](DeploymentWizard.md). Both files must be in the same `DeploymentWizard/` folder in your SCCM package.

---

## How It's Used

**In SCCM Console:**

1. Open your Task Sequence
2. Add Step → **Run PowerShell Script**
3. Configure:
   - **Script name:** `Start-DeploymentWizard.ps1`
   - **Execution policy:** `Bypass`
   - **Timeout:** `30` minutes (the wizard waits for technician interaction)
   - **Package:** `SCCM-OSD-Deployment-Kit`
4. Fill in the parameters (see below)

---

## Configuration

Fill in the TS step parameters with your organization values:

| Parameter | Default | Required | Description |
|-----------|---------|----------|-------------|
| `-CompanyName` | `Momar Tech` | No | Organization name in UI |
| `-CompanyShort` | `MT` | No | 2-3 char logo badge |
| `-Department` | `IT Operations` | No | Header subtitle |
| `-DomainName` | `momar.local` | ✅ **Yes** | AD domain FQDN |
| `-SearchBase` | `OU=Domain Computers,DC=Momar,DC=local` | ✅ **Yes** | LDAP root OU |
| `-DomainController` | `dc01.momar.local` | No | DC for auth/LDAP |
| `-SccmServer` | `sccm.momar.local` | No | SCCM MP FQDN |
| `-OrgName` | `Momar Tech` | No | Written to `OSDRegisteredOrgName` |
| `-DefaultLanguage` | `en-US` | No | OS language |
| `-Software` | Cisco AnyConnect | No | `Name\|TSVar\|Default` |

> ⚠️ `-DomainName` and `-SearchBase` are **required** — the script exits with code 1 if either is empty.

---

## Why a Wrapper?

You might wonder why this script exists separately from the wizard. Two reasons:

1. **Process isolation** — the wizard runs in a child `powershell.exe` process. If the wizard UI crashes or hangs, the Task Sequence step is not affected. The wrapper can gracefully exit and the TS can continue.

2. **Variable verification** — after the wizard closes, the wrapper reads back ALL the variables from `TSEnvironment` and logs them to `smsts.log`. This gives you a single audit point — you can see exactly what values were set for every deployment.

---

## Execution Flow

```
TS Step: Start-DeploymentWizard.ps1
   │
   ├─ 1. Validate -DomainName and -SearchBase (exit 1 if empty)
   ├─ 2. Locate DeploymentWizard.ps1 (must be in same folder)
   ├─ 3. Log configuration (company, domain, search base, etc.)
   ├─ 4. Launch wizard in child powershell.exe process
   │
   ▼
DeploymentWizard.ps1 (WPF wizard — user interaction)
   │
   ├─ Technician fills fields, clicks Deploy
   ├─ Wizard writes variables to TSEnvironment
   └─ Wizard closes
   │
   ▼
Start-DeploymentWizard.ps1 (verification)
   │
   ├─ 5. Read back all variables from TSEnvironment
   ├─ 6. Log every variable to smsts.log (password masked)
   └─ 7. Exit 0 (success) or 1 (failure)
```

---

## Package Structure

Both scripts must be in the same `DeploymentWizard/` folder inside your SCCM package:

```
SCCM Package Source\
└── DeploymentWizard\
    ├── Start-DeploymentWizard.ps1    ← TS step runs this
    └── DeploymentWizard.ps1          ← Wrapper finds and launches this
```

The wrapper uses `$PSScriptRoot` to locate the wizard — if they're in different folders, the wrapper exits with an error.

---

## Exit Codes

| Code | Meaning | TS Behavior |
|------|---------|-------------|
| `0` | Wizard completed successfully, all variables written and verified | Proceed to next step |
| `1` | Parameter missing, wizard file not found, wizard crashed, or wizard cancelled | TS step fails (unless "Continue on error" is checked) |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `[ERROR] DeploymentWizard.ps1 not found` | Both files must be in the same folder |
| `[ERROR] DomainName is required` | Pass `-DomainName` in the TS step parameters |
| `[WARN] TSEnvironment not available` | Expected when running outside a TS (e.g., for testing) |
| Wizard never appears | Add WinPE-PowerShell + WinPE-NetFX to boot image |
| Variable not consumed by next step | Check `smsts.log` for exact variable names |

---

## Related Documentation

- [DeploymentWizard.md](DeploymentWizard.md) — The wizard application itself
- [Technical Architecture](../technical-architecture.md) — Deep dive into the wrapper architecture
