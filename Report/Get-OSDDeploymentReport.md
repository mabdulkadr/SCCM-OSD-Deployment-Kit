# 📊 Get-OSDDeploymentReport.ps1

Generates an HTML executive report of your OSD deployment status, then optionally sends it via email using Microsoft Graph API.

> Runs as a standalone script — not part of the Task Sequence. Schedule it (via Task Scheduler or similar) to run daily/weekly for ongoing visibility.

---

## What It Does

Queries SCCM WMI for OSD deployment data and produces a comprehensive HTML report with:

- **Summary cards** — Total / Success / Failed / Running counts
- **Deployment summary** — Compliance statistics per deployment
- **Per-TS breakdown** — Success rate bars per Task Sequence
- **Duration statistics** — Average, fastest, slowest deployment times
- **Device details** — Per-device status, phase, duration, and error messages

The report is Outlook-safe (inline CSS, table-based layout, no JavaScript).

---

## How to Run

```powershell
# Generate report and send via email (default)
.\Report\Get-OSDDeploymentReport.ps1

# Generate report only (no email)
.\Report\Get-OSDDeploymentReport.ps1 -SendEmail:$false

# Send to different recipients
.\Report\Get-OSDDeploymentReport.ps1 -UserTo "admin@your-domain.com", "helpdesk@your-domain.com"
```

---

## Configuration

### Replace These Placeholders in the Script

| Placeholder | Variable | What to Put |
|---|---|---|
| `<YOUR_TENANT_ID>` | `$TenantId` | Azure AD tenant GUID |
| `<YOUR_CLIENT_ID>` | `$ClientId` | Azure AD app client GUID |
| `<YOUR_CLIENT_SECRET>` | `$ClientSecretDefault` | Azure AD app client secret |
| `<YOUR_SERVICE_EMAIL>` | `$UserFrom` | Sender mailbox (must have Send As permission) |
| `<YOUR_EMAIL>` | `$UserTo` | Default recipient email |

### Script Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-SccmServer` | `SCCM.Momar.local` | SCCM site server FQDN |
| `-SiteCode` | `MT1` | 3-character SCCM site code |
| `-SendEmail` | `$true` | Send the report via email |
| `-Subject` | `SCCM OSD Deployment Status` | Email subject line |
| `-UserFrom` | `<YOUR_SERVICE_EMAIL>` | Sender mailbox |
| `-UserTo` | `@("<YOUR_EMAIL>")` | Recipients |

---

## Data Sources

The script queries these WMI classes:

| WMI Class | Purpose |
|-----------|---------|
| `SMS_TaskSequenceExecutionStatus` | Per-step execution records |
| `SMS_DeploymentSummary` (FeatureType=7) | Compliance statistics |
| `SMS_R_System` | Computer name, MAC, OS info |
| `SMS_TaskSequencePackage` | Task Sequence names |
| `SMS_Advertisement` | Deployment details |

---

## Email Setup (Microsoft Graph API)

Uses OAuth 2.0 client credentials flow — **no SMTP, no basic auth**.

**Required Azure AD setup:**

1. Register an app in Azure AD (e.g., `OSD-Report-Sender`)
2. Grant the `Mail.Send` **Application** permission
3. Grant admin consent
4. Add `Send As` permission for the sender mailbox in Exchange
5. Copy the Tenant ID, Client ID, and Client Secret into the script

**Secret resolution order:**

1. `-ClientSecret` parameter (SecureString)
2. `$env:OSD_REPORT_CLIENT_SECRET` environment variable
3. `-ClientSecretDefault` parameter
4. Embedded default value

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| PowerShell | 5.1+ |
| SCCM WMI access | Read access to `root\sms\site_<SiteCode>` |
| Azure AD app | With `Mail.Send` (Application) permission |
| Admin consent | Granted in Azure AD |
| Network | HTTPS to `login.microsoftonline.com` and `graph.microsoft.com` |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Cannot connect to SCCM WMI | Verify `-SccmServer` and `-SiteCode`; test: `Get-WmiObject -Namespace "root\sms\site_MT1" -Class SMS_Site` |
| No OSD execution records found | The TS hasn't been deployed to any collection yet |
| Failed to acquire Graph token | Check TenantId, ClientId, and Client Secret |
| `AADSTS700016` | Wrong ClientId or app not found in tenant |
| `AADSTS7000215` | Invalid client secret — regenerate in Azure AD |
| `ErrorSendAsDenied` | Add `Send As` permission for the mailbox in Exchange |
| Cannot reach Graph endpoints | Allow outbound HTTPS to `graph.microsoft.com` and `login.microsoftonline.com` on port 443 |

---

## Related Documentation

- [Send-QUExchangeMail.md](Send-QUExchangeMail.md) — The Graph API email module used internally
