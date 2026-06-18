<#
.SYNOPSIS
    Creates an MECM CI + Baseline that enables LSA Protection (RunAsPPL).

.DESCRIPTION
    Single native registry-value compliance setting:

        HKLM\SYSTEM\CurrentControlSet\Control\Lsa
            RunAsPPL = 1 (DWORD)

    No embedded scripts. MECM handles discovery, comparison, and remediation natively.

    RunAsPPL runs LSASS as a Protected Process Light, blocking non-PPL processes
    (including most credential-dumping tooling) from opening a handle to LSASS memory.
    It is one of the highest-value, lowest-cost anti-credential-theft controls and is
    almost always missed -- it ships disabled and there is no nag to turn it on.

    REBOOT REQUIRED: protection engages on the next boot. MECM will remediate the value
    but the host is not actually protected until it restarts. Validate driver/plugin
    compatibility (some smartcard / AV LSA plugins must be PPL-signed) before broad
    enforcement.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER CollectionName
    If specified, deploys the baseline to this collection daily with remediation enabled.

.PARAMETER DetectOnly
    Create / deploy without remediation (audit mode). Recommended for an initial pass
    to find hosts missing the value before flipping on enforcement.

.EXAMPLE
    .\New-LSAProtectionBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -DetectOnly
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
    $CIName   = "Hardening: LSA Protection (RunAsPPL)"
    $CBName   = "Hardening LSA Protection RunAsPPL"
    $Severity = 'Critical'

    $settings = @(
        @{ Name = 'RunAsPPL'
           KeyName = 'SYSTEM\CurrentControlSet\Control\Lsa'
           ValueName = 'RunAsPPL'
           Expected = '1'
           Description = 'LSA Protection. 1 = LSASS runs as a Protected Process Light. Effective after reboot.' }
    )

    Write-Host "Creating Configuration Item: $CIName"
    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Enables LSA Protection (RunAsPPL = 1) so LSASS runs as a Protected Process Light, blocking credential-dumping tools. Effective after reboot. Validate LSA plugin signing before broad enforcement." `
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
    New-CMBaseline -Name $CBName -Description "Enforces LSA Protection (RunAsPPL) on targeted Windows hosts. Reboot required to take effect."
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
    Write-Host "Reboot:   REQUIRED to engage protection"
    Write-Host "Mode:     $(if ($DetectOnly) { 'Detect only' } else { 'Detect + remediate' })"
    $settings | ForEach-Object { Write-Host ("Setting:  HKLM\{0}\{1} = {2}" -f $_.KeyName, $_.ValueName, $_.Expected) }
}
finally {
    Set-Location $OriginalLocation
}
