<#
.SYNOPSIS
    Creates two MECM device collections that segment the fleet into Windows clients
    vs. Windows servers, using the OS ProductType from inventory.

.DESCRIPTION
    Creates query-based collections:

      "Devices: Windows Clients"  - ProductType = 1 (workstation OS: Windows 10 / 11, etc.)
      "Devices: Windows Servers"  - ProductType = 2 OR 3 (domain controller / member or
                                    standalone server)

    ProductType comes from Win32_OperatingSystem (SMS_G_System_OPERATING_SYSTEM):
      1 = Workstation
      2 = Domain controller
      3 = Server (not a DC)

    Primary use: targeting CIs / baselines that need a different expected value per
    OS class -- e.g. the Delivery Optimization DODownloadMode control
    (clients = 0, servers = 99), which builds a separate baseline per collection.

    Membership refresh: incremental enabled (so newly inventoried hosts populate fast),
    plus a daily full evaluation.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER LimitingCollectionName
    Parent / limiting collection for both new collections. Default: "All Systems".
    Use a tighter limit (e.g. "All Windows Devices") to keep non-Windows or
    unmanaged endpoints out.

.PARAMETER ClientCollectionName
    Name for the client collection. Default: "Devices: Windows Clients".

.PARAMETER ServerCollectionName
    Name for the server collection. Default: "Devices: Windows Servers".

.EXAMPLE
    .\New-OSClassCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local

.EXAMPLE
    .\New-OSClassCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -LimitingCollectionName "All Windows Devices"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SiteCode,

    [Parameter(Mandatory)]
    [string]$SiteServer,

    [string]$LimitingCollectionName = 'All Systems',

    [string]$ClientCollectionName = 'Devices: Windows Clients',

    [string]$ServerCollectionName = 'Devices: Windows Servers'
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# WQL queries
# ============================================================================

$ClientQuery = @'
SELECT DISTINCT SMS_R_SYSTEM.ResourceID, SMS_R_SYSTEM.ResourceType, SMS_R_SYSTEM.Name, SMS_R_SYSTEM.SMSUniqueIdentifier, SMS_R_SYSTEM.ResourceDomainORWorkgroup, SMS_R_SYSTEM.Client
FROM SMS_R_System
INNER JOIN SMS_G_System_OPERATING_SYSTEM ON SMS_G_System_OPERATING_SYSTEM.ResourceID = SMS_R_System.ResourceId
WHERE SMS_G_System_OPERATING_SYSTEM.ProductType = 1
'@

$ServerQuery = @'
SELECT DISTINCT SMS_R_SYSTEM.ResourceID, SMS_R_SYSTEM.ResourceType, SMS_R_SYSTEM.Name, SMS_R_SYSTEM.SMSUniqueIdentifier, SMS_R_SYSTEM.ResourceDomainORWorkgroup, SMS_R_SYSTEM.Client
FROM SMS_R_System
INNER JOIN SMS_G_System_OPERATING_SYSTEM ON SMS_G_System_OPERATING_SYSTEM.ResourceID = SMS_R_System.ResourceId
WHERE SMS_G_System_OPERATING_SYSTEM.ProductType = 2 OR SMS_G_System_OPERATING_SYSTEM.ProductType = 3
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
    # ========================================================================
    # Refresh schedule: daily full evaluation (incremental also enabled below)
    # ========================================================================

    $dailySchedule = New-CMSchedule -RecurInterval Days -RecurCount 1

    # ========================================================================
    # Client collection
    # ========================================================================

    Write-Host "Creating collection: $ClientCollectionName"

    New-CMDeviceCollection `
        -Name $ClientCollectionName `
        -LimitingCollectionName $LimitingCollectionName `
        -RefreshType Both `
        -RefreshSchedule $dailySchedule `
        -Comment "Windows client OS (Win32_OperatingSystem ProductType = 1). Auto-populated via WQL against SMS_G_System_OPERATING_SYSTEM." | Out-Null

    Add-CMDeviceCollectionQueryMembershipRule `
        -CollectionName $ClientCollectionName `
        -QueryExpression $ClientQuery `
        -RuleName 'Windows Clients (ProductType = 1)'

    Write-Host "  Created and query rule attached." -ForegroundColor Green

    # ========================================================================
    # Server collection
    # ========================================================================

    Write-Host "Creating collection: $ServerCollectionName"

    New-CMDeviceCollection `
        -Name $ServerCollectionName `
        -LimitingCollectionName $LimitingCollectionName `
        -RefreshType Both `
        -RefreshSchedule $dailySchedule `
        -Comment "Windows server OS (Win32_OperatingSystem ProductType = 2 [DC] or 3 [server]). Auto-populated via WQL against SMS_G_System_OPERATING_SYSTEM." | Out-Null

    Add-CMDeviceCollectionQueryMembershipRule `
        -CollectionName $ServerCollectionName `
        -QueryExpression $ServerQuery `
        -RuleName 'Windows Servers (ProductType = 2 or 3)'

    Write-Host "  Created and query rule attached." -ForegroundColor Green

    # ========================================================================
    # Trigger initial population
    # ========================================================================

    Write-Host ""
    Write-Host "Triggering initial collection evaluation..."

    Invoke-CMCollectionUpdate -Name $ClientCollectionName
    Invoke-CMCollectionUpdate -Name $ServerCollectionName

    Write-Host "  Evaluation queued. Membership populates within a few minutes." -ForegroundColor Green

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Limiting collection: $LimitingCollectionName"
    Write-Host "Windows Clients:     $ClientCollectionName"
    Write-Host "Windows Servers:     $ServerCollectionName"
    Write-Host "Refresh:             Incremental + Daily full"
    Write-Host ""
    Write-Host "Next:" -ForegroundColor Yellow
    Write-Host "  1. Wait a few minutes, then verify membership counts in the console."
    Write-Host "  2. Feed these names into New-DODownloadModeBaseline.ps1:"
    Write-Host "       -ClientCollectionName '$ClientCollectionName' -ServerCollectionName '$ServerCollectionName'"
}
finally {
    Set-Location $OriginalLocation
}
