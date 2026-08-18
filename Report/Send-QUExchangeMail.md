# Send-QUExchangeMail.psm1

PowerShell module for sending HTML email via Exchange Online using Microsoft Graph API with Azure AD app-only OAuth 2.0 authentication. No SMTP, no basic auth, no legacy protocols.

- **App registration:** `Exchange-Email-Sender`
- **Auth flow:** OAuth 2.0 client credentials grant
- **API endpoint:** `POST /v1.0/users/{mailbox}/sendMail`
- **Permission required:** `Mail.Send` (Application type)

---

## ⚙️ Configuration Required

> Replace the Azure AD credentials and email addresses with your own values.

| Placeholder | Where | What to put |
|---|---|---|
| `<YOUR_TENANT_ID>` | `$DefaultTenantId` | Azure AD tenant GUID |
| `<YOUR_CLIENT_ID>` | `$DefaultClientId` | Azure AD app client GUID |
| `<YOUR_CLIENT_SECRET>` | `$DefaultClientSecret` | Azure AD app secret |
| `<YOUR_SERVICE_EMAIL>` | `-From` parameter | Sender mailbox address |
| `<YOUR_EMAIL>` | `-To` parameter | Recipient email address |

---

## Quick Start

```powershell
Import-Module ".\Report\Send-QUExchangeMail.psm1"

Send-QUExchangeMail -From "<YOUR_SERVICE_EMAIL>" `
    -To "<YOUR_EMAIL>" `
    -Subject "Test Message" `
    -Body "<h1>Hello World</h1>"
```

The default TenantId, ClientId, and ClientSecret are embedded — no parameters needed unless overriding.

---

## Requirements

| Requirement | Details |
|---|---|
| PowerShell | 5.1 or higher |
| Azure AD app | `Exchange-Email-Sender` registered in tenant `<YOUR_TENANT_ID>` |
| API permission | `Mail.Send` (Application) — admin consent granted |
| Sender mailbox | The app must be authorized to send as the `-From` address |
| Network | Outbound HTTPS to `login.microsoftonline.com` and `graph.microsoft.com` |

---

## Parameters

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `-From` | string | Yes | — | Sender mailbox (e.g. `<YOUR_SERVICE_EMAIL>`) |
| `-To` | string[] | Yes | — | Recipient email address(es) |
| `-Subject` | string | Yes | — | Email subject line |
| `-Body` | string | Yes | — | HTML email body content |
| `-Cc` | string[] | No | `@()` | CC recipient(s) |
| `-SaveToSentItems` | switch | No | `$false` | Save copy in sender's Sent Items folder |
| `-TenantId` | string | No | Embedded default | Azure AD tenant ID |
| `-ClientId` | string | No | Embedded default | Azure AD application (client) ID |
| `-ClientSecret` | SecureString | No | See below | Client secret override |
| `-ClientSecretDefault` | string | No | Embedded default | Plaintext fallback secret |

### Secret Resolution Order

1. `-ClientSecret` parameter (SecureString)
2. `$env:QU_EXCHANGE_CLIENT_SECRET` environment variable
3. `-ClientSecretDefault` parameter
4. Embedded default value

---

## Integration Examples

### 1. Get-OSDDeploymentReport.ps1 (built-in)

The report script already uses the embedded `Get-GraphAccessToken` + `Send-GraphMailMessage` internally. No import needed.

```powershell
.\Report\Get-OSDDeploymentReport.ps1
```

---

### 2. Using the module in any custom script

```powershell
# dot-source or import the module
Import-Module ".\Report\Send-QUExchangeMail.psm1"

# collect data, build your report...
$html = @"
<h2>Daily SCCM Health Check</h2>
<table border='1'>
<tr><th>Site</th><th>Status</th></tr>
<tr><td>MT1</td><td style='color:green'>Healthy</td></tr>
</table>
"@

Send-QUExchangeMail -From "<YOUR_SERVICE_EMAIL>" `
    -To "<YOUR_EMAIL>", "<HELPDESK_EMAIL>" `
    -Cc "<MANAGER_EMAIL>" `
    -Subject "SCCM Daily Health Report" `
    -Body $html
```

---

### 3. Post-OSD Enrollment notification

```powershell
Import-Module ".\Report\Send-QUExchangeMail.psm1"

# called from Post-OSD-Enrollment-Accelerator.ps1 or Schedule-PostOSD-Enrollment.ps1
$computerName = $env:COMPUTERNAME
$body = @"
<h2>Post-OSD Enrollment Complete</h2>
<p>Device <b>$computerName</b> has completed post-deployment enrollment.</p>
<ul>
  <li>Entra ID Join: Success</li>
  <li>Intune MDM: Enrolled</li>
  <li>Co-Management: Active</li>
