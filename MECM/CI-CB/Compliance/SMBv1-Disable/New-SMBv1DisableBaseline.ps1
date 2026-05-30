<#
.SYNOPSIS
    Creates an MECM CI + Baseline that disables the SMBv1 server protocol.

.DESCRIPTION
    Single native registry-value compliance setting:

        HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters
            SMB1 = 0 (DWORD)

    Scope intentionally limited to the server-side reg control. The SMBv1 client
    redirector (mrxsmb10) is removed entirely as a Windows feature on Windows 10
    1709+ and Windows Server 2019+; a separate CI targeting legacy OSes can layer
    on if and when needed. For the supported-OS fleet that's the practical case,
    this one DWORD is the universal "SMBv1 server is off" signal.

    No embedded scripts. MECM handles discovery, comparison, and remediation natively.

    Per Microsoft guidance:
    https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER CollectionName
    If specified, deploys the baseline to this collection daily with remediation enabled.

.PARAMETER DetectOnly
    Create the CI without remediation.

.EXAMPLE
    .\New-SMBv1DisableBaseline.ps1 -SiteServer CM01.contoso.local -SiteCode MCM -CollectionName "All Desktop and Server Clients"
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
    $CIName  = "Compliance: SMBv1 Disable"
    $CBName  = "Compliance SMBv1 Disable"
    $KeyPath = 'SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'

    Write-Host "Creating Configuration Item: $CIName"

    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Disables the SMBv1 server protocol by setting HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters\SMB1 = 0. Server-side scope; client-side mrxsmb10 is Windows-feature-removed on Win10 1709+ / Server 2019+." `
        -CreationType WindowsOS

    Write-Host "  Adding setting: SMB1 = 0"

    $settingParams = @{
        InputObject           = $ci
        Name                  = 'SMB1'
        Description           = 'SMBv1 server protocol enablement. 0 = disabled.'
        Hive                  = 'LocalMachine'
        KeyName               = $KeyPath
        ValueName             = 'SMB1'
        DataType              = 'Integer'
        Is64Bit               = $true
        ValueRule             = $true
        RuleName              = 'SMB1 equals 0'
        ExpressionOperator    = 'IsEquals'
        ExpectedValue         = '0'
        NoncomplianceSeverity = 'Critical'
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
        -Description "Enforces SMBv1 server disable. CIS / DISA STIG mapped. Tenable plugin 96982 / similar."

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
    Write-Host "Control:   SMBv1 Server Disable"
    Write-Host "CI:        $CIName"
    Write-Host "Baseline:  $CBName"
    Write-Host "Mode:      $(if ($DetectOnly) { 'Detect only' } else { 'Detect + remediate' })"
    Write-Host "Reg path:  HKLM\$KeyPath"
    Write-Host "Setting:   SMB1 = 0"
}
finally {
    Set-Location $OriginalLocation
}
