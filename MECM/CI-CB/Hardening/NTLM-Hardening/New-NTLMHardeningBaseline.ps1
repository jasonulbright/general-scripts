<#
.SYNOPSIS
    Creates an MECM CI + Baseline that enforces NTLMv2-only authentication.

.DESCRIPTION
    Single native registry-value compliance setting:

        HKLM\SYSTEM\CurrentControlSet\Control\Lsa
            LmCompatibilityLevel = 5 (DWORD)

    No embedded scripts. MECM handles discovery, comparison, and remediation natively.

    LmCompatibilityLevel = 5 means "Send NTLMv2 response only; refuse LM & NTLM."
    LM and NTLMv1 are trivially crackable / relayable; leaving the level low (or unset,
    which historically defaulted to permissive behavior) is a common gap because nothing
    breaks visibly when weak protocols are allowed. Pin it to 5 on managed hosts.

    No reboot required.

    CAUTION: refusing LM/NTLMv1 can break authentication to very old appliances / NAS /
    legacy line-of-business hosts that never learned NTLMv2. Run -DetectOnly first and
    review non-compliant + dependent systems before enforcing.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER CollectionName
    If specified, deploys the baseline to this collection daily with remediation enabled.

.PARAMETER DetectOnly
    Create / deploy without remediation (audit mode).

.EXAMPLE
    .\New-NTLMHardeningBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -DetectOnly
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
    $CIName   = "Hardening: NTLM LmCompatibilityLevel"
    $CBName   = "Hardening NTLM LmCompatibilityLevel"
    $Severity = 'Critical'

    $settings = @(
        @{ Name = 'LmCompatibilityLevel'
           KeyName = 'SYSTEM\CurrentControlSet\Control\Lsa'
           ValueName = 'LmCompatibilityLevel'
           Expected = '5'
           Description = 'Authentication level. 5 = Send NTLMv2 only; refuse LM and NTLM.' }
    )

    Write-Host "Creating Configuration Item: $CIName"
    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Enforces NTLMv2-only authentication (LmCompatibilityLevel = 5; refuse LM & NTLMv1). Mitigates trivially crackable/relayable legacy auth. Test against legacy appliances before enforcing." `
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
    New-CMBaseline -Name $CBName -Description "Enforces NTLMv2-only authentication on targeted Windows hosts."
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
