<#
.SYNOPSIS
    Send-QUExchangeMail — Send email via Exchange Online using Microsoft Graph API (OAuth 2.0).

.CONFIGURATION
    Before using this module, replace the following placeholders with your actual values:

    ┌──────────────────────────────────────────────────────────────────────────────┐
    │ PLACEHOLDER              │ LOCATION        │ DESCRIPTION                    │
    ├──────────────────────────┼─────────────────┼────────────────────────────────┤
    │ <YOUR_TENANT_ID>         │ $DefaultTenantId│ Azure AD tenant ID (GUID)      │
    │ <YOUR_CLIENT_ID>         │ $DefaultClientId│ Azure AD app client ID (GUID)  │
    │ <YOUR_CLIENT_SECRET>     │ $DefaultClientS.│ Azure AD app client secret     │
    │ <YOUR_SERVICE_EMAIL>     │ .EXAMPLE / -From│ Sender mailbox address         │
    │ <YOUR_EMAIL>             │ .EXAMPLE / -To  │ Recipient email address        │
    └──────────────────────────────────────────────────────────────────────────────┘

.DESCRIPTION
    PowerShell module that sends HTML email through Microsoft Graph API using Azure AD
    app-only authentication (client credentials flow). Designed for the Exchange-Email-Sender
    app registration. No SMTP, no basic auth, no legacy protocols.

    Exported command: Send-QUExchangeMail

.EXAMPLE
    Import-Module .\Send-QUExchangeMail.psm1
    Send-QUExchangeMail -From "<YOUR_SERVICE_EMAIL>" `
        -To "<YOUR_EMAIL>" `
        -Subject "Test" `
        -Body "<h1>Hello</h1>"

.EXAMPLE
    $pw = ConvertTo-SecureString "<YOUR_CLIENT_SECRET>" -AsPlainText -Force
    Send-QUExchangeMail -From "<YOUR_SERVICE_EMAIL>" -To "<YOUR_EMAIL>" `
        -Subject "Report" -Body $html -ClientSecret $pw

.NOTES
    Requirements:
      - Exchange-Email-Sender Azure AD app with Mail.Send application permission
      - Admin consent granted for the app to send as the target mailbox
      - PowerShell 5.1+

    Secret resolution priority:
      1. -ClientSecret parameter
      2. $env:QU_EXCHANGE_CLIENT_SECRET
      3. -ClientSecretDefault parameter

    Default credentials (embedded):
      TenantId  : <YOUR_TENANT_ID>
      ClientId  : <YOUR_CLIENT_ID>
#>

# ==============================================================================
# Module-scoped default credentials
# ==============================================================================
$script:DefaultTenantId       = '<YOUR_TENANT_ID>'   # Azure AD tenant GUID
$script:DefaultClientId       = '<YOUR_CLIENT_ID>'   # Azure AD app client GUID
$script:DefaultClientSecret   = '<YOUR_CLIENT_SECRET>' # Azure AD app secret

# ==============================================================================
# Acquire OAuth 2.0 access token via client credentials flow
# ==============================================================================
function Get-GraphAccessToken {
    param(
        [Parameter(Mandatory)] [string]$TenantId,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [securestring]$ClientSecret
    )
    $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
    ) -replace '\0', ''

    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $plainSecret
        scope         = 'https://graph.microsoft.com/.default'
    }

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    try {
        $response = Invoke-RestMethod -Method Post -Uri $tokenUrl `
            -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        return $response.access_token
    } catch {
        $err = $_.Exception.Message
        try { $err = ($_.ErrorDetails.Message | ConvertFrom-Json).error_description } catch {}
        Write-Error "Get-GraphAccessToken: $err"
        return $null
    }
}

# ==============================================================================
# Send email via Microsoft Graph /sendMail endpoint
# ==============================================================================
function Send-GraphMailMessage {
    param(
        [Parameter(Mandatory)] [string]$AccessToken,
        [Parameter(Mandatory)] [string]$From,
        [Parameter(Mandatory)] [string[]]$To,
        [Parameter(Mandatory)] [string]$Subject,
        [Parameter(Mandatory)] [string]$Body,
        [string[]]$Cc = @(),
        [switch]$SaveToSentItems
    )

    $recipients = @($To | ForEach-Object { @{ emailAddress = @{ address = $_ } } })
    $ccRecipients = @($Cc | ForEach-Object { @{ emailAddress = @{ address = $_ } } })

    $message = @{
        subject      = $Subject
        body         = @{ contentType = 'HTML'; content = $Body }
        toRecipients = $recipients
        from         = @{ emailAddress = @{ address = $From } }
    }

    if ($ccRecipients.Count -gt 0) {
        $message.ccRecipients = $ccRecipients
    }

    $payload = @{
        message         = $message
        saveToSentItems = [bool]$SaveToSentItems
    } | ConvertTo-Json -Depth 5 -Compress

    $headers = @{
        Authorization  = "Bearer $AccessToken"
        'Content-Type' = 'application/json'
    }

    $sendUrl = "https://graph.microsoft.com/v1.0/users/$From/sendMail"
    try {
        Invoke-RestMethod -Method Post -Uri $sendUrl -Headers $headers `
            -Body $payload -ContentType 'application/json' -ErrorAction Stop
        return $true
    } catch {
        Write-Error "Send-GraphMailMessage: $($_.Exception.Message)"
        return $false
    }
}

