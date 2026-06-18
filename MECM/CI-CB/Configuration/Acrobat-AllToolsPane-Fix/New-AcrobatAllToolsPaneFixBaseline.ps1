<#
.SYNOPSIS
    Creates an MECM CI + Baseline that applies Adobe's registry workaround for the
    Acrobat "All Tools pane disappears / empty when selecting Edit PDF" bug.

.DESCRIPTION
    Single native registry-value compliance setting:

        HKLM\SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown
            bGenCoverPagesLabelStrings = 1 (DWORD)

    No embedded scripts. MECM handles discovery, comparison, and remediation natively.

    TEMPORARY WORKAROUND for a confirmed Adobe Acrobat defect: the All Tools pane goes
    blank / disappears when the user clicks Edit PDF. Per Adobe's accepted answer
    (community thread below), creating this FeatureLockDown DWORD restores the pane.
    Adobe has stated a permanent patch is planned -- retire this baseline once the fixed
    Acrobat build is deployed.

    Source: https://community.adobe.com/questions-9/all-tools-pane-disappears-empty-when-i-select-edit-pdf-1628319

    REBOOT / RESTART REQUIRED: per Adobe's guidance, restart Acrobat and the machine after
    the value is set. MECM remediates the value; the user does not see the fix until
    Acrobat (and ideally the host) restarts.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER CollectionName
    If specified, deploys the baseline to this collection daily with remediation enabled.
    Target a collection of machines that have Acrobat installed.

.PARAMETER DetectOnly
    Create / deploy without remediation (audit mode).

.EXAMPLE
    .\New-AcrobatAllToolsPaneFixBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -CollectionName "All Windows Devices"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SiteCode,

    [Parameter(Mandatory)]
    [string]$SiteServer,

    [string]$CollectionName,

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

try {
    $CIName   = "Configuration: Acrobat All Tools Pane Fix"
    $CBName   = "Configuration Acrobat All Tools Pane Fix"
    $Severity = 'Warning'

    $settings = @(
        @{ Name = 'bGenCoverPagesLabelStrings'
           KeyName = 'SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown'
           ValueName = 'bGenCoverPagesLabelStrings'
           Expected = '1'
           Description = 'Adobe FeatureLockDown workaround flag. 1 = restores the All Tools pane on Edit PDF.' }
    )

    Write-Host "Creating Configuration Item: $CIName"
    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Temporary Adobe-supplied workaround for the Acrobat All Tools pane disappearing on Edit PDF (bGenCoverPagesLabelStrings = 1). Retire once Adobe ships the permanent patch. Requires Acrobat/host restart to take effect." `
        -CreationType WindowsOS

    foreach ($s in $settings) {
        Write-Host "  Adding setting: $($s.ValueName) = $($s.Expected)"
        $p = @{
            InputObject = $ci; Name = $s.Name; Description = $s.Description; Hive = 'LocalMachine'
            KeyName = $s.KeyName; ValueName = $s.ValueName; DataType = 'Integer'; Is64Bit = $true
            ValueRule = $true; RuleName = "$($s.ValueName) equals $($s.Expected)"
            ExpressionOperator = 'IsEquals'; ExpectedValue = $s.Expected
            NoncomplianceSeverity = $Severity; ReportNoncompliance = $true; RemediateDword = $true
        }
        if (-not $DetectOnly) { $p.Remediate = $true }
        Add-CMComplianceSettingRegistryKeyValue @p
    }
    Write-Host "  CI created." -ForegroundColor Green

    $ci = Get-CMConfigurationItem -Name $CIName -Fast

    Write-Host "Creating Configuration Baseline: $CBName"
    New-CMBaseline -Name $CBName -Description "Applies the Adobe Acrobat All Tools pane workaround on targeted Windows hosts. Temporary; retire after Adobe's patch."
    Set-CMBaseline -Name $CBName -AddOSConfigurationItem $ci.CI_ID
    Write-Host "  Baseline created." -ForegroundColor Green

    if ($CollectionName) {
        Write-Host "Deploying baseline to: $CollectionName"
        $schedule = New-CMSchedule -RecurInterval Days -RecurCount 1
        New-CMBaselineDeployment `
            -Name $CBName -CollectionName $CollectionName `
            -EnableEnforcement (-not $DetectOnly) -OverrideServiceWindow $false `
            -GenerateAlert $false -MonitoredByScom $false -Schedule $schedule
        $mode = if ($DetectOnly) { "DETECT ONLY" } else { "DETECT + REMEDIATE" }
        Write-Host "  Deployed daily, mode: $mode" -ForegroundColor Green
    }
    else {
        Write-Host "  Baseline created but NOT deployed. Re-run with -CollectionName." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "CI:       $CIName"
    Write-Host "Baseline: $CBName"
    Write-Host "Severity: $Severity"
    Write-Host "Reboot:   Restart Acrobat + host to apply"
    Write-Host "Note:     TEMPORARY -- retire after Adobe ships the permanent patch"
    Write-Host "Mode:     $(if ($DetectOnly) { 'Detect only' } else { 'Detect + remediate' })"
    $settings | ForEach-Object { Write-Host ("Setting:  HKLM\{0}\{1} = {2}" -f $_.KeyName, $_.ValueName, $_.Expected) }
}
finally {
    Set-Location $OriginalLocation
}
