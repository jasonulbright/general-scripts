<#
.SYNOPSIS
    Creates two MECM device collections that segment the fleet by Intel Hyper-Threading state.

.DESCRIPTION
    Creates query-based collections:

      "Devices: Hyperthreading Enabled"  - any processor where NumberOfLogicalProcessors > NumberOfCores
      "Devices: Hyperthreading Disabled" - all processors where NumberOfLogicalProcessors = NumberOfCores
                                           AND the system is NOT in the HT-Enabled set (subquery filter)

    Primary use: targeting the bundled Intel Speculative Execution Mitigations CIs, which
    require different FeatureSettingsOverride DWORDs depending on HT state.

    Secondary use: audit visibility. HT-disabled workstations are unusual and worth investigating
    (deliberate hardening? misconfigured BIOS? hardware fault?). HT-enabled servers in regulated
    contexts may be a finding (MDS/L1TF exposure).

    Membership refresh: incremental enabled (so newly inventoried hosts populate fast),
    plus a daily full evaluation.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER LimitingCollectionName
    Parent / limiting collection for both new collections. Default: "All Systems".
    Use a tighter limit (e.g. "All Workstations" or "All Windows Devices") if you
    don't want unmanaged or non-Windows endpoints scanned.

.PARAMETER HtEnabledCollectionName
    Name for the HT-enabled collection. Default: "Devices: Hyperthreading Enabled".

.PARAMETER HtDisabledCollectionName
    Name for the HT-disabled collection. Default: "Devices: Hyperthreading Disabled".

.EXAMPLE
    .\New-HTBasedCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local

.EXAMPLE
    .\New-HTBasedCollections.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -LimitingCollectionName "All Windows Devices"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SiteCode,

    [Parameter(Mandatory)]
    [string]$SiteServer,

    [string]$LimitingCollectionName = 'All Systems',

    [string]$HtEnabledCollectionName  = 'Devices: Hyperthreading Enabled',

    [string]$HtDisabledCollectionName = 'Devices: Hyperthreading Disabled'
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# WQL queries
# ============================================================================

$HtEnabledQuery = @'
SELECT DISTINCT SMS_R_SYSTEM.ResourceID, SMS_R_SYSTEM.ResourceType, SMS_R_SYSTEM.Name, SMS_R_SYSTEM.SMSUniqueIdentifier, SMS_R_SYSTEM.ResourceDomainORWorkgroup, SMS_R_SYSTEM.Client
FROM SMS_R_System
INNER JOIN SMS_G_System_PROCESSOR ON SMS_G_System_PROCESSOR.ResourceID = SMS_R_System.ResourceId
WHERE SMS_G_System_PROCESSOR.NumberOfLogicalProcessors > SMS_G_System_PROCESSOR.NumberOfCores
'@

$HtDisabledQuery = @'
SELECT DISTINCT SMS_R_SYSTEM.ResourceID, SMS_R_SYSTEM.ResourceType, SMS_R_SYSTEM.Name, SMS_R_SYSTEM.SMSUniqueIdentifier, SMS_R_SYSTEM.ResourceDomainORWorkgroup, SMS_R_SYSTEM.Client
FROM SMS_R_System
INNER JOIN SMS_G_System_PROCESSOR ON SMS_G_System_PROCESSOR.ResourceID = SMS_R_System.ResourceId
WHERE SMS_G_System_PROCESSOR.NumberOfLogicalProcessors = SMS_G_System_PROCESSOR.NumberOfCores
AND SMS_R_System.ResourceId NOT IN (
    SELECT SMS_R_SYSTEM.ResourceID FROM SMS_R_System
    INNER JOIN SMS_G_System_PROCESSOR ON SMS_G_System_PROCESSOR.ResourceID = SMS_R_System.ResourceId
    WHERE SMS_G_System_PROCESSOR.NumberOfLogicalProcessors > SMS_G_System_PROCESSOR.NumberOfCores
)
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
    # Refresh schedule: daily full evaluation
    # ========================================================================

    $dailySchedule = New-CMSchedule -RecurInterval Days -RecurCount 1

    # ========================================================================
    # HT Enabled collection
    # ========================================================================

    Write-Host "Creating collection: $HtEnabledCollectionName"

    New-CMDeviceCollection `
        -Name $HtEnabledCollectionName `
        -LimitingCollectionName $LimitingCollectionName `
        -RefreshType Both `
        -RefreshSchedule $dailySchedule `
        -Comment "Devices where any processor reports NumberOfLogicalProcessors > NumberOfCores (Hyper-Threading enabled). Auto-populated via WQL against SMS_G_System_PROCESSOR." | Out-Null

    Add-CMDeviceCollectionQueryMembershipRule `
        -CollectionName $HtEnabledCollectionName `
        -QueryExpression $HtEnabledQuery `
        -RuleName 'HT-Enabled (LogicalProcessors > Cores)'

    Write-Host "  Created and query rule attached." -ForegroundColor Green

    # ========================================================================
    # HT Disabled collection
    # ========================================================================

    Write-Host "Creating collection: $HtDisabledCollectionName"

    New-CMDeviceCollection `
        -Name $HtDisabledCollectionName `
        -LimitingCollectionName $LimitingCollectionName `
        -RefreshType Both `
        -RefreshSchedule $dailySchedule `
        -Comment "Devices where all processors report NumberOfLogicalProcessors = NumberOfCores AND the device is not in HT-Enabled. Hyper-Threading disabled or unsupported. Auto-populated via WQL against SMS_G_System_PROCESSOR." | Out-Null

    Add-CMDeviceCollectionQueryMembershipRule `
        -CollectionName $HtDisabledCollectionName `
        -QueryExpression $HtDisabledQuery `
        -RuleName 'HT-Disabled (LogicalProcessors = Cores AND not in HT-Enabled)'

    Write-Host "  Created and query rule attached." -ForegroundColor Green

    # ========================================================================
    # Trigger initial population
    # ========================================================================

    Write-Host ""
    Write-Host "Triggering initial collection evaluation..."

    Invoke-CMCollectionUpdate -Name $HtEnabledCollectionName
    Invoke-CMCollectionUpdate -Name $HtDisabledCollectionName

    Write-Host "  Evaluation queued. Membership populates within a few minutes." -ForegroundColor Green

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Limiting collection: $LimitingCollectionName"
    Write-Host "HT Enabled:          $HtEnabledCollectionName"
    Write-Host "HT Disabled:         $HtDisabledCollectionName"
    Write-Host "Refresh:             Incremental + Daily full"
    Write-Host ""
    Write-Host "Next:" -ForegroundColor Yellow
    Write-Host "  1. Wait a few minutes, then verify membership counts in the console."
    Write-Host "  2. Deploy the bundled Intel Speculative Execution Mitigations CBs to these collections."
}
finally {
    Set-Location $OriginalLocation
}
