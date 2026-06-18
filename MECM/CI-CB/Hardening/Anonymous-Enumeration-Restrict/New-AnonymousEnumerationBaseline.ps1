<#
.SYNOPSIS
    Creates an MECM CI + Baseline that restricts anonymous (null-session) enumeration.

.DESCRIPTION
    Three native registry-value compliance settings (no embedded scripts), all under:

        HKLM\SYSTEM\CurrentControlSet\Control\Lsa
            RestrictAnonymous        = 1 (DWORD)   -- no anonymous SAM/share enumeration
            RestrictAnonymousSAM     = 1 (DWORD)   -- no anonymous SAM account enumeration
            EveryoneIncludesAnonymous = 0 (DWORD)  -- Everyone token excludes anonymous

    MECM handles discovery, comparison, and remediation natively.

    Anonymous / null-session enumeration lets an unauthenticated attacker list local
    accounts, groups, and shares -- prime reconnaissance for password spraying and
    lateral movement. These three values are classic CIS / STIG items that are easy to
    miss because the exposure is silent: nothing breaks, but the host quietly answers
    null-session queries.

    No reboot required.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER CollectionName
    If specified, deploys the baseline to this collection daily with remediation enabled.

.PARAMETER DetectOnly
    Create / deploy without remediation (audit mode).

.EXAMPLE
    .\New-AnonymousEnumerationBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -CollectionName "All Windows Devices"
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
    $CIName   = "Hardening: Anonymous Enumeration Restrictions"
    $CBName   = "Hardening Anonymous Enumeration Restrictions"
    $Severity = 'Critical'

    $settings = @(
        @{ Name = 'RestrictAnonymous'
           KeyName = 'SYSTEM\CurrentControlSet\Control\Lsa'
           ValueName = 'RestrictAnonymous'
           Expected = '1'
           Description = 'No anonymous enumeration of SAM accounts and shares. 1 = restricted.' }

        @{ Name = 'RestrictAnonymousSAM'
           KeyName = 'SYSTEM\CurrentControlSet\Control\Lsa'
           ValueName = 'RestrictAnonymousSAM'
           Expected = '1'
           Description = 'No anonymous enumeration of SAM accounts. 1 = restricted.' }

        @{ Name = 'EveryoneIncludesAnonymous'
           KeyName = 'SYSTEM\CurrentControlSet\Control\Lsa'
           ValueName = 'EveryoneIncludesAnonymous'
           Expected = '0'
           Description = 'Everyone permissions do NOT apply to anonymous users. 0 = excluded.' }
    )

    Write-Host "Creating Configuration Item: $CIName"
    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Restricts anonymous (null-session) enumeration of accounts, groups, and shares. RestrictAnonymous=1, RestrictAnonymousSAM=1, EveryoneIncludesAnonymous=0. Blocks unauthenticated recon." `
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
    New-CMBaseline -Name $CBName -Description "Enforces anonymous enumeration restrictions on targeted Windows hosts."
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
    Write-Host "Mode:     $(if ($DetectOnly) { 'Detect only' } else { 'Detect + remediate' })"
    $settings | ForEach-Object { Write-Host ("Setting:  HKLM\{0}\{1} = {2}" -f $_.KeyName, $_.ValueName, $_.Expected) }
}
finally {
    Set-Location $OriginalLocation
}