</ul>
"@

Send-QUExchangeMail -From "<YOUR_SERVICE_EMAIL>" `
    -To "it-support@<YOUR_DOMAIN>" `
    -Subject "Post-OSD Complete: $computerName" `
    -Body $body
```

---

### 4. Scheduled Task / Automation

```powershell
# Set the secret in the scheduled task environment
# (Task Scheduler > Action > set environment variable)
[Environment]::SetEnvironmentVariable("QU_EXCHANGE_CLIENT_SECRET", `
    "<YOUR_CLIENT_SECRET>", "User")

# Now the module picks it up automatically via $env:QU_EXCHANGE_CLIENT_SECRET
Import-Module "\\server\share\Send-QUExchangeMail.psm1"
Send-QUExchangeMail -From "<YOUR_SERVICE_EMAIL>" `
    -To "<ADMIN_EMAIL>" -Subject "Automated Report" -Body $reportHtml
```

---

### 5. Override credentials for a different tenant

```powershell
$sec = ConvertTo-SecureString "your-secret-here" -AsPlainText -Force

Send-QUExchangeMail `
    -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -ClientId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
    -ClientSecret $sec `
    -From "noreply@another-tenant.onmicrosoft.com" `
    -To "user@contoso.com" `
    -Subject "Cross-Tenant Test" `
    -Body "<p>Sent from another Azure AD tenant.</p>"
```

---

### 6. Remove-StaleADComputer.ps1 alert

```powershell
Import-Module ".\Report\Send-QUExchangeMail.psm1"

# Add to Remove-StaleADComputer.ps1 after deletion
if ($deleted) {
    Send-QUExchangeMail -From "<YOUR_SERVICE_EMAIL>" `
        -To "sccm-<ADMIN_EMAIL>" `
        -Subject "Stale AD Object Removed: $computerName" `
        -Body "<p>Deleted stale AD computer: <b>$computerName</b> from SCCM OSD pre-stage.</p>"
}
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Failed to acquire Graph access token` | Invalid TenantId, ClientId or expired secret | Verify app registration values in Azure AD |
| `AADSTS700016` | Wrong ClientId or app not found in tenant | Check `-ClientId` matches app registration |
| `AADSTS7000215` | Invalid client secret | Regenerate secret in Azure AD > App > Certificates & secrets |
| `ErrorAccessDenied` / `403` | App lacks `Mail.Send` permission | Grant and admin-consent `Mail.Send` (Application) in API permissions |
| `ErrorSendAsDenied` | App not authorized for the `-From` mailbox | Add `Send As` permission in Exchange Admin or assign to the mailbox |
| `Unable to connect to remote server` | Firewall/proxy blocks Graph endpoints | Allow outbound HTTPS to `graph.microsoft.com:443` and `login.microsoftonline.com:443` |
| No output, no email | Script terminated silently | Add `-Verbose` to see token acquisition and send steps |

### Debug with Verbose Output

```powershell
Send-QUExchangeMail -From "<YOUR_SERVICE_EMAIL>" `
    -To "<SENDER_EMAIL>" -Subject "Debug" -Body "<p>Test</p>" -Verbose
```

---

## Security Notes

- **Never commit secrets to source control.** The embedded default exists only for air-gapped internal environments. Override via `-ClientSecret`, `$env:QU_EXCHANGE_CLIENT_SECRET`, or a secrets management solution.
- **Rotate client secrets** every 6 months via Azure AD > App registrations > Exchange-Email-Sender > Certificates & secrets.
- **Use a dedicated service mailbox** (`<YOUR_SERVICE_EMAIL>`) rather than a user mailbox for audit trail clarity.
- **The app uses application permissions** (not delegated) — no user is impersonated, and no interactive login is required. Suitable for fully automated unattended scenarios.

---

## Internal Functions

Two helper functions handle the low-level API calls. They are not exported; use `Send-QUExchangeMail` only.

| Function | Scope | Purpose |
|---|---|---|
| `Get-GraphAccessToken` | Private | POST to `login.microsoftonline.com/{tenant}/oauth2/v2.0/token` — returns bearer token |
| `Send-GraphMailMessage` | Private | POST to `graph.microsoft.com/v1.0/users/{from}/sendMail` — sends the email |

---

## File Location

```
SCCM-OSD-Deployment-Kit/
└── Report/
    ├── Send-QUExchangeMail.psm1       ← This module
    └── Get-OSDDeploymentReport.ps1   ← Report script (uses same auth internally)
```