# ==============================================================================
# Public function: resolve secret, get token, send email
# ==============================================================================
function Send-QUExchangeMail {
    <#
    .SYNOPSIS
        Send an HTML email via Exchange Online using Azure AD app-only OAuth.

    .DESCRIPTION
        Resolves the client secret (parameter > env var > default), acquires an
        OAuth 2.0 access token from Azure AD, and sends the email via Microsoft Graph.

    .PARAMETER From
        Sender email address. Must be a mailbox the app has permission to send as.

    .PARAMETER To
        Recipient email address(es).

    .PARAMETER Subject
        Email subject line.

    .PARAMETER Body
        HTML email body content.

    .PARAMETER Cc
        CC recipient email address(es).

    .PARAMETER TenantId
        Azure AD tenant ID. Uses embedded default if omitted.

    .PARAMETER ClientId
        Azure AD application (client) ID. Uses embedded default if omitted.

    .PARAMETER ClientSecret
        Client secret as SecureString. Falls back to env var or embedded default.

    .PARAMETER ClientSecretDefault
        Plaintext fallback client secret when param and env var are both empty.

    .PARAMETER SaveToSentItems
        Save the sent email to the sender's Sent Items folder.

    .EXAMPLE
        Send-QUExchangeMail -From "<YOUR_SERVICE_EMAIL>" `
            -To "<YOUR_EMAIL>" `
            -Subject "OSD Report" -Body $htmlBody

    .EXAMPLE
        Send-QUExchangeMail -From "<SENDER_EMAIL>" -To "<YOUR_EMAIL>" `
            -Subject "Daily Report" -Body $report `
            -TenantId "xxx" -ClientId "yyy" -ClientSecret $sec
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$From,
        [Parameter(Mandatory)] [string[]]$To,
        [Parameter(Mandatory)] [string]$Subject,
        [Parameter(Mandatory)] [string]$Body,
        [string[]]$Cc = @(),
        [switch]$SaveToSentItems,

        [string]$TenantId,
        [string]$ClientId,
        [securestring]$ClientSecret,
        [string]$ClientSecretDefault
    )

    $tenant = if ($TenantId) { $TenantId } else { $script:DefaultTenantId }
    $client = if ($ClientId) { $ClientId } else { $script:DefaultClientId }

    $secret = $ClientSecret
    if (-not $secret -and $env:QU_EXCHANGE_CLIENT_SECRET) {
        $secret = ConvertTo-SecureString $env:QU_EXCHANGE_CLIENT_SECRET -AsPlainText -Force
    }
    if (-not $secret) {
        $plainDefault = if ($ClientSecretDefault) { $ClientSecretDefault } else { $script:DefaultClientSecret }
        $secret = ConvertTo-SecureString $plainDefault -AsPlainText -Force
    }

    Write-Verbose "Acquiring token: Tenant=$tenant Client=$client"
    $token = Get-GraphAccessToken -TenantId $tenant -ClientId $client -ClientSecret $secret
    if (-not $token) {
        Write-Error "Send-QUExchangeMail: Failed to acquire Graph access token."
        return $false
    }

    Write-Verbose "Sending email From=$From To=$($To -join ',') Subject='$Subject'"
    $params = @{
        AccessToken     = $token
        From            = $From
        To              = $To
        Subject         = $Subject
        Body            = $Body
        Cc              = $Cc
        SaveToSentItems = $SaveToSentItems
    }
    return Send-GraphMailMessage @params
}

# ==============================================================================
# Export only the public function
# ==============================================================================
Export-ModuleMember -Function 'Send-QUExchangeMail'
