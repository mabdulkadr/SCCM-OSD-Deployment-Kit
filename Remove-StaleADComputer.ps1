<#
.SYNOPSIS
    Deletes a stale computer object from Active Directory if it exists.
    Runs in WinPE at the start of the SCCM OSD task sequence.

.CONFIGURATION
    Before using this script, replace the following placeholders with your actual values:

    ┌─────────────────────────────────────────────────────────────────────────────┐
    │ PLACEHOLDER              │ LOCATION        │ DESCRIPTION                    │
    ├──────────────────────────┼─────────────────┼────────────────────────────────┤
    │ dc01.yourdomain.local    │ FallbackDCs     │ Domain controller hostnames    │
    │ dc02.yourdomain.local    │ FallbackDCs     │ (add as many as needed)        │
    │ dc03.yourdomain.local    │ FallbackDCs     │                                │
    │ dc04.yourdomain.local    │ FallbackDCs     │                                │
    │ x.x.x.x                  │ DCFallbackIPs   │ Corresponding DC IP addresses  │
    └─────────────────────────────────────────────────────────────────────────────┘

.DESCRIPTION
    Reads the OSDComputerName task sequence variable (and the optional
    OSDJoinAccount / OSDJoinPassword for the LDAP bind) and deletes the
    matching AD computer object. Uses System.DirectoryServices.Protocols
    (pure .NET LdapConnection) — works in WinPE, no ADSI, no ActiveDirectory
    module.

    Behavior:
      - OSDComputerName empty  -> exit 0 (nothing to check)
      - Name found in AD       -> delete object, exit 0
      - Name not found in AD   -> exit 0 (nothing to do)
      - All DCs unreachable    -> exit 1
#>

Add-Type -AssemblyName System.DirectoryServices.Protocols

$script:FallbackDomainControllers = @(
    'dc01.momar.local',
    'dc02.momar.local',
    'dc03.momar.local',
    'dc04.momar.local'
)

$script:DCFallbackIPs = @{
    'dc01.momar.local' = '10.0.0.11'
    'dc02.momar.local' = '10.0.0.12'
    'dc03.momar.local' = '10.0.0.13'
    'dc04.momar.local' = '10.0.0.14'
}

function Get-TSVariable {
    param([string]$Name)
    try {
        $tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment
        return $tsenv.Value($Name)
    }
    catch {
        return $null
    }
}

$ComputerName = Get-TSVariable 'OSDComputerName'
$JoinAccount  = Get-TSVariable 'OSDJoinAccount'
$JoinPassword = Get-TSVariable 'OSDJoinPassword'

if (-not $ComputerName) {
    Write-Host "OSDComputerName is empty - nothing to check."
    exit 0
}

$ComputerName = [System.DirectoryServices.Protocols.LdapEncoder]::EscapeFilterValue($ComputerName)

Write-Host "Checking AD for computer: $ComputerName"

$filter = '(&(objectClass=computer)(sAMAccountName=' + $ComputerName + '$))'

foreach ($dc in $script:FallbackDomainControllers) {
    $targets = @($dc)
    if ($script:DCFallbackIPs.ContainsKey($dc)) {
        $targets += $script:DCFallbackIPs[$dc]
    }

    foreach ($target in $targets) {
        $conn = $null
        try {
            $id   = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier($target, 389)
            $conn = New-Object System.DirectoryServices.Protocols.LdapConnection($id)
            $conn.SessionOptions.ProtocolVersion = 3
            $conn.SessionOptions.ReferralChasing = [System.DirectoryServices.Protocols.ReferralChasingOptions]::All
            $conn.Timeout = [TimeSpan]::FromSeconds(20)

            if ($JoinAccount -and $JoinPassword) {
                $cred = New-Object System.Net.NetworkCredential($JoinAccount, $JoinPassword)
                $conn.Bind($cred)
                Write-Host "Bound to $target as OSDJoinAccount."
            }
            else {
                $conn.Bind()
                Write-Host "Bound to $target (anonymous)."
            }

            $rootReq = New-Object System.DirectoryServices.Protocols.SearchRequest('', '(objectClass=*)', ([System.DirectoryServices.Protocols.SearchScope]::Base))
            $rootReq.Attributes.Add('defaultNamingContext') | Out-Null
            $rootResp = [System.DirectoryServices.Protocols.SearchResponse]$conn.SendRequest($rootReq)
            $baseDN = [string]$rootResp.Entries[0].Attributes['defaultNamingContext'][0]

            $searchReq = New-Object System.DirectoryServices.Protocols.SearchRequest($baseDN, $filter, ([System.DirectoryServices.Protocols.SearchScope]::Subtree))
            $searchReq.SizeLimit = 0
            $searchReq.Attributes.Add('distinguishedName') | Out-Null
            $searchResp = [System.DirectoryServices.Protocols.SearchResponse]$conn.SendRequest($searchReq)

            if ($searchResp.Entries.Count -gt 0) {
                $dn = [string]$searchResp.Entries[0].DistinguishedName
                Write-Host "Found computer '$ComputerName' at $dn - deleting."
                $delReq = New-Object System.DirectoryServices.Protocols.DeleteRequest($dn)
                $conn.SendRequest($delReq)
                Write-Host "Deleted '$ComputerName' from AD."
                exit 0
            }
            else {
                Write-Host "Computer '$ComputerName' not found in AD - nothing to delete."
                exit 0
            }
        }
        catch {
            Write-Host "DC $target failed: $($_.Exception.Message)"
        }
        finally {
            if ($conn) { $conn.Dispose() }
        }
    }
}

Write-Host "ERROR: No domain controller reachable."
exit 1
