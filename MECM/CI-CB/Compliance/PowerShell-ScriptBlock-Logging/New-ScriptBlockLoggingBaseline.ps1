<#
.SYNOPSIS
    Creates an MECM CI + Baseline that enables PowerShell Script Block Logging.

.DESCRIPTION
    Single native registry-value compliance setting:

        HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging
            EnableScriptBlockLogging = 1 (DWORD)

    No embedded scripts. MECM handles discovery, comparison, and remediation natively.

    Script Block Logging records the de-obfuscated content of every PowerShell script
    block to the Microsoft-Windows-PowerShell/Operational log (event 4104). It is the
    single most useful PowerShell forensic / detection control and is almost universally
    missing from homegrown baselines -- it is a detective control, so its absence is
    invisible until you need the logs and they aren't there.

    No reboot required.

    NOTE: this is detective only -- it does not block anything, so it is safe to enable
    broadly. Ensure downstream log collection (WEF / SIEM agent) is actually gathering
    the PowerShell/Operational channel, or the events stay local.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER CollectionName
    If specified, deploys the baseline to this collection daily with remediation enabled.

.PARAMETER DetectOnly
    Create / deploy without remediation (audit mode).

.EXAMPLE
    .\New-ScriptBlockLoggingBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -CollectionName "All Windows Devices"
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
    $CIName   = "Compliance: PowerShell Script Block Logging"
    $CBName   = "Compliance PowerShell Script Block Logging"
    $Severity = 'Warning'

    $settings = @(
        @{ Name = 'EnableScriptBlockLogging'
           KeyName = 'SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
           ValueName = 'EnableScriptBlockLogging'
           Expected = '1'
           Description = 'PowerShell script block logging. 1 = log de-obfuscated script blocks (event 4104).' }
    )

    Write-Host "Creating Configuration Item: $CIName"
    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Enables PowerShell Script Block Logging (EnableScriptBlockLogging = 1) for detection/forensics (event 4104). Detective only; safe to enable broadly. Verify log collection downstream." `
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
    New-CMBaseline -Name $CBName -Description "Enforces PowerShell Script Block Logging on targeted Windows hosts."
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
