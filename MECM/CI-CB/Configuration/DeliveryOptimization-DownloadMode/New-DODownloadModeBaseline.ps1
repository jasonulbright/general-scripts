<#
.SYNOPSIS
    Creates MECM CIs + Baselines that enforce the Delivery Optimization download
    mode, with a different expected value for clients vs. servers.

.DESCRIPTION
    Single native registry-value compliance setting per OS class:

        HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization
            DODownloadMode = 0   (DWORD)  -- Windows 10 / 11 clients
            DODownloadMode = 99  (DWORD)  -- Windows Server

    No embedded scripts. MECM handles discovery, comparison, and remediation natively.

    Why two artifacts:
        A single registry value rule can only assert one expected value. Clients and
        servers need different values, so this builds two CIs (one per value) wrapped
        in two baselines, each deployed to its own collection. Deploying a single
        combined baseline would mark every server non-compliant against the client
        rule (and vice versa). This mirrors the Intel SpecExec control, which also
        splits by OS class across separate collections.

    Download mode meanings (per the DeliveryOptimization Policy CSP):
        0  = HTTP only, no peering. Uses DO cloud metadata for a peerless but
             reliable/efficient download. Standard "no P2P" posture for clients.
        99 = HTTP only, no peering, AND no use of the DO cloud service. Plain HTTP
             from the original source / Microsoft. Appropriate for servers, which
             have no business peering and often sit where DO cloud reachability is
             undesirable.
        (Do NOT use 100 / Bypass -- deprecated in Windows 11 and causes some content
         to fail with 0x80d03002.)

    GP-backed value, so it survives gpupdate cycles. No reboot required; takes effect
    on the next DO download.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER ClientCollectionName
    If specified, deploys the client baseline (DODownloadMode = ClientDownloadMode)
    to this collection daily with remediation enabled. Target a client-only
    collection (e.g. "All Workstations").

.PARAMETER ServerCollectionName
    If specified, deploys the server baseline (DODownloadMode = ServerDownloadMode)
    to this collection daily with remediation enabled. Target a server-only
    collection (e.g. "All Windows Servers").

.PARAMETER ClientDownloadMode
    Expected DODownloadMode value for clients. Default: 0.

.PARAMETER ServerDownloadMode
    Expected DODownloadMode value for servers. Default: 99.

.PARAMETER DetectOnly
    Create the CIs / deploy without remediation (audit mode).

.EXAMPLE
    .\New-DODownloadModeBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.local `
        -ClientCollectionName "All Workstations" -ServerCollectionName "All Windows Servers"

.EXAMPLE
    # Audit only, no deployment yet:
    .\New-DODownloadModeBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -DetectOnly
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SiteCode,

    [Parameter(Mandatory)]
    [string]$SiteServer,

    [string]$ClientCollectionName,

    [string]$ServerCollectionName,

    [ValidateSet('0', '1', '2', '3', '99')]
    [string]$ClientDownloadMode = '0',

    [ValidateSet('0', '1', '2', '3', '99')]
    [string]$ServerDownloadMode = '99',

    [switch]$DetectOnly
)

$ErrorActionPreference = 'Stop'

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

# ============================================================================
# Helper: build one CI + one Baseline for a given OS class / expected value,
#         and optionally deploy it to a collection.
# ============================================================================

function New-DODownloadModeControl {
    param(
        [string]$OsClass,          # 'Client' or 'Server' -- naming + description only
        [string]$ExpectedValue,    # DODownloadMode value to enforce
        [string]$CollectionName,   # deploy target, or empty to skip deployment
        [bool]  $Detect            # detect-only?
    )

    $KeyPath = 'SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
    $CIName  = "Delivery Optimization: DODownloadMode ($OsClass)"
    $CBName  = "Delivery Optimization DODownloadMode ($OsClass)"

    Write-Host "Creating Configuration Item: $CIName"

    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Enforces HKLM\$KeyPath\DODownloadMode = $ExpectedValue on $OsClass hosts. Controls Delivery Optimization peering / source behavior." `
        -CreationType WindowsOS

    Write-Host "  Adding setting: DODownloadMode = $ExpectedValue"

    $settingParams = @{
        InputObject           = $ci
        Name                  = 'DODownloadMode'
        Description           = "Delivery Optimization download mode. $ExpectedValue enforced for $OsClass."
        Hive                  = 'LocalMachine'
        KeyName               = $KeyPath
        ValueName             = 'DODownloadMode'
        DataType              = 'Integer'
        Is64Bit               = $true
        ValueRule             = $true
        RuleName              = "DODownloadMode equals $ExpectedValue"
        ExpressionOperator    = 'IsEquals'
        ExpectedValue         = $ExpectedValue
        NoncomplianceSeverity = 'Warning'
        ReportNoncompliance   = $true
        RemediateDword        = $true
    }
    if (-not $Detect) { $settingParams.Remediate = $true }

    Add-CMComplianceSettingRegistryKeyValue @settingParams

    Write-Host "  CI created." -ForegroundColor Green

    $ci = Get-CMConfigurationItem -Name $CIName -Fast

    Write-Host "Creating Configuration Baseline: $CBName"

    New-CMBaseline `
        -Name $CBName `
        -Description "Enforces Delivery Optimization DODownloadMode = $ExpectedValue on targeted $OsClass hosts."

    Set-CMBaseline -Name $CBName -AddOSConfigurationItem $ci.CI_ID

    Write-Host "  Baseline created." -ForegroundColor Green

    if ($CollectionName) {
        Write-Host "Deploying baseline to: $CollectionName"

        $schedule = New-CMSchedule -RecurInterval Days -RecurCount 1

        New-CMBaselineDeployment `
            -Name $CBName `
            -CollectionName $CollectionName `
            -EnableEnforcement (-not $Detect) `
            -OverrideServiceWindow $false `
            -GenerateAlert $false `
            -MonitoredByScom $false `
            -Schedule $schedule

        $mode = if ($Detect) { "DETECT ONLY" } else { "DETECT + REMEDIATE" }
        Write-Host "  Deployed daily to '$CollectionName', mode: $mode" -ForegroundColor Green
    }
    else {
        Write-Host "  Baseline created but NOT deployed (no collection supplied for $OsClass)." -ForegroundColor Yellow
    }

    [pscustomobject]@{
        OsClass    = $OsClass
        CI         = $CIName
        Baseline   = $CBName
        Value      = $ExpectedValue
        Collection = if ($CollectionName) { $CollectionName } else { '(not deployed)' }
    }
}

try {
    $results = @(
        New-DODownloadModeControl -OsClass 'Client' -ExpectedValue $ClientDownloadMode `
            -CollectionName $ClientCollectionName -Detect $DetectOnly.IsPresent

        New-DODownloadModeControl -OsClass 'Server' -ExpectedValue $ServerDownloadMode `
            -CollectionName $ServerCollectionName -Detect $DetectOnly.IsPresent
    )

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Control:  Delivery Optimization Download Mode"
    Write-Host "Reg path: HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization\DODownloadMode"
    Write-Host "Mode:     $(if ($DetectOnly) { 'Detect only' } else { 'Detect + remediate' })"
    Write-Host ""
    $results | Format-Table OsClass, Value, CI, Baseline, Collection -AutoSize
}
finally {
    Set-Location $OriginalLocation
}
