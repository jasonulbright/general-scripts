<#
.SYNOPSIS
    Creates an MECM CI + Baseline that requires RDP Network Level Authentication
    and TLS security.

.DESCRIPTION
    Two native registry-value compliance settings (no embedded scripts), both under:

        HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp
            UserAuthentication = 1 (DWORD)   -- require NLA (CredSSP before session)
            SecurityLayer      = 2 (DWORD)   -- require TLS for the RDP transport

    MECM handles discovery, comparison, and remediation natively.

    NLA forces authentication before a session (and its logon screen) is created,
    blocking pre-auth RDP attack surface and a class of DoS / exploit vectors. SecurityLayer
    = 2 forces TLS rather than the legacy RDP Security Layer. Both are standard hardening
    items that are easy to miss because RDP "works" without them.

    The RDP-Tcp WinStation key exists on all Windows hosts even when RDP is disabled, so
    enforcing these values is harmless on non-RDP machines and pre-hardens them if RDP is
    ever enabled -- which is why this targets all Windows devices rather than a scoped
    RDP-enabled collection.

    No reboot required (Terminal Services picks up the change on next connection / service
    refresh).

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER CollectionName
    If specified, deploys the baseline to this collection daily with remediation enabled.

.PARAMETER DetectOnly
    Create / deploy without remediation (audit mode).

.EXAMPLE
    .\New-RDPHardeningBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -CollectionName "All Windows Devices"
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
    $CIName   = "Compliance: RDP NLA + TLS Required"
    $CBName   = "Compliance RDP NLA TLS Required"
    $Severity = 'Critical'
    $KeyPath  = 'SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'

    $settings = @(
        @{ Name = 'UserAuthentication'
           KeyName = $KeyPath
           ValueName = 'UserAuthentication'
           Expected = '1'
           Description = 'Require Network Level Authentication (CredSSP) before an RDP session. 1 = required.' }

        @{ Name = 'SecurityLayer'
           KeyName = $KeyPath
           ValueName = 'SecurityLayer'
           Expected = '2'
           Description = 'RDP transport security. 2 = require TLS (SSL).' }
    )

    Write-Host "Creating Configuration Item: $CIName"
    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Requires RDP Network Level Authentication (UserAuthentication = 1) and TLS (SecurityLayer = 2). Removes pre-auth RDP attack surface and legacy RDP Security Layer." `
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
    New-CMBaseline -Name $CBName -Description "Enforces RDP NLA + TLS on targeted Windows hosts."
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
