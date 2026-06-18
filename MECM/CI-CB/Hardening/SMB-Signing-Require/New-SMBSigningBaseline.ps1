<#
.SYNOPSIS
    Creates an MECM CI + Baseline that requires SMB signing on both the
    Workstation (client) and Server services.

.DESCRIPTION
    Two native registry-value compliance settings (no embedded scripts):

        HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters
            RequireSecuritySignature = 1 (DWORD)   -- outbound / client side

        HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters
            RequireSecuritySignature = 1 (DWORD)   -- inbound / server side

    MECM handles discovery, comparison, and remediation natively.

    Required SMB signing defeats SMB relay / man-in-the-middle attacks (a primary
    lateral-movement and privilege-escalation path, e.g. via Responder + ntlmrelayx).
    It is commonly missed because the default is "enabled but not required," which still
    permits unsigned sessions to be downgraded. Requiring it on both sides closes the gap.

    No reboot required (LanmanServer/Workstation pick up the change on service refresh;
    a reboot guarantees it).

    CAUTION: requiring signing can affect throughput on very old/embedded SMB clients and
    breaks SMB to devices that cannot sign. Run -DetectOnly first.

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER CollectionName
    If specified, deploys the baseline to this collection daily with remediation enabled.

.PARAMETER DetectOnly
    Create / deploy without remediation (audit mode).

.EXAMPLE
    .\New-SMBSigningBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -DetectOnly
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
    $CIName   = "Hardening: SMB Signing Required"
    $CBName   = "Hardening SMB Signing Required"
    $Severity = 'Critical'

    $settings = @(
        @{ Name = 'WorkstationRequireSigning'
           KeyName = 'SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
           ValueName = 'RequireSecuritySignature'
           Expected = '1'
           Description = 'SMB client requires signing. 1 = required.' }

        @{ Name = 'ServerRequireSigning'
           KeyName = 'SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
           ValueName = 'RequireSecuritySignature'
           Expected = '1'
           Description = 'SMB server requires signing. 1 = required.' }
    )

    Write-Host "Creating Configuration Item: $CIName"
    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Requires SMB signing on both the Workstation and Server services (RequireSecuritySignature = 1). Defeats SMB relay / MITM lateral movement. Test legacy/embedded SMB peers before enforcing." `
        -CreationType WindowsOS

    foreach ($s in $settings) {
        Write-Host "  Adding setting: $($s.Name) ($($s.ValueName) = $($s.Expected))"
        $p = @{
            InputObject = $ci; Name = $s.Name; Description = $s.Description; Hive = 'LocalMachine'
            KeyName = $s.KeyName; ValueName = $s.ValueName; DataType = 'Integer'; Is64Bit = $true
            ValueRule = $true; RuleName = "$($s.Name) equals $($s.Expected)"
            ExpressionOperator = 'IsEquals'; ExpectedValue = $s.Expected
            NoncomplianceSeverity = $Severity; ReportNoncompliance = $true; RemediateDword = $true
        }
        if (-not $DetectOnly) { $p.Remediate = $true }
        Add-CMComplianceSettingRegistryKeyValue @p
    }
    Write-Host "  CI created." -ForegroundColor Green

    $ci = Get-CMConfigurationItem -Name $CIName -Fast

    Write-Host "Creating Configuration Baseline: $CBName"
    New-CMBaseline -Name $CBName -Description "Enforces required SMB signing (client + server) on targeted Windows hosts."
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
