<#
.SYNOPSIS
    Creates an MECM Configuration Item and Baseline for automated CCM cache cleanup.

.DESCRIPTION
    Creates a CI with a PowerShell discovery script that reports non-persistent cache
    size in MB, and a remediation script that clears non-persistent cache elements.
    Content flagged "Persist in client cache" (0x200) is never touched.

    The CI is added to a new Configuration Baseline. The baseline is NOT deployed
    automatically -- deploy it manually or pass -CollectionName to auto-deploy.

.PARAMETER SiteCode
    MECM site code. Defaults to reading from PSDrive if already connected.

.PARAMETER SiteServer
    MECM site server FQDN. Required if ConfigurationManager module is not already loaded.

.PARAMETER ThresholdGB
    Non-persistent cache size threshold in GB. Discovery reports non-compliant when
    exceeded. Default: 20.

.PARAMETER CollectionName
    If specified, deploys the baseline to this collection with weekly schedule and
    remediation enabled. If omitted, the baseline is created but not deployed.

.EXAMPLE
    .\New-CCMCacheCleanupBaseline.ps1 -SiteServer sccm01.contoso.com -SiteCode MCM

.EXAMPLE
    .\New-CCMCacheCleanupBaseline.ps1 -SiteServer sccm01.contoso.com -SiteCode MCM -CollectionName "All Workstations"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SiteCode,

    [Parameter(Mandatory)]
    [string]$SiteServer,

    [int]$ThresholdGB = 20,

    [string]$CollectionName
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# Scripts (embedded as strings for the CI)
# ============================================================================

$DiscoveryScript = @'
$CMObject = New-Object -ComObject UIResource.UIResourceMgr
$Cache = $CMObject.GetCacheInfo()
$NonPersistent = $Cache.GetCacheElements() | Where-Object { -not ($_.ContentFlags -band 0x200) }
$SizeMB = ($NonPersistent | Measure-Object -Property ContentSize -Sum).Sum
if ($null -eq $SizeMB) { $SizeMB = 0 }
[math]::Round($SizeMB / 1024)
'@

$RemediationScript = @'
$CMObject = New-Object -ComObject UIResource.UIResourceMgr
$Cache = $CMObject.GetCacheInfo()
$Cache.GetCacheElements() | Where-Object { -not ($_.ContentFlags -band 0x200) } | ForEach-Object {
    $Cache.DeleteCacheElement($_.CacheElementID)
}
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
    $ThresholdMB = $ThresholdGB * 1024
    $CIName = "CCM Cache Cleanup - Non-Persistent Content"
    $CBName = "CCM Cache Cleanup"
    $SettingName = "NonPersistentCacheSizeMB"
    $RuleName = "Cache size within ${ThresholdGB}GB limit"

    # ========================================================================
    # Create Configuration Item
    # ========================================================================

    Write-Host "Creating Configuration Item: $CIName"

    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Reports non-persistent CCM cache size in MB. Remediates by clearing non-persistent cache elements. Content marked 'Persist in client cache' is never removed." `
        -CreationType WindowsOS

    Write-Host "  Adding script compliance setting..."

    Add-CMComplianceSettingScript `
        -InputObject $ci `
        -Name $SettingName `
        -Description "Returns non-persistent cache size in MB" `
        -DataType Integer `
        -DiscoveryScriptLanguage PowerShell `
        -DiscoveryScriptText $DiscoveryScript `
        -RemediationScriptLanguage PowerShell `
        -RemediationScriptText $RemediationScript `
        -Is64Bit `
        -NoRule

    Write-Host "  Adding compliance rule..."

    # Get the setting object from the CI to pass to New-CMComplianceRuleValue
    $ci = Get-CMConfigurationItem -Name $CIName -Fast
    $setting = $ci | Get-CMComplianceSetting -SettingName $SettingName

    $setting | New-CMComplianceRuleValue `
        -RuleName $RuleName `
        -ExpressionOperator LessEquals `
        -ExpectedValue $ThresholdMB `
        -NoncomplianceSeverity Warning `
        -Remediate `
        -ReportNoncompliance

    Write-Host "  CI created successfully." -ForegroundColor Green

    # ========================================================================
    # Create Configuration Baseline
    # ========================================================================

    Write-Host "Creating Configuration Baseline: $CBName"

    New-CMBaseline `
        -Name $CBName `
        -Description "Weekly cleanup of non-persistent CCM cache content exceeding ${ThresholdGB}GB. VPN/ZPA and other persistent content is preserved."

    Set-CMBaseline -Name $CBName -AddOSConfigurationItem $ci.CI_ID

    Write-Host "  Baseline created successfully." -ForegroundColor Green

    # ========================================================================
    # Deploy (optional)
    # ========================================================================

    if ($CollectionName) {
        Write-Host "Deploying baseline to collection: $CollectionName"

        $schedule = New-CMSchedule -RecurInterval Days -RecurCount 7

        New-CMBaselineDeployment `
            -Name $CBName `
            -CollectionName $CollectionName `
            -EnableEnforcement $true `
            -OverrideServiceWindow $false `
            -GenerateAlert $false `
            -MonitoredByScom $false `
            -Schedule $schedule

        Write-Host "  Baseline deployed with weekly schedule, remediation enabled." -ForegroundColor Green
    }
    else {
        Write-Host ""
        Write-Host "Baseline created but NOT deployed. To deploy:" -ForegroundColor Yellow
        Write-Host "  1. Open MECM Console > Assets and Compliance > Compliance Settings > Configuration Baselines"
        Write-Host "  2. Right-click '$CBName' > Deploy"
        Write-Host "  3. Check 'Remediate noncompliant rules when supported'"
        Write-Host "  4. Target your workstation collection"
        Write-Host "  5. Set schedule to Simple (every 7 days)"
    }

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "CI:        $CIName"
    Write-Host "Baseline:  $CBName"
    Write-Host "Threshold: ${ThresholdGB}GB (${ThresholdMB}MB)"
    Write-Host "Preserves: Content with 'Persist in client cache' flag (0x200)"
    Write-Host "Cleans:    DeleteCacheElement (skips in-use content)"
}
finally {
    Set-Location $OriginalLocation
}
