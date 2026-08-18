# Get-OSDDeploymentReport.ps1

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)
![SCCM](https://img.shields.io/badge/SCCM-WMI-orange.svg)
![Version](https://img.shields.io/badge/version-2.0-green.svg)

---

## Configuration Required

> Replace the Azure AD credentials and email addresses with your own values.

| Placeholder | Where | What to put |
|---|---|---|
| `<YOUR_TENANT_ID>` | `$TenantId` | Azure AD tenant GUID |
| `<YOUR_CLIENT_ID>` | `$ClientId` | Azure AD app client GUID |
| `<YOUR_CLIENT_SECRET>` | `$ClientSecretDefault` | Azure AD app secret |
| `<YOUR_SERVICE_EMAIL>` | `$UserFrom` | Sender mailbox (Graph API) |
| `<YOUR_EMAIL>` | `$UserTo` | Recipient email address(es) |

---

## Overview

**Get-OSDeploymentReport.ps1** is an OSD deployment status report that queries SCCM for Operating System Deployment execution data and generates an Outlook-safe HTML executive report.

The report pulls from two SCCM WMI data sources:

1. **SMS_DeploymentSummary** — deployment-level compliance statistics (Targeted, Success, Error, Not Met)
2. **SMS_TaskSequenceExecutionStatus** — per-step device execution records

Email delivery is handled via **Microsoft Graph API** using the Exchange-Email-Sender Azure AD app registration (OAuth 2.0 client credentials flow) — no SMTP, no basic auth.

---

## Requirements

| Requirement | Details |
|---|---|
| PowerShell | 5.1 or higher |
| SCCM Admin Console or RSAT | WMI provider access |
| SCCM WMI access | Read access to SMS namespace (`root\sms\site_<SiteCode>`) |
| Azure AD app | `Exchange-Email-Sender` with `Mail.Send` (Application) permission |
| Admin consent | Granted in Azure AD for the app to send as the mailbox identity |
| Network | Outbound HTTPS to `login.microsoftonline.com` and `graph.microsoft.com` |

---

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-SccmServer` | string | `SCCM.Momar.local` | SCCM site server FQDN |
| `-SiteCode` | string | `MT1` | 3-character SCCM site code |
| `-SendEmail` | switch | `$true` | Send the HTML report via email |
| `-Subject` | string | `"SCCM OSD Deployment Status"` | Email subject line |
| `-UserFrom` | string | `<YOUR_SERVICE_EMAIL>` | Sender mailbox (Graph API) |
| `-UserTo` | string[] | `@("<YOUR_EMAIL>")` | Recipient email address(es) |
| `-TenantId` | string | `<YOUR_TENANT_ID>` | Azure AD tenant ID |
| `-ClientId` | string | `<YOUR_CLIENT_ID>` | Azure AD app client ID |
| `-ClientSecret` | SecureString | — | Azure AD secret (overrides default) |
| `-ClientSecretDefault` | string | `<YOUR_CLIENT_SECRET>` | Fallback secret (plaintext) |

---

## How to Run

### Option 1 — Full Report (Default)

```powershell
.\Report\Get-OSDDeploymentReport.ps1
```

Generates HTML and sends via Graph API.

### Option 2 — HTML Only (No Email)

```powershell
.\Report\Get-OSDDeploymentReport.ps1 -SendEmail:$false
```

Saves HTML to `C:\Reports\` but skips email delivery.

### Option 3 — Custom Recipients

```powershell
.\Report\Get-OSDDeploymentReport.ps1 -UserTo "<ADMIN_EMAIL>", "<HELPDESK_EMAIL>"
```

---

## Report Contents

The HTML report includes:

| Section | Description |
|---|---|
| **Summary Cards** | Total / Success / Failed / Running deployment counts |
| **Deployment Summary** | SMS_DeploymentSummary compliance table (Targeted, Success, Errors, In Progress, Unknown, Not Met) |
| **Per-TS Breakdown** | Deployments grouped by task sequence with success rate bars |
| **Duration Statistics** | Average, fastest, and slowest times for successful deployments |
| **Device Details** | Per-device table with status, phase, task sequence, collection, duration, and error messages |

---

## Data Sources

| WMI Class | Purpose |
|---|---|
| `SMS_TaskSequenceExecutionStatus` | Per-step execution records (split into runs via step-number drop detection) |
| `SMS_R_System` | Computer name, MAC, OS, last user |
| `SMS_TaskSequencePackage` | Task sequence names |
| `SMS_Advertisement` | Deployment/advertisement details |
| `SMS_Collection` | Collection names |
| `SMS_DeploymentSummary` (FeatureType=7) | OSD deployment compliance statistics |

---

## Email Delivery

The report uses **Microsoft Graph API** for email delivery:

- **Auth flow:** OAuth 2.0 client credentials grant
- **API endpoint:** `POST /v1.0/users/{mailbox}/sendMail`
- **Permission required:** `Mail.Send` (Application type)

### Secret Resolution Order

1. `-ClientSecret` parameter (SecureString)
2. `$env:OSD_REPORT_CLIENT_SECRET` environment variable
3. `-ClientSecretDefault` parameter
4. Embedded default value

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| **Cannot connect to SCCM WMI** | Wrong server or namespace | Verify `-SccmServer` and `-SiteCode`. Test: `Get-WmiObject -Namespace "root\sms\site_MT1" -Class SMS_Site -ComputerName SCCM.Momar.local` |
| **No OSD execution records found** | No OSD deployments in SCCM | Check that the task sequence has been deployed to at least one collection |
| **Failed to acquire Graph access token** | Invalid TenantId, ClientId, or expired secret | Verify Azure AD app registration values in the Azure portal |
| **AADSTS700016** | Wrong ClientId or app not found in tenant | Check `-ClientId` matches the app registration |
| **AADSTS7000215** | Invalid client secret | Regenerate secret in Azure AD > App > Certificates & secrets |
| **ErrorSendAsDenied** | App not authorized for the `-From` mailbox | Add `Send As` permission in Exchange Admin or assign to the mailbox |
| **Unable to connect to remote server** | Firewall/proxy blocks Graph endpoints | Allow outbound HTTPS to `graph.microsoft.com:443` and `login.microsoftonline.com:443` |

---

## Design Principles

- **Dual data source** — SMS_DeploymentSummary for compliance + SMS_TaskSequenceExecutionStatus for device-level detail
- **Run detection** — step-number drop detection splits multi-attempt deployments into separate runs
- **Graph API email** — no SMTP, no basic auth, OAuth 2.0 client credentials
- **Outlook-safe HTML** — inline CSS, table-based layout, no JavaScript
- **Silent on failure** — all WMI queries wrapped in try/catch, never halts on a single query failure

---

## License

This project is licensed under the [MIT License](../LICENSE).

---

## Author

**Mohammad Abdulkader Omar**
Website: https://momar.tech
LinkedIn: https://www.linkedin.com/in/mabdulkadr/

---

## Disclaimer

These scripts are provided as-is. Test them in a staging environment before applying them to production. The author is not responsible for any unintended outcomes resulting from their use.
