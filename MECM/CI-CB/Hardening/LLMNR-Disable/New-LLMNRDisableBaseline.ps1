<#
.SYNOPSIS
    Creates an MECM CI + Baseline that disables LLMNR via the DNSClient policy.

.DESCRIPTION
    Single native registry-value compliance setting:

        HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient
            EnableMulticast = 0 (DWORD)

    No embedded scripts. MECM handles discovery, comparison, and remediation natively.

    Disabling LLMNR is a baseline hardening control that prevents Responder-style
    name-resolution poisoning attacks. There is no operational reason to leave it
    enabled on managed hosts -- DNS handles all legitimate name resolution.

    Same reg surface across Windows 7 / Server 2008 R2 forward. No reboot required.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER CollectionName
    If specified, deploys the baseline to this collection daily with remediation enabled.

.PARAMETER DetectOnly
    Create the CI without remediation.

.EXAMPLE
    .\New-LLMNRDisableBaseline.ps1 -SiteServer CM01.contoso.local -SiteCode MCM -CollectionName "All Desktop and Server Clients"
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
    $CIName  = "Hardening: LLMNR Disable"
    $CBName  = "Hardening LLMNR Disable"
    $KeyPath = 'SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'

    Write-Host "Creating Configuration Item: $CIName"

    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Disables LLMNR by setting HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient\EnableMulticast = 0. Prevents Responder-style name-resolution poisoning attacks." `
        -CreationType WindowsOS

    Write-Host "  Adding setting: EnableMulticast = 0"

    $settingParams = @{
        InputObject           = $ci
        Name                  = 'EnableMulticast'
        Description           = 'LLMNR disable bit. 0 = LLMNR off.'
        Hive                  = 'LocalMachine'
        KeyName               = $KeyPath
        ValueName             = 'EnableMulticast'
        DataType              = 'Integer'
        Is64Bit               = $true
        ValueRule             = $true
        RuleName              = 'EnableMulticast equals 0'
        ExpressionOperator    = 'IsEquals'
        ExpectedValue         = '0'
        NoncomplianceSeverity = 'Warning'
        ReportNoncompliance   = $true
        RemediateDword        = $true
    }
    if (-not $DetectOnly) { $settingParams.Remediate = $true }

    Add-CMComplianceSettingRegistryKeyValue @settingParams

    Write-Host "  CI created." -ForegroundColor Green

    $ci = Get-CMConfigurationItem -Name $CIName -Fast

    Write-Host "Creating Configuration Baseline: $CBName"

    New-CMBaseline `
        -Name $CBName `
        -Description "Enforces LLMNR disable on targeted Windows hosts. Hardening / defense-in-depth control."

    Set-CMBaseline -Name $CBName -AddOSConfigurationItem $ci.CI_ID

    Write-Host "  Baseline created." -ForegroundColor Green

    if ($CollectionName) {
        Write-Host "Deploying baseline to: $CollectionName"

        $schedule = New-CMSchedule -RecurInterval Days -RecurCount 1

        New-CMBaselineDeployment `
            -Name $CBName `
            -CollectionName $CollectionName `
            -EnableEnforcement (-not $DetectOnly) `
            -OverrideServiceWindow $false `
            -GenerateAlert $false `
            -MonitoredByScom $false `
            -Schedule $schedule

        $mode = if ($DetectOnly) { "DETECT ONLY" } else { "DETECT + REMEDIATE" }
        Write-Host "  Deployed daily, mode: $mode" -ForegroundColor Green
    }
    else {
        Write-Host ""
        Write-Host "Baseline created but NOT deployed. Re-run with -CollectionName." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Control:   LLMNR Disable"
    Write-Host "CI:        $CIName"
    Write-Host "Baseline:  $CBName"
    Write-Host "Mode:      $(if ($DetectOnly) { 'Detect only' } else { 'Detect + remediate' })"
    Write-Host "Reg path:  HKLM\$KeyPath"
    Write-Host "Setting:   EnableMulticast = 0"
}
finally {
    Set-Location $OriginalLocation
}
