# 📧 Send-QUExchangeMail.psm1

A reusable PowerShell module for sending HTML email via Microsoft Graph API. OAuth 2.0 client credentials — no SMTP, no basic auth, no legacy protocols.

> Used internally by `Get-OSDDeploymentReport.ps1`. Can also be imported and used by any custom script that needs to send email.

---

## Quick Start

```powershell
Import-Module ".\Report\Send-QUExchangeMail.psm1"

Send-QUExchangeMail -From "noreply@your-domain.com" `
    -To "admin@your-domain.com" `
    -Subject "Test Message" `
    -Body "<h1>Hello World</h1>"
```

The default TenantId, ClientId, and ClientSecret are embedded — you only need to pass them if you want to override.

---

## Configuration

### Replace These Placeholders

| Placeholder | Variable | What to Put |
|---|---|---|
| `<YOUR_TENANT_ID>` | `$DefaultTenantId` | Azure AD tenant GUID |
| `<YOUR_CLIENT_ID>` | `$DefaultClientId` | Azure AD app client GUID |
| `<YOUR_CLIENT_SECRET>` | `$DefaultClientSecret` | Azure AD app client secret |

### Secret Resolution Order

The module checks these in order until it finds a value:

1. `-ClientSecret` parameter (SecureString)
2. `$env:QU_EXCHANGE_CLIENT_SECRET` environment variable
3. `-ClientSecretDefault` parameter
4. Embedded default value

---

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-From` | ✅ Yes | Sender mailbox address |
| `-To` | ✅ Yes | One or more recipient addresses |
| `-Subject` | ✅ Yes | Email subject line |
| `-Body` | ✅ Yes | HTML content |
| `-Cc` | No | CC recipients |
| `-SaveToSentItems` | No | Save a copy in the sender's Sent Items folder |
| `-TenantId` | No | Override default Azure AD tenant |
| `-ClientId` | No | Override default app client ID |
| `-ClientSecret` | No | Override default client secret (SecureString) |

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| PowerShell | 5.1+ |
| Azure AD app | Registered with `Mail.Send` (Application) permission |
| Admin consent | Must be granted in Azure AD |
| Mailbox permissions | App must be authorized to send as the `-From` mailbox |
| Network | Outbound HTTPS to `login.microsoftonline.com` and `graph.microsoft.com` |

---

## Azure AD App Setup

1. **Azure Portal → App registrations → New registration**
2. Name it something like `Exchange-Email-Sender`
3. Copy the **Tenant ID** and **Client ID** into the module
4. **Certificates & secrets → New client secret** → copy the secret value
5. **API permissions → Add permission → Microsoft Graph → Application permissions → Mail.Send**
6. Click **Grant admin consent**
7. In **Exchange Admin**, grant `Send As` permission for the sender mailbox to the app

---

## Usage Examples

### Basic Send

```powershell
Send-QUExchangeMail -From "noreply@your-domain.com" `
    -To "admin@your-domain.com" `
    -Subject "Test" `
    -Body "<h1>Hello</h1>"
```

### Multiple Recipients + CC

```powershell
Send-QUExchangeMail -From "noreply@your-domain.com" `
    -To "admin@your-domain.com", "helpdesk@your-domain.com" `
    -Cc "manager@your-domain.com" `
    -Subject "Daily Report" `
    -Body $htmlReport
```

### Override Credentials (Cross-Tenant)

```powershell
$secret = ConvertTo-SecureString "your-secret-here" -AsPlainText -Force

Send-QUExchangeMail `
    -TenantId "your-tenant-guid" `
    -ClientId "your-client-guid" `
    -ClientSecret $secret `
    -From "noreply@other-tenant.com" `
    -To "user@your-domain.com" `
    -Subject "Cross-Tenant" `
    -Body "<p>Hello</p>"
```

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| `Failed to acquire token` | Check TenantId, ClientId, Client Secret |
| `AADSTS700016` | Wrong ClientId or app not found in tenant |
| `AADSTS7000215` | Invalid client secret — regenerate in Azure AD |
| `ErrorAccessDenied` / `403` | App lacks `Mail.Send` permission — grant + admin consent |
| `ErrorSendAsDenied` | App not authorized for `-From` mailbox — add `Send As` in Exchange |
| Cannot reach server | Allow outbound HTTPS to `graph.microsoft.com` and `login.microsoftonline.com` |
| No output, no email | Add `-Verbose` to see token acquisition and send steps |

### Verbose Debug

```powershell
Send-QUExchangeMail -From "noreply@your-domain.com" -To "admin@your-domain.com" -Subject "Debug" -Body "Test" -Verbose
```

---

## Security Notes

- **Never commit secrets to source control.** Use `-ClientSecret` parameter, environment variable, or a secrets management solution.
- **Rotate client secrets** every 6 months via Azure AD → Certificates & secrets.
- **Use a dedicated service mailbox** (e.g., `noreply@your-domain.com`) for clear audit trails.
- **Application permissions only** — no user impersonation, no interactive login required.
