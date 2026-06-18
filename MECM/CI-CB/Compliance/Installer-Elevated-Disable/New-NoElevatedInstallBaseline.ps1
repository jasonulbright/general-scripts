<#
.SYNOPSIS
    Creates an MECM CI + Baseline that disables Windows Installer
    AlwaysInstallElevated.

.DESCRIPTION
    Single native registry-value compliance setting (machine side):

        HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer
            AlwaysInstallElevated = 0 (DWORD)

    No embedded scripts. MECM handles discovery, comparison, and remediation natively.

    AlwaysInstallElevated lets any user install MSI packages with SYSTEM privileges.
    When enabled it is a textbook local privilege-escalation primitive (a standard user
    crafts a malicious MSI and gets SYSTEM). Elevation requires BOTH the HKLM and HKCU
    copies to be 1, so enforcing the HKLM machine policy to 0 is sufficient to neutralize
    it -- and the machine side is the one a CI can reliably manage. Easy to miss because
    it is buried in a rarely visited Installer policy node.

    NOTE: the matching per-user value lives at
        HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer\AlwaysInstallElevated
    A machine-targeted CI cannot evaluate HKCU per user; the HKLM=0 enforcement here
    breaks the elevation regardless of the HKCU value, which is the point.

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
    .\New-NoElevatedInstallBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.local -CollectionName "All Windows Devices"
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
    $CIName   = "Compliance: Windows Installer AlwaysInstallElevated Disable"
    $CBName   = "Compliance Installer AlwaysInstallElevated Disable"
    $Severity = 'Critical'

    $settings = @(
        @{ Name = 'AlwaysInstallElevated'
           KeyName = 'SOFTWARE\Policies\Microsoft\Windows\Installer'
           ValueName = 'AlwaysInstallElevated'
           Expected = '0'
           Description = 'Machine-side AlwaysInstallElevated. 0 = MSI packages do not install with elevated privileges.' }
    )

    Write-Host "Creating Configuration Item: $CIName"
    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Disables Windows Installer AlwaysInstallElevated (HKLM = 0). Removes a standard local privilege-escalation primitive (malicious MSI -> SYSTEM)." `
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
    New-CMBaseline -Name $CBName -Description "Enforces Windows Installer AlwaysInstallElevated = 0 on targeted Windows hosts."
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
    Write-Host "Note:     HKCU copy is per-user; HKLM=0 alone neutralizes elevation."
    $settings | ForEach-Object { Write-Host ("Setting:  HKLM\{0}\{1} = {2}" -f $_.KeyName, $_.ValueName, $_.Expected) }
}
finally {
    Set-Location $OriginalLocation
}
