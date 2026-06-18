<#
.SYNOPSIS
    Creates an MECM device collection containing all Windows hosts (client + server),
    intended as the universal deploy target for fleet-wide CI/CB baselines.

.DESCRIPTION
    Creates a query-based collection:

      "All Windows Devices" - any host whose Win32_OperatingSystem.Caption contains
                              "Windows" (ProductType 1, 2, or 3).

    Most hardening / compliance baselines in MECM\CI-CB apply to every managed Windows
    host regardless of role -- WDigest, LSA Protection, NTLM, SMB signing, anonymous
    enumeration, UAC remote restriction, AlwaysInstallElevated, script block logging,
    autorun, RDP NLA/TLS. Rather than mint a near-identical collection per control, point
    them all at this one. Use New-OSClassCollections.ps1 instead when a control needs a
    different value per client vs. server (e.g. Delivery Optimization DODownloadMode).

    The built-in "All Systems" also contains non-Windows and unknown/agentless resources;
    this collection narrows to actual Windows OS hosts so baseline compliance numbers are
    not diluted.

    Membership refresh: incremental enabled (so newly inventoried hosts populate fast),
    plus a daily full evaluation.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER LimitingCollectionName
    Parent / limiting collection. Default: "All Systems".

.PARAMETER CollectionName
    Name for the collection. Default: "All Windows Devices".

.EXAMPLE
    .\New-WindowsDevicesCollection.ps1 -SiteCode MCM -SiteServer CM01.contoso.local
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SiteCode,

    [Parameter(Mandatory)]
    [string]$SiteServer,

    [string]$LimitingCollectionName = 'All Systems',

    [string]$CollectionName = 'All Windows Devices'
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# WQL query
# ============================================================================

$WindowsQuery = @'
SELECT DISTINCT SMS_R_SYSTEM.ResourceID, SMS_R_SYSTEM.ResourceType, SMS_R_SYSTEM.Name, SMS_R_SYSTEM.SMSUniqueIdentifier, SMS_R_SYSTEM.ResourceDomainORWorkgroup, SMS_R_SYSTEM.Client
FROM SMS_R_System
INNER JOIN SMS_G_System_OPERATING_SYSTEM ON SMS_G_System_OPERATING_SYSTEM.ResourceID = SMS_R_System.ResourceId
WHERE SMS_G_System_OPERATING_SYSTEM.Caption LIKE "%Windows%"
'@

# ============================================================================
# Connect to MECM
# ============================================================================

$modulePath = Join-Path (Split-Path $ENV:SMS_ADMIN_UI_PATH -Parent) "ConfigurationManager.psd1"
if (-not (Get-Module ConfigurationManager -ErrorAction SilentlyContinue)) {
    if (Test-Path $modulePath) {
        Import-Module $modulePath
    }
    else {
        throw "ConfigurationManager module not found. Run this from a machine with the MECM admin console installed."
    }
}

$OriginalLocation = Get-Location

if (-not (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer | Out-Null
}
Set-Location "${SiteCode}:"

try {
    $dailySchedule = New-CMSchedule -RecurInterval Days -RecurCount 1

    Write-Host "Creating collection: $CollectionName"

    New-CMDeviceCollection `
        -Name $CollectionName `
        -LimitingCollectionName $LimitingCollectionName `
        -RefreshType Both `
        -RefreshSchedule $dailySchedule `
        -Comment "All Windows OS hosts (Win32_OperatingSystem Caption LIKE '%Windows%'). Universal deploy target for fleet-wide CI/CB baselines. Auto-populated via WQL against SMS_G_System_OPERATING_SYSTEM." | Out-Null

    Add-CMDeviceCollectionQueryMembershipRule `
        -CollectionName $CollectionName `
        -QueryExpression $WindowsQuery `
        -RuleName 'Windows OS (Caption LIKE %Windows%)'

    Write-Host "  Created and query rule attached." -ForegroundColor Green

    Write-Host ""
    Write-Host "Triggering initial collection evaluation..."
    Invoke-CMCollectionUpdate -Name $CollectionName
    Write-Host "  Evaluation queued. Membership populates within a few minutes." -ForegroundColor Green

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Limiting collection: $LimitingCollectionName"
    Write-Host "Collection:          $CollectionName"
    Write-Host "Refresh:             Incremental + Daily full"
    Write-Host ""
    Write-Host "Next:" -ForegroundColor Yellow
    Write-Host "  Use this collection name as -CollectionName for the fleet-wide CI/CB baselines"
    Write-Host "  under MECM\CI-CB (WDigest, LSA Protection, NTLM, SMB signing, anonymous enumeration,"
    Write-Host "  UAC remote restriction, AlwaysInstallElevated, script block logging, autorun, RDP)."
}
finally {
    Set-Location $OriginalLocation
}
